import uuid

from rest_framework import viewsets, status
from rest_framework.decorators import action
from rest_framework.permissions import IsAuthenticated, AllowAny
from rest_framework.response import Response
from rest_framework.views import APIView
from django.http import HttpResponse

from .models import Paiement, DemandePaiement, CompteMarchand
from .serializers import (
    PaiementSerializer, DemandePaiementSerializer, CompteMarchandSerializer,
)
from .services import (
    appliquer_paiement, generer_quittance_pdf,
    exporter_paiements_pdf, exporter_paiements_excel,
    creer_demande_paiement, confirmer_demande_paiement,
)
from abonnements.providers import get_provider
from abonnements.permissions import AbonnementActif
from abonnements.services import exiger_pro


class PaiementViewSet(viewsets.ModelViewSet):
    serializer_class = PaiementSerializer
    permission_classes = [IsAuthenticated, AbonnementActif]

    def get_queryset(self):
        if getattr(self, 'swagger_fake_view', False):
            return Paiement.objects.none()
        queryset = Paiement.objects.filter(locataire__bailleur=self.request.user)
        locataire_id = self.request.query_params.get('locataire', None)
        if locataire_id is not None:
            queryset = queryset.filter(locataire_id=locataire_id)
        return queryset

    def perform_create(self, serializer):
        paiement = serializer.save()
        appliquer_paiement(paiement)

    @action(detail=True, methods=['get'])
    def quittance(self, request, pk=None):
        """Télécharge la quittance de loyer (PDF) pour ce paiement."""
        paiement = self.get_object()
        try:
            pdf = generer_quittance_pdf(paiement)
        except ImportError:
            return Response(
                {'error': "reportlab n'est pas installé sur le serveur."},
                status=status.HTTP_501_NOT_IMPLEMENTED,
            )
        response = HttpResponse(pdf, content_type='application/pdf')
        response['Content-Disposition'] = f'attachment; filename="quittance_{paiement.id}.pdf"'
        return response

    @action(detail=False, methods=['get'])
    def exporter(self, request):
        """Exporte la liste des paiements (filtrée) en PDF ou Excel.

        Paramètres : ?fmt=pdf|excel  &  ?mode=<mode_paiement> (optionnel,
        ex. 'Mobile Money')  & ?locataire=<id> (optionnel, géré par get_queryset).
        NB : on évite le nom `format` qui est réservé à la négociation DRF."""
        exiger_pro(request.user, 'comptabilite')
        qs = self.get_queryset().select_related('locataire')
        mode = request.query_params.get('mode')
        if mode:
            qs = qs.filter(mode_paiement=mode)

        fmt = (request.query_params.get('fmt') or 'pdf').lower()
        try:
            if fmt == 'excel':
                data = exporter_paiements_excel(qs)
                ct = 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet'
                ext = 'xlsx'
            else:
                data = exporter_paiements_pdf(qs)
                ct = 'application/pdf'
                ext = 'pdf'
        except ImportError:
            return Response(
                {'error': "Bibliothèque d'export (reportlab/openpyxl) absente du serveur."},
                status=status.HTTP_501_NOT_IMPLEMENTED,
            )
        response = HttpResponse(data, content_type=ct)
        response['Content-Disposition'] = f'attachment; filename="paiements.{ext}"'
        return response


class DemandePaiementViewSet(viewsets.ModelViewSet):
    """Demandes d'encaissement Mobile Money (loyer).

    POST crée la demande + le lien de paiement ; le locataire paie via ce lien,
    et le webhook confirme automatiquement (→ Paiement + statut Payé).
    """
    serializer_class = DemandePaiementSerializer
    permission_classes = [IsAuthenticated, AbonnementActif]
    http_method_names = ['get', 'post']

    def get_queryset(self):
        if getattr(self, 'swagger_fake_view', False):
            return DemandePaiement.objects.none()
        qs = DemandePaiement.objects.filter(locataire__bailleur=self.request.user)
        locataire_id = self.request.query_params.get('locataire')
        if locataire_id is not None:
            qs = qs.filter(locataire_id=locataire_id)
        return qs.select_related('locataire')

    def create(self, request, *args, **kwargs):
        serializer = self.get_serializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        locataire = serializer.validated_data['locataire']
        try:
            demande = creer_demande_paiement(locataire)
        except ValueError as e:
            messages = {
                'compte_marchand_non_configure': "Configurez d'abord votre compte marchand (Réglages).",
                'rien_a_encaisser': "Ce locataire est déjà à jour pour ce mois.",
            }
            return Response(
                {'error': messages.get(str(e), "Demande d'encaissement impossible.")},
                status=status.HTTP_400_BAD_REQUEST,
            )
        except Exception as e:
            return Response({'error': f"Échec de l'initialisation du paiement : {e}"},
                            status=status.HTTP_502_BAD_GATEWAY)
        return Response(self.get_serializer(demande).data, status=status.HTTP_201_CREATED)


class CompteMarchandView(APIView):
    """Config du compte marchand du bailleur (GET état, PUT enregistre)."""
    permission_classes = [IsAuthenticated]

    def get(self, request):
        compte = getattr(request.user, 'compte_marchand', None)
        if compte is None:
            return Response({'est_configure': False, 'actif': False})
        return Response(CompteMarchandSerializer(compte).data)

    def put(self, request):
        compte, _ = CompteMarchand.objects.get_or_create(bailleur=request.user)
        serializer = CompteMarchandSerializer(compte, data=request.data, partial=True)
        serializer.is_valid(raise_exception=True)
        serializer.save()
        return Response(CompteMarchandSerializer(compte).data)


class WebhookLoyerView(APIView):
    """Webhook prestataire pour l'encaissement des loyers (idempotent).

    On ne fait pas confiance au statut brut : on retrouve la demande puis on
    revérifie via l'API du prestataire (compte plateforme).
    """
    permission_classes = [AllowAny]

    def post(self, request):
        # Défense en profondeur (parité avec le webhook d'abonnement) : on rejette
        # une signature invalide si un secret est configuré. La revérification via
        # l'API du prestataire (verifier_paiement) reste la garantie principale.
        if not get_provider().verifier_signature(request):
            return Response({'error': 'Signature invalide'}, status=status.HTTP_403_FORBIDDEN)

        data = request.data if hasattr(request, 'data') else request.POST
        reference = data.get('cpm_trans_id') or data.get('transaction_id') or data.get('reference')
        if not reference:
            return Response({'error': 'Référence manquante'}, status=status.HTTP_400_BAD_REQUEST)

        # `reference_interne` est un UUIDField : filtrer avec une valeur non-UUID
        # (bot, scanner, retry mal formé) lèverait ValueError → 500. On la parse
        # d'abord ; une référence invalide ne correspond à aucune demande → 404.
        try:
            reference = uuid.UUID(str(reference))
        except (ValueError, AttributeError, TypeError):
            return Response({'error': 'Demande introuvable'}, status=status.HTTP_404_NOT_FOUND)

        demande = DemandePaiement.objects.filter(reference_interne=reference).select_related(
            'locataire__bailleur').first()
        if demande is None:
            return Response({'error': 'Demande introuvable'}, status=status.HTTP_404_NOT_FOUND)

        # Collecte centralisée : la vérification s'appuie sur le compte plateforme.
        if get_provider().verifier_paiement(reference, {}):
            confirmer_demande_paiement(demande)  # idempotent
            return Response({'status': 'paiement confirmé'})

        if demande.statut == 'en_attente':
            demande.statut = 'echouee'
            demande.payload = dict(data)
            demande.save(update_fields=['statut', 'payload'])
        return Response({'status': 'paiement non confirmé'})

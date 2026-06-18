from rest_framework import viewsets, status
from rest_framework.decorators import action
from rest_framework.response import Response
from rest_framework.permissions import IsAuthenticated, AllowAny
from rest_framework.parsers import MultiPartParser, FormParser
from rest_framework.views import APIView
from django.db.models import Sum
from django.http import HttpResponse
from django.utils import timezone
import threading
from .serializers import (
    LocataireSerializer, LocataireStatutSerializer, RappelSerializer, NotificationSerializer,
    HistoriqueLoyerSerializer, MouvementCautionSerializer, EtatDesLieuxSerializer,
    PhotoEtatDesLieuxSerializer,
)
from .models import (
    Locataire, Rappel, Notification,
    HistoriqueLoyer, MouvementCaution, EtatDesLieux, PhotoEtatDesLieux,
)
from .services import execute_rappel
from .tasks import verifier_echeances
from . import gestion
from abonnements.permissions import AbonnementActif, requiere_pro
from abonnements.services import exiger_pro

class LocataireViewSet(viewsets.ModelViewSet):
    serializer_class = LocataireSerializer
    permission_classes = [IsAuthenticated, AbonnementActif]

    def get_queryset(self):
        if getattr(self, 'swagger_fake_view', False):
            return Locataire.objects.none()
        qs = Locataire.objects.filter(bailleur=self.request.user, is_deleted=False)
        # Les locataires archivés (bail résilié) sont masqués sauf demande explicite
        if self.request.query_params.get('inclure_archives') not in ('1', 'true', 'True'):
            qs = qs.filter(archive=False)
        return qs

    def perform_create(self, serializer):
        serializer.save(bailleur=self.request.user)

    def perform_destroy(self, instance):
        instance.is_deleted = True
        instance.save()

    @action(detail=False, methods=['post', 'get'])
    def forcer_automatisations(self, request):
        from penalites.tasks import calculer_penalites
        verifier_echeances()
        calculer_penalites()
        return Response({'status': 'Tâches d\'automatisation (J-5, J-1, Pénalités) exécutées avec succès !'})

    @action(detail=True, methods=['post'])
    def demarrer_test(self, request, pk=None):
        """Lance un cycle de test rapide pour un locataire en mode test."""
        locataire = self.get_object()
        if not locataire.mode_test:
            return Response({'error': 'Ce locataire n\'est pas en mode test. Activez mode_test d\'abord.'}, status=400)
        
        locataire.statut = 'En retard'
        locataire.test_debut = timezone.now()
        locataire.save()
        
        # Étape 1 : SMS à 15 secondes
        def envoyer_sms():
            loc = Locataire.objects.get(pk=locataire.pk)
            if loc.statut == 'Payé':  # Stop si payé
                return
            rappel = Rappel.objects.create(locataire=loc, type_rappel='SMS', statut='En attente')
            from .services import execute_rappel
            execute_rappel(rappel, contexte='J-5')
        
        # Étape 2 : Appel IA à 25 secondes
        def envoyer_appel():
            loc = Locataire.objects.get(pk=locataire.pk)
            if loc.statut == 'Payé':  # Stop si payé
                return
            rappel = Rappel.objects.create(locataire=loc, type_rappel='Appel', statut='En attente')
            execute_rappel(rappel, contexte='J-1')
        
        # Étape 3 : Pénalité à 30 secondes
        def appliquer_penalite():
            from penalites.models import Penalite
            loc = Locataire.objects.get(pk=locataire.pk)
            if loc.statut == 'Payé':  # Stop si payé
                return
            montant = loc.get_penalite_journaliere
            Penalite.objects.get_or_create(
                locataire=loc, statut='Active',
                defaults={'date_debut': timezone.now().date(), 'montant_journalier': montant}
            )
            loc.statut = 'En pénalité'
            loc.total_penalites += montant
            loc.save()
            Notification.objects.create(
                locataire=loc, bailleur=loc.bailleur,
                titre='[TEST] Pénalité appliquée',
                corps=f'{loc.prenom} {loc.nom} est entré en pénalité après le cycle de test.',
                type_notif='penalite'
            )
        
        threading.Timer(15.0, envoyer_sms).start()
        threading.Timer(25.0, envoyer_appel).start()
        threading.Timer(30.0, appliquer_penalite).start()
        
        return Response({
            'status': 'Cycle de test démarré !',
            'locataire': f'{locataire.prenom} {locataire.nom}',
            'etapes': {
                '15s': 'SMS de rappel envoyé',
                '25s': 'Appel IA passé',
                '30s': 'Pénalité appliquée si toujours impayé'
            }
        })

    @action(detail=True, methods=['patch'])
    def statut(self, request, pk=None):
        locataire = self.get_object()
        serializer = LocataireStatutSerializer(locataire, data=request.data, partial=True)
        if serializer.is_valid():
            serializer.save()
            return Response(serializer.data)
        return Response(serializer.errors, status=status.HTTP_400_BAD_REQUEST)

    @action(detail=True, methods=['post'])
    def rappeler(self, request, pk=None):
        locataire = self.get_object()
        type_rappel = request.data.get('type_rappel', 'SMS')
        if type_rappel not in dict(Rappel.TYPE_CHOICES).keys():
            return Response({'error': 'Type de rappel invalide'}, status=status.HTTP_400_BAD_REQUEST)
        
        rappel = Rappel.objects.create(
            locataire=locataire,
            type_rappel=type_rappel,
            statut='En attente'
        )
        execute_rappel(rappel)
        serializer = RappelSerializer(rappel)
        return Response(serializer.data, status=status.HTTP_201_CREATED)

    @action(detail=True, methods=['get'])
    def rappels(self, request, pk=None):
        locataire = self.get_object()
        rappels = locataire.rappels.all().order_by('-date_envoi')
        serializer = RappelSerializer(rappels, many=True)
        return Response(serializer.data)

    @action(detail=False, methods=['post'])
    def trigger_automations(self, request):
        verifier_echeances()
        return Response({'status': 'Automations executed'})

    # ----- Augmentation de loyer (3.3) -----
    @action(detail=True, methods=['post'])
    def augmenter_loyer(self, request, pk=None):
        locataire = self.get_object()
        montant = request.data.get('montant')
        date_debut = request.data.get('date_debut')
        motif = request.data.get('motif', '')
        if not montant or not date_debut:
            return Response({'error': 'montant et date_debut requis'}, status=400)
        hist = gestion.programmer_augmentation(locataire, montant, date_debut, motif)
        return Response(HistoriqueLoyerSerializer(hist).data, status=201)

    @action(detail=True, methods=['get'])
    def historique_loyers(self, request, pk=None):
        locataire = self.get_object()
        data = HistoriqueLoyerSerializer(locataire.historique_loyers.all(), many=True).data
        return Response(data)

    # ----- Caution (3.2) -----
    @action(detail=True, methods=['post'])
    def verser_caution(self, request, pk=None):
        locataire = self.get_object()
        montant = request.data.get('montant')
        date = request.data.get('date')
        if not montant or not date:
            return Response({'error': 'montant et date requis'}, status=400)
        gestion.verser_caution(locataire, montant, date, request.data.get('motif', ''))
        return Response(LocataireSerializer(locataire).data)

    @action(detail=True, methods=['post'])
    def restituer_caution(self, request, pk=None):
        locataire = self.get_object()
        montant = request.data.get('montant', 0)
        date = request.data.get('date')
        if not date:
            return Response({'error': 'date requise'}, status=400)
        gestion.restituer_caution(
            locataire, montant, date,
            motif=request.data.get('motif', ''),
            deductions=request.data.get('deductions', []),
        )
        return Response(LocataireSerializer(locataire).data)

    @action(detail=True, methods=['get'])
    def mouvements_caution(self, request, pk=None):
        locataire = self.get_object()
        data = MouvementCautionSerializer(locataire.mouvements_caution.all(), many=True).data
        return Response(data)

    # ----- Résiliation / fin de bail (2.7) -----
    @action(detail=True, methods=['post'])
    def resilier(self, request, pk=None):
        locataire = self.get_object()
        date_sortie = request.data.get('date_sortie')
        if not date_sortie:
            return Response({'error': 'date_sortie requise'}, status=400)
        res = gestion.resilier_locataire(locataire, date_sortie, request.data.get('motif', ''))
        return Response({'status': 'Bail résilié', **res})

    # ----- Import CSV/Excel (2.4) -----
    @action(detail=False, methods=['get'])
    def modele_import(self, request):
        from .import_service import modele_csv
        response = HttpResponse(modele_csv(), content_type='text/csv')
        response['Content-Disposition'] = 'attachment; filename="modele_import_locataires.csv"'
        return response

    @action(detail=False, methods=['post'], parser_classes=[MultiPartParser, FormParser])
    def importer(self, request):
        exiger_pro(request.user, 'import_masse')
        from .import_service import importer_locataires
        fichier = request.FILES.get('fichier')
        if not fichier:
            return Response({'error': "Aucun fichier fourni (champ 'fichier')"}, status=400)
        dry_run = request.query_params.get('dry_run') in ('1', 'true', 'True')
        res = importer_locataires(request.user, fichier.read(), fichier.name, dry_run=dry_run)
        return Response(res, status=200)

    # ----- Contrat de bail PDF (2.2) -----
    @action(detail=True, methods=['get'])
    def contrat(self, request, pk=None):
        exiger_pro(request.user, 'documents_legaux')
        locataire = self.get_object()
        from documents.services import generer_contrat_pdf
        pdf = generer_contrat_pdf(locataire)
        response = HttpResponse(pdf, content_type='application/pdf')
        response['Content-Disposition'] = f'attachment; filename="contrat_{locataire.id}.pdf"'
        return response

class DashboardView(APIView):
    permission_classes = [IsAuthenticated, AbonnementActif]

    def get(self, request):
        user = request.user
        locataires = Locataire.objects.filter(bailleur=user, is_deleted=False, archive=False)

        from paiements.models import Paiement
        revenus = Paiement.objects.filter(locataire__bailleur=user).aggregate(total=Sum('montant'))['total'] or 0

        loyers_payes = locataires.filter(statut='Payé').count()
        en_penalite = locataires.filter(statut='En pénalité').count()
        en_discussion = locataires.filter(statut='En discussion').count()
        
        revenus_attendus = locataires.aggregate(total=Sum('montant_loyer'))['total'] or 0
        penalites_dues = locataires.aggregate(total=Sum('total_penalites'))['total'] or 0

        # Statistiques de parc immobilier (module multi-biens)
        from biens.models import Propriete, UniteLogement
        nombre_biens = Propriete.objects.filter(bailleur=user).count()
        unites = UniteLogement.objects.filter(propriete__bailleur=user)
        total_unites = unites.count()
        unites_occupees = unites.filter(locataires__is_deleted=False).distinct().count()
        taux_occupation = round(unites_occupees / total_unites * 100, 1) if total_unites else 0

        data = {
            "total_locataires": locataires.count(),
            "loyers_payes": loyers_payes,
            "en_penalite": en_penalite,
            "en_discussion": en_discussion,
            "revenus_encaisses": revenus,
            "revenus_attendus": revenus_attendus,
            "penalites_dues": penalites_dues,
            "nombre_biens": nombre_biens,
            "total_unites": total_unites,
            "unites_occupees": unites_occupees,
            "unites_vacantes": total_unites - unites_occupees,
            "taux_occupation": taux_occupation,
            "alertes": [f"{l.prenom} {l.nom} est en retard" for l in locataires.filter(statut='En pénalité')]
        }
        return Response(data)

class NotificationViewSet(viewsets.ModelViewSet):
    serializer_class = NotificationSerializer
    permission_classes = [IsAuthenticated, AbonnementActif]

    def get_queryset(self):
        if getattr(self, 'swagger_fake_view', False):
            return Notification.objects.none()
        return Notification.objects.filter(bailleur=self.request.user)

    @action(detail=True, methods=['post'])
    def marquer_lue(self, request, pk=None):
        notification = self.get_object()
        notification.lue = True
        notification.save()
        return Response({'status': 'Notification marquée comme lue'})
    
    @action(detail=False, methods=['post'])
    def marquer_tout_lu(self, request):
        self.get_queryset().filter(lue=False).update(lue=True)
        return Response({'status': 'Toutes les notifications ont été marquées comme lues'})


class EtatDesLieuxViewSet(viewsets.ModelViewSet):
    serializer_class = EtatDesLieuxSerializer
    permission_classes = [IsAuthenticated, requiere_pro('documents_legaux')]

    def get_queryset(self):
        if getattr(self, 'swagger_fake_view', False):
            return EtatDesLieux.objects.none()
        qs = EtatDesLieux.objects.filter(locataire__bailleur=self.request.user)
        locataire_id = self.request.query_params.get('locataire')
        if locataire_id:
            qs = qs.filter(locataire_id=locataire_id)
        return qs

    @action(detail=True, methods=['get'])
    def rapport(self, request, pk=None):
        """Télécharge le rapport d'état des lieux en PDF (3.1 / 2.2)."""
        etat = self.get_object()
        from documents.services import generer_etat_des_lieux_pdf
        pdf = generer_etat_des_lieux_pdf(etat)
        response = HttpResponse(pdf, content_type='application/pdf')
        response['Content-Disposition'] = f'attachment; filename="etat_des_lieux_{etat.id}.pdf"'
        return response


class PhotoEtatDesLieuxViewSet(viewsets.ModelViewSet):
    serializer_class = PhotoEtatDesLieuxSerializer
    permission_classes = [IsAuthenticated, requiere_pro('documents_legaux')]

    def get_queryset(self):
        if getattr(self, 'swagger_fake_view', False):
            return PhotoEtatDesLieux.objects.none()
        return PhotoEtatDesLieux.objects.filter(etat__locataire__bailleur=self.request.user)

from rest_framework import viewsets, status
from rest_framework.decorators import action
from rest_framework.response import Response
from rest_framework.permissions import IsAuthenticated, AllowAny
from rest_framework.parsers import MultiPartParser, FormParser
from rest_framework.views import APIView
from django.db.models import Sum, F, Q, Value, DecimalField
from django.db.models.functions import Coalesce
from django.http import HttpResponse
from django.utils import timezone
from datetime import date, timedelta
from decimal import Decimal
import threading
from .serializers import (
    LocataireSerializer, LocataireStatutSerializer, RappelSerializer, NotificationSerializer,
    HistoriqueLoyerSerializer, MouvementCautionSerializer, EtatDesLieuxSerializer,
    PhotoEtatDesLieuxSerializer, PieceIdentiteFichierSerializer,
)
from .models import (
    Locataire, Rappel, Notification,
    HistoriqueLoyer, MouvementCaution, EtatDesLieux, PhotoEtatDesLieux,
    PieceIdentiteFichier,
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

    # ----- Pièces d'identité multiples (recto/verso/PDF) -----
    @action(detail=True, methods=['post'], url_path='ajouter_piece',
            parser_classes=[MultiPartParser, FormParser])
    def ajouter_piece(self, request, pk=None):
        locataire = self.get_object()
        fichier = request.FILES.get('fichier')
        if not fichier:
            return Response({'error': "Aucun fichier fourni (champ 'fichier')"}, status=400)
        piece = PieceIdentiteFichier.objects.create(
            locataire=locataire, fichier=fichier,
            libelle=(request.data.get('libelle') or '')[:50],
        )
        return Response(
            PieceIdentiteFichierSerializer(piece, context={'request': request}).data,
            status=201,
        )

    @action(detail=True, methods=['delete'], url_path=r'pieces/(?P<piece_id>[^/.]+)')
    def supprimer_piece(self, request, pk=None, piece_id=None):
        locataire = self.get_object()
        PieceIdentiteFichier.objects.filter(locataire=locataire, id=piece_id).delete()
        return Response(status=204)

    # ----- Contrat de bail PDF (2.2) -----
    @action(detail=True, methods=['get'])
    def contrat(self, request, pk=None):
        exiger_pro(request.user, 'documents_legaux')
        locataire = self.get_object()
        from documents.services import generer_contrat_pdf, champs_manquants_contrat

        # Conformité loi n°2014/023 : on REFUSE de générer un document tant que
        # des mentions obligatoires manquent. On renvoie la liste + la cible
        # pour que l'app redirige vers le bon écran (locataire et/ou réglages).
        manquants = champs_manquants_contrat(locataire)
        if manquants:
            cibles = {m['cible'] for m in manquants}
            cible = 'les_deux' if len(cibles) > 1 else next(iter(cibles))
            return Response({
                'code': 'donnees_incompletes',
                'message': "Informations obligatoires manquantes pour générer le contrat de bail.",
                'champs': [m['libelle'] for m in manquants],
                'details': manquants,
                'cible': cible,
            }, status=422)

        pdf = generer_contrat_pdf(locataire)
        response = HttpResponse(pdf, content_type='application/pdf')
        response['Content-Disposition'] = f'attachment; filename="contrat_{locataire.id}.pdf"'
        return response

class DashboardView(APIView):
    permission_classes = [IsAuthenticated, AbonnementActif]

    def get(self, request):
        user = request.user
        from paiements.models import Paiement

        DEC = DecimalField(max_digits=12, decimal_places=2)
        zero = Value(Decimal('0'), output_field=DEC)

        # Bornes du mois courant (le cockpit raisonne « ce mois-ci »).
        today = timezone.localdate()
        debut_mois = today.replace(day=1)
        if debut_mois.month == 12:
            fin_mois = debut_mois.replace(year=debut_mois.year + 1, month=1) - timedelta(days=1)
        else:
            fin_mois = debut_mois.replace(month=debut_mois.month + 1) - timedelta(days=1)

        locataires = Locataire.objects.filter(bailleur=user, is_deleted=False, archive=False)

        # Facturables ce mois : la facturation a démarré (ou pas de date définie).
        facturables = locataires.filter(
            Q(date_debut_facturation__isnull=True) | Q(date_debut_facturation__lte=fin_mois)
        )

        # ── Cockpit d'encaissement (mois courant) ────────────────────────────
        # Attendu = Σ (loyer + charges) des locataires facturables.
        attendu_mois = facturables.aggregate(
            t=Coalesce(Sum(F('montant_loyer') + F('charges_mensuelles'), output_field=DEC), zero)
        )['t']

        # Encaissé ce mois = trésorerie réellement entrée ce mois civil (par
        # date_paiement). La COUVERTURE par locataire (soldé / reste), elle, est
        # calculée par période ci-dessous — une avance d'un mois antérieur y compte.
        paiements_mois = Paiement.objects.filter(
            locataire__bailleur=user, date_paiement__gte=debut_mois, date_paiement__lte=fin_mois
        )
        encaisse_mois = paiements_mois.aggregate(t=Coalesce(Sum('montant'), zero))['t']

        # Couverture PAR PÉRIODE : un paiement couvre le mois courant si sa période
        # de loyer le chevauche. Gère les avances versées un mois antérieur (sinon
        # comptées à tort comme impayées → risque de re-réclamation).
        couvrants = Paiement.objects.filter(
            locataire__bailleur=user, periode_debut__lte=fin_mois, periode_fin__gte=debut_mois
        )
        # Locataires dont le mois est SOLDÉ (paiement complet/avance : reste_du = 0).
        soldes_ids = set(
            couvrants.filter(reste_du__lte=0).values_list('locataire_id', flat=True)
        )
        # Acomptes (paiements partiels) imputés au mois courant, par locataire.
        acompte_par_loc = {
            row['locataire_id']: row['t']
            for row in couvrants.exclude(reste_du__lte=0)
                                .values('locataire_id').annotate(t=Sum('montant'))
        }

        # Répartition + liste actionnable (calcul en mémoire, sans requête par item).
        a_jour = en_retard = partiel = en_attente = 0
        reste_a_encaisser = Decimal('0')
        a_encaisser = []
        for l in facturables.only(
            'id', 'prenom', 'nom', 'logement', 'telephone', 'statut',
            'montant_loyer', 'charges_mensuelles', 'jour_echeance', 'langue_preferee'
        ):
            du = (l.montant_loyer or Decimal('0')) + (l.charges_mensuelles or Decimal('0'))
            if l.id in soldes_ids:
                a_jour += 1  # mois déjà soldé (paiement complet/avance le couvrant)
                continue
            acompte = acompte_par_loc.get(l.id, Decimal('0'))
            reste = du - acompte
            if reste <= 0:
                a_jour += 1
                continue
            reste_a_encaisser += reste
            echu = today.day > (l.jour_echeance or 1)
            if acompte > 0:
                partiel += 1
            elif echu:
                en_retard += 1
            else:
                en_attente += 1
            a_encaisser.append({
                'locataire_id': l.id,
                'nom': f"{l.prenom} {l.nom}".strip(),
                'logement': l.logement or '',
                'telephone': l.telephone or '',
                'montant_du': int(reste),
                'jours_retard': max(0, today.day - l.jour_echeance) if echu else 0,
                'partiel': acompte > 0,
            })
        # Les plus en retard d'abord (puis plus gros montant).
        a_encaisser.sort(key=lambda x: (-x['jours_retard'], -x['montant_du']))

        taux_recouvrement = round(float(encaisse_mois) / float(attendu_mois) * 100, 1) if attendu_mois else 0.0

        # ── Statistiques de parc immobilier (conservées) ─────────────────────
        from biens.models import Propriete, UniteLogement
        nombre_biens = Propriete.objects.filter(bailleur=user).count()
        unites = UniteLogement.objects.filter(propriete__bailleur=user)
        total_unites = unites.count()
        unites_occupees = unites.filter(locataires__is_deleted=False).distinct().count()
        taux_occupation = round(unites_occupees / total_unites * 100, 1) if total_unites else 0

        # Revenus « tout-temps » (rétro-compat : ancien champ du dashboard).
        revenus = Paiement.objects.filter(locataire__bailleur=user).aggregate(
            t=Coalesce(Sum('montant'), zero))['t']
        penalites_dues = locataires.aggregate(t=Coalesce(Sum('total_penalites'), zero))['t']

        data = {
            # ── Cockpit d'encaissement (nouveau) ──
            "attendu_mois": int(attendu_mois),
            "encaisse_mois": int(encaisse_mois),
            "reste_a_encaisser": int(reste_a_encaisser),
            "taux_recouvrement": taux_recouvrement,
            "repartition": {
                "a_jour": a_jour, "en_retard": en_retard,
                "partiel": partiel, "en_attente": en_attente,
            },
            "a_encaisser": a_encaisser,
            # ── Champs historiques (rétro-compat frontend) ──
            "total_locataires": locataires.count(),
            "loyers_payes": a_jour,
            "en_penalite": locataires.filter(statut='En pénalité').count(),
            "en_discussion": locataires.filter(statut='En discussion').count(),
            "revenus_encaisses": int(revenus),
            "revenus_attendus": int(attendu_mois),
            "penalites_dues": int(penalites_dues),
            "nombre_biens": nombre_biens,
            "total_unites": total_unites,
            "unites_occupees": unites_occupees,
            "unites_vacantes": total_unites - unites_occupees,
            "taux_occupation": taux_occupation,
            "alertes": [f"{x['nom']} — {x['montant_du']} FCFA" for x in a_encaisser[:5]],
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

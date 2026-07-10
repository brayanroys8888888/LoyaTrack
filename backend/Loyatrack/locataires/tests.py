from datetime import date, timedelta
from decimal import Decimal

from django.contrib.auth import get_user_model
from django.test import TestCase
from django.utils import timezone

from .models import Locataire, HistoriqueLoyer, MouvementCaution
from . import gestion
from .import_service import importer_locataires

User = get_user_model()


def _locataire(bailleur, **kw):
    defaults = dict(
        bailleur=bailleur, nom='Doe', prenom='John', telephone='690', montant_loyer=Decimal('50000'),
        jour_echeance=1, date_entree=date(2024, 1, 1),
    )
    defaults.update(kw)
    return Locataire.objects.create(**defaults)


class GestionTests(TestCase):
    def setUp(self):
        self.b = User.objects.create_user(email='b@test.com', password='x')
        self.loc = _locataire(self.b)

    def test_augmentation_immediate(self):
        gestion.programmer_augmentation(self.loc, 60000, timezone.now().date(), 'révision annuelle')
        self.loc.refresh_from_db()
        self.assertEqual(self.loc.montant_loyer, Decimal('60000'))
        self.assertTrue(HistoriqueLoyer.objects.filter(locataire=self.loc, applique=True).exists())

    def test_augmentation_programmee_future(self):
        futur = timezone.now().date() + timedelta(days=30)
        gestion.programmer_augmentation(self.loc, 70000, futur)
        self.loc.refresh_from_db()
        self.assertEqual(self.loc.montant_loyer, Decimal('50000'))  # pas encore appliquée
        # Simule la tâche au jour J
        gestion.appliquer_augmentations_dues(futur)
        self.loc.refresh_from_db()
        self.assertEqual(self.loc.montant_loyer, Decimal('70000'))

    def test_caution_versement_et_restitution(self):
        gestion.verser_caution(self.loc, 100000, date.today())
        self.loc.refresh_from_db()
        self.assertEqual(self.loc.statut_caution, 'versee')
        self.assertEqual(self.loc.montant_caution, Decimal('100000'))
        gestion.restituer_caution(self.loc, 80000, date.today(),
                                  deductions=[{'montant': 20000, 'motif': 'dégâts'}])
        self.loc.refresh_from_db()
        self.assertEqual(self.loc.statut_caution, 'restituee_partielle')
        self.assertEqual(MouvementCaution.objects.filter(locataire=self.loc).count(), 3)

    def test_resiliation_archive_et_libere_unite(self):
        res = gestion.resilier_locataire(self.loc, date.today(), 'départ')
        self.loc.refresh_from_db()
        self.assertTrue(self.loc.archive)
        self.assertIsNotNone(self.loc.date_sortie)
        self.assertIn('solde_du', res)


class ImportTests(TestCase):
    def setUp(self):
        self.b = User.objects.create_user(email='b@test.com', password='x')

    def test_import_csv(self):
        csv = (
            "nom,prenom,telephone,logement,montant_loyer,jour_echeance,date_entree\n"
            "Mbarga,Alice,690,Studio A1,50000,5,2024-01-01\n"
            "Fotso,Jean,691,B2,75000,1,01/02/2024\n"
        ).encode()
        res = importer_locataires(self.b, csv, 'test.csv')
        self.assertEqual(res['crees'], 2)
        self.assertEqual(len(res['erreurs']), 0)
        self.assertEqual(Locataire.objects.filter(bailleur=self.b).count(), 2)

    def test_import_erreurs(self):
        csv = ("nom,prenom,montant_loyer,jour_echeance\n"
               ",Alice,50000,5\n"          # nom manquant
               "X,Y,50000,99\n").encode()  # jour invalide
        res = importer_locataires(self.b, csv, 'test.csv')
        self.assertEqual(res['crees'], 0)
        self.assertEqual(len(res['erreurs']), 2)


class DocumentsTests(TestCase):
    def test_contrat_pdf(self):
        b = User.objects.create_user(email='b@test.com', password='x')
        loc = _locataire(b)
        from documents.services import generer_contrat_pdf
        pdf = generer_contrat_pdf(loc)
        self.assertTrue(pdf.startswith(b'%PDF'))


class RappelMessageTests(TestCase):
    """Templates de rappels bilingues (module Paramètres 6.1)."""

    def test_message_fr_avant_echeance(self):
        from .services import construire_message
        m = construire_message('SMS', 'avant', 'fr', salutation='Bonjour',
                               nom_complet='DOE John', nom_prononce='x', jours=3)
        self.assertIn('dans 3 jours', m)
        self.assertIn('pénalités', m)

    def test_message_en_avant_echeance(self):
        from .services import construire_message
        m = construire_message('SMS', 'avant', 'en', salutation='Good morning',
                               nom_complet='DOE John', nom_prononce='x', jours=3)
        self.assertIn('in 3 days', m)
        self.assertIn('penalties', m)

    def test_message_en_demain(self):
        from .services import construire_message
        m = construire_message('Appel', 'avant', 'en', salutation='Good morning',
                               nom_complet='DOE John', nom_prononce='Mr DOE', jours=1)
        self.assertIn('tomorrow', m)
        self.assertIn('automated call', m)

    def test_retro_compat_J5(self):
        from .services import construire_message
        m = construire_message('SMS', 'J-5', 'fr', salutation='Bonjour',
                               nom_complet='DOE John', nom_prononce='x')
        self.assertIn('dans 5 jours', m)


class DashboardCockpitTests(TestCase):
    """Métriques du cockpit d'encaissement (attendu / encaissé / reste, ce mois)."""

    def setUp(self):
        self.b = User.objects.create_user(email='b@test.com', password='x')

    def _dashboard(self):
        from rest_framework.test import APIRequestFactory, force_authenticate
        from .views import DashboardView
        req = APIRequestFactory().get('/api/v1/dashboard/')
        force_authenticate(req, user=self.b)
        return DashboardView.as_view()(req).data

    def test_attendu_encaisse_reste_et_repartition(self):
        from paiements.models import Paiement
        from paiements.services import appliquer_paiement
        # Deux locataires, dû = loyer 50000 + charges 10000 = 60000 chacun.
        l1 = _locataire(self.b, charges_mensuelles=Decimal('10000'), jour_echeance=5)
        l2 = _locataire(self.b, nom='Fotso', prenom='Jean',
                        charges_mensuelles=Decimal('10000'), jour_echeance=5)
        # l1 solde son mois ; l2 ne paie rien.
        appliquer_paiement(Paiement.objects.create(
            locataire=l1, montant=Decimal('60000'),
            date_paiement=timezone.localdate(), mode_paiement='Mobile Money'))

        data = self._dashboard()
        self.assertEqual(data['attendu_mois'], 120000)
        self.assertEqual(data['encaisse_mois'], 60000)
        self.assertEqual(data['reste_a_encaisser'], 60000)
        self.assertEqual(data['taux_recouvrement'], 50.0)
        self.assertEqual(data['repartition']['a_jour'], 1)
        ids = [x['locataire_id'] for x in data['a_encaisser']]
        self.assertIn(l2.id, ids)       # impayé listé
        self.assertNotIn(l1.id, ids)    # soldé exclu

    def test_paiement_partiel_compte_le_reste(self):
        from paiements.models import Paiement
        from paiements.services import appliquer_paiement
        l = _locataire(self.b, charges_mensuelles=Decimal('0'), jour_echeance=5)  # dû 50000
        appliquer_paiement(Paiement.objects.create(
            locataire=l, montant=Decimal('20000'),
            date_paiement=timezone.localdate(), mode_paiement='Espèces'))

        data = self._dashboard()
        self.assertEqual(data['reste_a_encaisser'], 30000)
        self.assertEqual(data['repartition']['partiel'], 1)
        self.assertEqual(data['a_encaisser'][0]['montant_du'], 30000)
        self.assertTrue(data['a_encaisser'][0]['partiel'])

    def test_avance_mois_anterieur_couvre_le_mois_courant(self):
        """Une avance versée le mois dernier couvrant ce mois -> locataire à jour."""
        from paiements.models import Paiement
        from paiements.services import appliquer_paiement
        l = _locataire(self.b, charges_mensuelles=Decimal('10000'), jour_echeance=5)  # dû 60000
        # Avance de 2 mois (120000) versée le 1er du mois dernier -> couvre ce mois.
        mois_dernier = (timezone.localdate().replace(day=1) - timedelta(days=1)).replace(day=1)
        p = appliquer_paiement(Paiement.objects.create(
            locataire=l, montant=Decimal('120000'),
            date_paiement=mois_dernier, mode_paiement='Mobile Money'))
        self.assertEqual(p.statut, 'avance')  # période s'étend jusqu'à ce mois

        data = self._dashboard()
        # Aucune trésorerie encaissée CE mois-ci, mais le mois est couvert.
        self.assertEqual(data['encaisse_mois'], 0)
        self.assertEqual(data['reste_a_encaisser'], 0)
        self.assertEqual(data['repartition']['a_jour'], 1)
        self.assertNotIn(l.id, [x['locataire_id'] for x in data['a_encaisser']])

    def test_locataire_non_encore_facturable_exclu(self):
        # Facturation démarrant le mois prochain → hors attendu de ce mois.
        futur = (timezone.localdate().replace(day=1) + timedelta(days=40)).replace(day=1)
        _locataire(self.b, date_debut_facturation=futur)
        data = self._dashboard()
        self.assertEqual(data['attendu_mois'], 0)
        self.assertEqual(data['a_encaisser'], [])


class VerifierEcheancesConfigTests(TestCase):
    """verifier_echeances respecte la ConfigBailleur (master, jours, canal)."""

    def setUp(self):
        self.b = User.objects.create_user(email='b@test.com', password='x')
        self.aujourd_hui = timezone.now().date()

    def _loc_echeant_dans(self, jours, **kw):
        # jour_echeance tel que l'échéance de ce mois tombe dans `jours` jours
        cible = self.aujourd_hui + timedelta(days=jours)
        return _locataire(self.b, jour_echeance=cible.day, statut='En retard', **kw)

    def test_master_off_ne_cree_aucun_rappel(self):
        from accounts.models import ConfigBailleur
        from .models import Rappel
        from .tasks import verifier_echeances
        ConfigBailleur.objects.create(user=self.b, rappels_automatiques_actifs=False)
        self._loc_echeant_dans(3)
        verifier_echeances()
        self.assertEqual(Rappel.objects.count(), 0)

    def test_canal_et_jours_respectes(self):
        from accounts.models import ConfigBailleur
        from .models import Rappel
        from .tasks import verifier_echeances
        ConfigBailleur.objects.create(user=self.b, jours_avant_rappel=3, canal_rappel_prefere='whatsapp')
        loc = self._loc_echeant_dans(3)
        verifier_echeances()
        r = Rappel.objects.filter(locataire=loc).first()
        self.assertIsNotNone(r)
        self.assertEqual(r.type_rappel, 'WhatsApp')

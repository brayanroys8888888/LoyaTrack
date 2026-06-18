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

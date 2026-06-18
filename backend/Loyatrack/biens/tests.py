from datetime import date
from decimal import Decimal

from django.contrib.auth import get_user_model
from django.test import TestCase

from locataires.models import Locataire
from .models import Propriete, UniteLogement

User = get_user_model()


class BiensTests(TestCase):
    def setUp(self):
        self.bailleur = User.objects.create_user(email='b@test.com', password='x')
        self.prop = Propriete.objects.create(bailleur=self.bailleur, titre='Résidence A', type='immeuble')
        self.u1 = UniteLogement.objects.create(propriete=self.prop, numero='A1', loyer_standard=Decimal('50000'))
        self.u2 = UniteLogement.objects.create(propriete=self.prop, numero='A2', loyer_standard=Decimal('60000'))

    def test_unite_vacante_par_defaut(self):
        self.assertFalse(self.u1.est_occupee)

    def test_unite_occupee_avec_locataire(self):
        Locataire.objects.create(
            bailleur=self.bailleur, nom='X', prenom='Y', telephone='690', montant_loyer=Decimal('50000'),
            jour_echeance=1, date_entree=date(2024, 1, 1), unite=self.u1,
        )
        self.assertTrue(self.u1.est_occupee)
        self.u1.synchroniser_statut()
        self.u1.refresh_from_db()
        self.assertEqual(self.u1.statut, 'occupe')

    def test_locataire_supprime_libere_unite(self):
        loc = Locataire.objects.create(
            bailleur=self.bailleur, nom='X', prenom='Y', telephone='690', montant_loyer=Decimal('50000'),
            jour_echeance=1, date_entree=date(2024, 1, 1), unite=self.u1, is_deleted=True,
        )
        self.assertFalse(self.u1.est_occupee)

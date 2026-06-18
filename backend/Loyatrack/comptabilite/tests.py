from datetime import date
from decimal import Decimal

from django.contrib.auth import get_user_model
from django.test import TestCase

from locataires.models import Locataire
from paiements.models import Paiement
from .models import Depense
from . import services

User = get_user_model()


class ComptabiliteTests(TestCase):
    def setUp(self):
        self.b = User.objects.create_user(email='b@test.com', password='x')
        self.loc = Locataire.objects.create(
            bailleur=self.b, nom='Doe', prenom='J', telephone='690',
            montant_loyer=Decimal('50000'), jour_echeance=1, date_entree=date(2024, 1, 1),
        )
        Paiement.objects.create(locataire=self.loc, montant=Decimal('50000'),
                                date_paiement=date(2026, 3, 1), mode_paiement='Espèces')
        Depense.objects.create(bailleur=self.b, libelle='Plomberie', montant=Decimal('10000'),
                               date=date(2026, 4, 1), categorie='entretien')

    def test_releve_annuel(self):
        r = services.releve_annuel(self.b, 2026)
        self.assertEqual(r['loyers_percus'], Decimal('50000'))
        self.assertEqual(r['depenses_total'], Decimal('10000'))
        self.assertEqual(r['revenu_net'], Decimal('40000'))

    def test_export_excel_et_pdf(self):
        r = services.releve_annuel(self.b, 2026)
        self.assertTrue(services.export_excel(r)[:2] == b'PK')  # xlsx = zip
        self.assertTrue(services.export_pdf(r).startswith(b'%PDF'))

from datetime import date
from decimal import Decimal

from django.contrib.auth import get_user_model
from django.test import TestCase

from locataires.models import Locataire
from penalites.models import Penalite
from .models import Paiement
from .services import appliquer_paiement, generer_quittance_pdf

User = get_user_model()


class PaiementServiceTests(TestCase):
    def setUp(self):
        self.bailleur = User.objects.create_user(email='b@test.com', password='x')
        self.loc = Locataire.objects.create(
            bailleur=self.bailleur, nom='Doe', prenom='Jane', telephone='690000000',
            montant_loyer=Decimal('50000'), jour_echeance=1, statut='En retard',
            date_entree=date(2024, 1, 1),
        )

    def _paiement(self, montant):
        p = Paiement.objects.create(
            locataire=self.loc, montant=Decimal(str(montant)),
            date_paiement=date(2026, 6, 5), mode_paiement='Espèces',
        )
        return appliquer_paiement(p)

    def test_paiement_partiel(self):
        p = self._paiement(20000)
        self.assertEqual(p.statut, 'partiel')
        self.assertEqual(p.reste_du, Decimal('30000.00'))
        self.loc.refresh_from_db()
        self.assertNotEqual(self.loc.statut, 'Payé')  # non soldé

    def test_paiement_complet_solde_et_cloture_penalites(self):
        Penalite.objects.create(locataire=self.loc, periode=date(2026, 6, 1),
                                date_debut=date(2026, 6, 2), montant_journalier=Decimal('1000'),
                                total=Decimal('3000'), statut='Active')
        p = self._paiement(50000)
        self.assertEqual(p.statut, 'complet')
        self.loc.refresh_from_db()
        self.assertEqual(self.loc.statut, 'Payé')
        self.assertEqual(self.loc.total_penalites, Decimal('0'))
        self.assertEqual(self.loc.penalites.filter(statut='Active').count(), 0)

    def test_paiement_avance(self):
        p = self._paiement(150000)  # 3 mois
        self.assertEqual(p.statut, 'avance')
        self.assertEqual(p.nb_mois, 3)
        self.assertEqual(p.periode_fin.month, 8)  # juin -> août

    def test_quittance_pdf(self):
        p = self._paiement(50000)
        pdf = generer_quittance_pdf(p)
        self.assertTrue(pdf.startswith(b'%PDF'))

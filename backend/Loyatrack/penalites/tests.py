from datetime import date
from decimal import Decimal

from django.contrib.auth import get_user_model
from django.test import TestCase

from locataires.models import Locataire
from .models import Penalite, ConfigPenalite
from .services import appliquer_penalite_locataire, remettre_penalite

User = get_user_model()


class PenaliteServiceTests(TestCase):
    def setUp(self):
        self.bailleur = User.objects.create_user(
            email='b@test.com', password='x', penalite_defaut=Decimal('1000')
        )
        # Échéance le 1er du mois
        self.loc = Locataire.objects.create(
            bailleur=self.bailleur, nom='Doe', prenom='John', telephone='690000000',
            montant_loyer=Decimal('50000'), jour_echeance=1, statut='En retard',
            date_entree=date(2024, 1, 1),
        )

    def test_penalite_par_date_absolue(self):
        appliquer_penalite_locataire(self.loc, date(2026, 6, 11))  # 10 jours après le 1er
        p = Penalite.objects.get(locataire=self.loc)
        self.assertEqual(p.total, Decimal('10000.00'))  # 10 j * 1000 (défaut bailleur)
        self.loc.refresh_from_db()
        self.assertEqual(self.loc.statut, 'En pénalité')

    def test_idempotence_meme_jour(self):
        appliquer_penalite_locataire(self.loc, date(2026, 6, 11))
        appliquer_penalite_locataire(self.loc, date(2026, 6, 11))  # relance
        self.assertEqual(Penalite.objects.filter(locataire=self.loc).count(), 1)
        self.assertEqual(Penalite.objects.get(locataire=self.loc).total, Decimal('10000.00'))

    def test_delai_grace(self):
        ConfigPenalite.objects.create(locataire=self.loc, delai_grace=5,
                                      type_penalite='fixe', montant_fixe=Decimal('2000'))
        self.assertIsNone(appliquer_penalite_locataire(self.loc, date(2026, 6, 4)))  # dans la grâce
        appliquer_penalite_locataire(self.loc, date(2026, 6, 9))  # 8 - 5 = 3 jours
        self.assertEqual(Penalite.objects.get(locataire=self.loc).total, Decimal('6000.00'))

    def test_penalite_pourcentage(self):
        ConfigPenalite.objects.create(locataire=self.loc, type_penalite='pourcentage',
                                      pourcentage=Decimal('1'))  # 1% de 50000 = 500/j
        appliquer_penalite_locataire(self.loc, date(2026, 6, 6))  # 5 jours
        self.assertEqual(Penalite.objects.get(locataire=self.loc).total, Decimal('2500.00'))

    def test_remise_totale(self):
        appliquer_penalite_locataire(self.loc, date(2026, 6, 11))
        p = Penalite.objects.get(locataire=self.loc)
        remettre_penalite(p, motif='Geste commercial')
        p.refresh_from_db()
        self.assertEqual(p.montant_net, Decimal('0'))
        self.assertEqual(p.statut, 'Remise')
        self.loc.refresh_from_db()
        self.assertEqual(self.loc.total_penalites, Decimal('0'))

    def test_remise_motif_obligatoire(self):
        appliquer_penalite_locataire(self.loc, date(2026, 6, 11))
        p = Penalite.objects.get(locataire=self.loc)
        with self.assertRaises(ValueError):
            remettre_penalite(p, motif='')

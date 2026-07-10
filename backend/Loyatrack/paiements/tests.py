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

    def test_paiement_en_deux_fois_solde_le_mois(self):
        """Acompte puis complément le même mois -> 2e paiement 'complet', locataire soldé."""
        self.loc.charges_mensuelles = Decimal('10000')  # dû = 50000 + 10000 = 60000
        self.loc.save(update_fields=['charges_mensuelles'])
        p1 = self._paiement(20000)
        self.assertEqual(p1.statut, 'partiel')
        self.assertEqual(p1.reste_du, Decimal('40000.00'))
        self.loc.refresh_from_db()
        self.assertNotEqual(self.loc.statut, 'Payé')  # mois pas encore couvert

        p2 = self._paiement(40000)  # 20000 + 40000 = 60000 -> mois soldé
        self.assertEqual(p2.statut, 'complet')
        self.assertEqual(p2.reste_du, Decimal('0'))
        self.loc.refresh_from_db()
        self.assertEqual(self.loc.statut, 'Payé')


class EncaissementLoyerTests(TestCase):
    """Encaissement Mobile Money : demande → webhook → Paiement (provider fake)."""

    def setUp(self):
        self.bailleur = User.objects.create_user(email='b@test.com', password='x')
        self.loc = Locataire.objects.create(
            bailleur=self.bailleur, nom='Doe', prenom='Jane', telephone='690',
            montant_loyer=Decimal('50000'), charges_mensuelles=Decimal('10000'),
            jour_echeance=5, statut='En retard', date_entree=date(2024, 1, 1),
        )

    def _webhook(self, reference):
        from rest_framework.test import APIRequestFactory
        from .views import WebhookLoyerView
        req = APIRequestFactory().post(
            '/api/v1/webhooks/paiement-loyer/', {'reference': reference}, format='json')
        return WebhookLoyerView.as_view()(req)

    def test_creer_demande_calcule_montant_frais_repercutes(self):
        from .services import creer_demande_paiement
        d = creer_demande_paiement(self.loc)
        # Base = loyer 50000 + charges 10000 = 60000 ; frais 2% = 1200.
        self.assertEqual(d.montant_loyer, Decimal('60000'))
        self.assertEqual(d.frais, Decimal('1200'))
        self.assertEqual(d.montant, Decimal('61200'))
        self.assertEqual(d.statut, 'en_attente')
        self.assertTrue(d.url_paiement)  # URL fake renseignée

    def test_demande_deduit_paiement_deja_fait(self):
        """La demande ne facture que le solde restant (déduit un acompte du mois)."""
        from .models import Paiement
        from .services import creer_demande_paiement, appliquer_paiement
        appliquer_paiement(Paiement.objects.create(
            locataire=self.loc, montant=Decimal('20000'),
            date_paiement=date.today(), mode_paiement='Espèces'))
        d = creer_demande_paiement(self.loc)
        # Reste = 60000 - 20000 = 40000 ; frais 2% = 800 ; total = 40800.
        self.assertEqual(d.montant_loyer, Decimal('40000'))
        self.assertEqual(d.frais, Decimal('800'))
        self.assertEqual(d.montant, Decimal('40800'))

    def test_encaissement_apres_acompte_ne_double_facture_pas(self):
        """Acompte espèces + encaissement MoMo = obligation exacte, sans surfacturation."""
        from django.db.models import Sum
        from .models import Paiement
        from .services import creer_demande_paiement, appliquer_paiement
        appliquer_paiement(Paiement.objects.create(
            locataire=self.loc, montant=Decimal('20000'),
            date_paiement=date.today(), mode_paiement='Espèces'))
        d = creer_demande_paiement(self.loc)
        self._webhook(str(d.reference_interne))
        self.loc.refresh_from_db()
        self.assertEqual(self.loc.statut, 'Payé')
        total = Paiement.objects.filter(locataire=self.loc).aggregate(t=Sum('montant'))['t']
        self.assertEqual(total, Decimal('60000'))  # 20000 + 40000, pas 20000 + 60000

    def test_demande_rien_a_encaisser_si_deja_solde(self):
        """Un locataire déjà à jour pour le mois ne peut pas être re-sollicité."""
        from .models import Paiement
        from .services import creer_demande_paiement, appliquer_paiement
        appliquer_paiement(Paiement.objects.create(
            locataire=self.loc, montant=Decimal('60000'),
            date_paiement=date.today(), mode_paiement='Espèces'))
        with self.assertRaises(ValueError):
            creer_demande_paiement(self.loc)

    def test_webhook_confirme_cree_paiement_et_solde_locataire(self):
        from .services import creer_demande_paiement
        d = creer_demande_paiement(self.loc)
        resp = self._webhook(str(d.reference_interne))
        self.assertEqual(resp.status_code, 200)
        d.refresh_from_db()
        self.assertEqual(d.statut, 'payee')
        self.assertIsNotNone(d.paiement)
        # Le Paiement enregistré = loyer (hors frais, qui rémunèrent le prestataire).
        self.assertEqual(d.paiement.montant, Decimal('60000'))
        self.assertEqual(d.paiement.mode_paiement, 'Mobile Money')
        self.loc.refresh_from_db()
        self.assertEqual(self.loc.statut, 'Payé')

    def test_webhook_idempotent_un_seul_paiement(self):
        from .services import creer_demande_paiement
        d = creer_demande_paiement(self.loc)
        self._webhook(str(d.reference_interne))
        self._webhook(str(d.reference_interne))  # rejeu du webhook
        self.assertEqual(Paiement.objects.filter(locataire=self.loc).count(), 1)

    def test_webhook_reference_inconnue_404(self):
        import uuid
        resp = self._webhook(str(uuid.uuid4()))
        self.assertEqual(resp.status_code, 404)

    def test_webhook_reference_malformee_404_pas_500(self):
        """Une référence non-UUID (bot/scanner) renvoie 404, jamais une 500."""
        resp = self._webhook('pas-un-uuid')
        self.assertEqual(resp.status_code, 404)

    def test_reversement_immediat_vers_bailleur(self):
        """Bailleur avec numéro de reversement configuré → transfert immédiat."""
        from .models import CompteMarchand
        from .services import creer_demande_paiement
        CompteMarchand.objects.create(
            bailleur=self.bailleur, numero_momo='690123456', operateur='mtn', actif=True)
        d = creer_demande_paiement(self.loc)
        self._webhook(str(d.reference_interne))
        d.refresh_from_db()
        self.assertEqual(d.reversement_statut, 'effectue')  # provider fake → succès
        self.assertTrue(d.reversement_ref)

    def test_pas_de_reversement_sans_compte(self):
        """Sans compte de reversement configuré, la demande reste 'non_requis'."""
        from .services import creer_demande_paiement
        d = creer_demande_paiement(self.loc)
        self._webhook(str(d.reference_interne))
        d.refresh_from_db()
        self.assertEqual(d.reversement_statut, 'non_requis')

    def test_relance_reversement_bloque(self):
        """Un reversement bloqué en 'echoue' est rejoué et repasse 'effectue'."""
        from .models import CompteMarchand, DemandePaiement
        from .services import creer_demande_paiement
        from .tasks import relancer_reversements
        CompteMarchand.objects.create(
            bailleur=self.bailleur, numero_momo='690123456', operateur='mtn', actif=True)
        d = creer_demande_paiement(self.loc)
        self._webhook(str(d.reference_interne))
        # Simule un transfert antérieur resté bloqué (échec réseau / worker tué).
        DemandePaiement.objects.filter(pk=d.pk).update(reversement_statut='echoue')
        relancer_reversements()
        d.refresh_from_db()
        self.assertEqual(d.reversement_statut, 'effectue')  # provider fake → succès

    def test_relance_ne_retransfere_pas_si_deja_effectue(self):
        """Idempotence : relancer une demande déjà reversée ne change rien."""
        from .models import CompteMarchand
        from .services import creer_demande_paiement
        from .tasks import relancer_reversements
        CompteMarchand.objects.create(
            bailleur=self.bailleur, numero_momo='690123456', operateur='mtn', actif=True)
        d = creer_demande_paiement(self.loc)
        self._webhook(str(d.reference_interne))
        d.refresh_from_db()
        self.assertEqual(d.reversement_statut, 'effectue')
        ref_initiale = d.reversement_ref
        relancer_reversements()  # 'effectue' n'est pas ciblé → aucun re-transfert
        d.refresh_from_db()
        self.assertEqual(d.reversement_ref, ref_initiale)

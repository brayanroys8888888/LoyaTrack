import tempfile
from datetime import timedelta
from decimal import Decimal

from django.contrib.auth import get_user_model
from django.core.exceptions import ValidationError
from django.core.files.uploadedfile import SimpleUploadedFile
from django.test import TestCase, override_settings
from django.utils import timezone

from biens.models import Propriete, UniteLogement
from locataires.models import Locataire

from . import services
from .models import Ville, Quartier, Annonce, PhotoAnnonce
from .tasks import expirer_annonces

User = get_user_model()

# JPEG minimal valide (SOI + EOI) pour ImageField.
_JPEG = b'\xff\xd8\xff\xd9'


@override_settings(MEDIA_ROOT=tempfile.mkdtemp())
class AnnonceServiceTests(TestCase):
    def setUp(self):
        self.bailleur = User.objects.create_user(email='b@test.cm', password='x')
        self.ville = Ville.objects.create(nom='Douala', slug='douala')
        self.quartier = Quartier.objects.create(
            ville=self.ville, nom='Bonamoussadi', slug='bonamoussadi')
        self.propriete = Propriete.objects.create(bailleur=self.bailleur, titre='Imm A')
        self.unite = UniteLogement.objects.create(
            propriete=self.propriete, numero='A1', loyer_standard=Decimal('120000'))

    def _annonce(self, **kw):
        defaults = dict(
            bailleur=self.bailleur, ville=self.ville, quartier=self.quartier,
            titre='Bel appart', type_bien='appartement', nb_chambres=2,
            loyer=Decimal('120000'), description='Joli logement lumineux.')
        defaults.update(kw)
        return Annonce.objects.create(**defaults)

    def _photo(self, annonce):
        return PhotoAnnonce.objects.create(
            annonce=annonce,
            image=SimpleUploadedFile('p.jpg', _JPEG, content_type='image/jpeg'))

    # ── Génération référence / slug ──────────────────────────────────────────
    def test_reference_et_slug_generes_et_uniques(self):
        a1 = self._annonce()
        a2 = self._annonce()
        self.assertTrue(a1.reference.startswith('LT-'))
        ref = a1.reference.lower().replace('-', '')
        self.assertEqual(a1.slug, f'appartement-2-chambres-bonamoussadi-douala-{ref}')
        self.assertNotEqual(a1.reference, a2.reference)
        self.assertNotEqual(a1.slug, a2.slug)

    def test_slug_sans_quartier(self):
        a = self._annonce(quartier=None)
        self.assertIn('appartement-2-chambres-douala', a.slug)

    # ── Nettoyage des numéros ────────────────────────────────────────────────
    def test_nettoyer_telephones(self):
        self.assertEqual(
            services.nettoyer_telephones('Appelez 690112233 svp'),
            'Appelez [numéro masqué] svp')
        self.assertEqual(
            services.nettoyer_telephones('tel +237 699 00 11 22'),
            'tel [numéro masqué]')
        # Un nombre court (superficie, pièces) n'est pas masqué.
        self.assertEqual(
            services.nettoyer_telephones('120 m2, 3 pièces'),
            '120 m2, 3 pièces')

    # ── Publication ──────────────────────────────────────────────────────────
    def test_publier_refuse_sans_photo_ni_loyer(self):
        a = self._annonce(loyer=Decimal('0'))
        with self.assertRaises(ValidationError):
            services.publier(a)
        a.refresh_from_db()
        self.assertEqual(a.statut, 'brouillon')
        self.assertFalse(a.est_visible)

    def test_publier_ok_et_masque_numero(self):
        a = self._annonce(description='Contact 690112233 pour visite')
        self._photo(a)
        services.publier(a)
        a.refresh_from_db()
        self.assertEqual(a.statut, 'publiee')
        self.assertTrue(a.est_visible)
        self.assertNotIn('690112233', a.description)
        self.assertAlmostEqual(
            (a.date_expiration - timezone.now()).days,
            services.DUREE_ANNONCE_JOURS, delta=1)

    # ── Synchro occupation ───────────────────────────────────────────────────
    def test_synchro_occupation_depublie_annonce(self):
        a = self._annonce(unite=self.unite)
        self._photo(a)
        services.publier(a)
        self.assertTrue(a.est_visible)
        # Un locataire rattaché à l'unité → unité occupée.
        Locataire.objects.create(
            bailleur=self.bailleur, nom='Doe', prenom='Jane', telephone='650000000',
            unite=self.unite, montant_loyer=Decimal('120000'), jour_echeance=5,
            date_entree=timezone.now().date())
        self.unite.synchroniser_statut()
        a.refresh_from_db()
        self.assertEqual(a.statut, 'pourvue')
        self.assertFalse(a.est_visible)

    # ── Renouvellement / expiration ──────────────────────────────────────────
    def test_expirer_annonces_task(self):
        a = self._annonce()
        self._photo(a)
        services.publier(a)
        Annonce.objects.filter(pk=a.pk).update(
            date_expiration=timezone.now() - timedelta(days=1))
        n = expirer_annonces()
        a.refresh_from_db()
        self.assertGreaterEqual(n, 1)
        self.assertEqual(a.statut, 'expiree')

    def test_renouveler_republie_une_annonce_expiree(self):
        a = self._annonce()
        self._photo(a)
        services.publier(a)
        Annonce.objects.filter(pk=a.pk).update(
            statut='expiree', date_expiration=timezone.now() - timedelta(days=1))
        a.refresh_from_db()
        services.renouveler(a)
        a.refresh_from_db()
        self.assertEqual(a.statut, 'publiee')
        self.assertTrue(a.est_visible)

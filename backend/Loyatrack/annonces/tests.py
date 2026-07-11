import tempfile
from datetime import timedelta
from decimal import Decimal

from django.contrib.auth import get_user_model
from django.core.exceptions import ValidationError
from django.core.files.uploadedfile import SimpleUploadedFile
from django.test import TestCase, override_settings
from django.utils import timezone

from rest_framework.test import APIClient

from biens.models import Propriete, UniteLogement
from locataires.models import Locataire

from . import services
from . import messagerie
from .messagerie import (
    envoyer_otp_chercheur, verifier_otp_chercheur, demarrer_conversation, repondre,
    MessagerieError,
)
from .models import (
    Ville, Quartier, Annonce, PhotoAnnonce, Chercheur, Conversation, Message,
    Signalement,
)
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


@override_settings(MEDIA_ROOT=tempfile.mkdtemp())
class AnnonceAPITests(TestCase):
    def setUp(self):
        self.bailleur = User.objects.create_user(email='b@test.cm', password='x')
        self.autre = User.objects.create_user(email='autre@test.cm', password='x')
        self.ville = Ville.objects.create(nom='Douala', slug='douala')
        self.quartier = Quartier.objects.create(
            ville=self.ville, nom='Bonamoussadi', slug='bonamoussadi')
        self.propriete = Propriete.objects.create(bailleur=self.bailleur, titre='Imm A')
        self.unite = UniteLogement.objects.create(
            propriete=self.propriete, numero='A1', loyer_standard=Decimal('120000'))
        self.client = APIClient()
        self.client.force_authenticate(self.bailleur)

    def _payload(self, **kw):
        data = dict(titre='Studio centre', type_bien='studio', nb_chambres=1,
                    loyer='80000', ville=self.ville.id, quartier=self.quartier.id,
                    description='Studio propre et lumineux.')
        data.update(kw)
        return data

    def test_depuis_unite_cree_brouillon_prerempli(self):
        r = self.client.post('/api/v1/annonces/depuis-unite/',
                             {'unite': self.unite.id}, format='json')
        self.assertEqual(r.status_code, 201)
        self.assertEqual(r.data['statut'], 'brouillon')
        self.assertEqual(Decimal(r.data['loyer']), Decimal('120000'))
        self.assertEqual(r.data['unite'], self.unite.id)
        self.assertEqual(r.data['type_bien'], 'appartement')  # immeuble → appartement

    def test_create_et_scoping_liste(self):
        r = self.client.post('/api/v1/annonces/', self._payload(), format='json')
        self.assertEqual(r.status_code, 201)
        # Annonce d'un autre bailleur : invisible dans ma liste.
        Annonce.objects.create(bailleur=self.autre, ville=self.ville, titre='X')
        r = self.client.get('/api/v1/annonces/')
        ids = [a['id'] for a in r.data['results']]
        self.assertEqual(len(ids), 1)

    def test_publier_via_api_refuse_sans_photo_puis_ok_avec_photo(self):
        a = Annonce.objects.create(
            bailleur=self.bailleur, ville=self.ville, quartier=self.quartier,
            titre='Bel appart', type_bien='appartement', nb_chambres=2,
            loyer=Decimal('120000'), description='Joli logement.')
        # Sans photo → 400 avec liste d'erreurs.
        r = self.client.post(f'/api/v1/annonces/{a.id}/publier/')
        self.assertEqual(r.status_code, 400)
        self.assertIn('erreurs', r.data)
        # Upload d'une photo (multipart) → couverture.
        r = self.client.post(
            f'/api/v1/annonces/{a.id}/photos/',
            {'image': SimpleUploadedFile('p.jpg', _JPEG, content_type='image/jpeg')},
            format='multipart')
        self.assertEqual(r.status_code, 201)
        self.assertTrue(r.data['est_couverture'])
        # Publication OK.
        r = self.client.post(f'/api/v1/annonces/{a.id}/publier/')
        self.assertEqual(r.status_code, 200)
        self.assertEqual(r.data['statut'], 'publiee')
        self.assertTrue(r.data['url_publique'].endswith(f'/logements/annonce/{r.data["slug"]}/'))

    def test_localisations_villes_non_paginee(self):
        r = self.client.get('/api/v1/localisations/villes/')
        self.assertEqual(r.status_code, 200)
        self.assertIsInstance(r.data, list)  # pagination désactivée
        villes = {v['slug']: v for v in r.data}
        self.assertIn('douala', villes)
        self.assertIn('bonamoussadi', [q['slug'] for q in villes['douala']['quartiers']])

    def test_scoping_autre_bailleur_404(self):
        a = Annonce.objects.create(bailleur=self.autre, ville=self.ville, titre='X')
        r = self.client.get(f'/api/v1/annonces/{a.id}/')
        self.assertEqual(r.status_code, 404)
        r = self.client.post(f'/api/v1/annonces/{a.id}/publier/')
        self.assertEqual(r.status_code, 404)


@override_settings(MEDIA_ROOT=tempfile.mkdtemp())
class AnnoncePubliqueTests(TestCase):
    def setUp(self):
        self.bailleur = User.objects.create_user(email='b@test.cm', password='x')
        self.ville = Ville.objects.create(nom='Douala', slug='douala')
        self.quartier = Quartier.objects.create(
            ville=self.ville, nom='Bonamoussadi', slug='bonamoussadi')
        self.annonce = Annonce.objects.create(
            bailleur=self.bailleur, ville=self.ville, quartier=self.quartier,
            titre='Bel appart', type_bien='appartement', nb_chambres=2,
            loyer=Decimal('120000'), description='Joli logement.')
        PhotoAnnonce.objects.create(
            annonce=self.annonce, est_couverture=True,
            image=SimpleUploadedFile('p.jpg', _JPEG, content_type='image/jpeg'))
        services.publier(self.annonce)
        self.annonce.refresh_from_db()

    def test_page_publique_ok_seo(self):
        r = self.client.get(f'/logements/annonce/{self.annonce.slug}/')
        self.assertEqual(r.status_code, 200)
        html = r.content.decode()
        self.assertIn('RealEstateListing', html)          # JSON-LD
        self.assertIn('property="og:image"', html)        # aperçu partage
        self.assertIn('rel="canonical"', html)
        self.assertIn('120 000 FCFA', html)               # prix formaté

    def test_brouillon_et_expiree_404(self):
        brouillon = Annonce.objects.create(
            bailleur=self.bailleur, ville=self.ville, titre='X')
        self.assertEqual(
            self.client.get(f'/logements/annonce/{brouillon.slug}/').status_code, 404)
        Annonce.objects.filter(pk=self.annonce.pk).update(
            date_expiration=timezone.now() - timedelta(days=1))
        self.assertEqual(
            self.client.get(f'/logements/annonce/{self.annonce.slug}/').status_code, 404)

    def test_compteur_vues_une_fois_par_session(self):
        url = f'/logements/annonce/{self.annonce.slug}/'
        self.client.get(url)
        self.client.get(url)
        self.annonce.refresh_from_db()
        self.assertEqual(self.annonce.nb_vues, 1)

    def test_sitemap_et_robots(self):
        r = self.client.get('/logements/sitemap.xml')
        self.assertEqual(r.status_code, 200)
        self.assertIn(self.annonce.slug, r.content.decode())
        r = self.client.get('/robots.txt')
        self.assertEqual(r.status_code, 200)
        self.assertIn('Disallow: /api/', r.content.decode())


@override_settings(MEDIA_ROOT=tempfile.mkdtemp())
class AnnoncesListeTests(TestCase):
    def setUp(self):
        self.bailleur = User.objects.create_user(email='b@test.cm', password='x')
        self.ville = Ville.objects.create(nom='Douala', slug='douala')
        self.quartier = Quartier.objects.create(
            ville=self.ville, nom='Bonamoussadi', slug='bonamoussadi')
        self.annonce = Annonce.objects.create(
            bailleur=self.bailleur, ville=self.ville, quartier=self.quartier,
            titre='Bel appart', type_bien='appartement', nb_chambres=2,
            loyer=Decimal('120000'), description='Joli logement.')
        PhotoAnnonce.objects.create(
            annonce=self.annonce, est_couverture=True,
            image=SimpleUploadedFile('p.jpg', _JPEG, content_type='image/jpeg'))
        services.publier(self.annonce)
        self.annonce.refresh_from_db()

    def test_accueil(self):
        r = self.client.get('/logements/')
        self.assertEqual(r.status_code, 200)
        html = r.content.decode()
        self.assertIn('Douala', html)
        self.assertIn(self.annonce.slug, html)

    def test_page_ville_seo(self):
        r = self.client.get('/logements/louer/douala/')
        self.assertEqual(r.status_code, 200)
        html = r.content.decode()
        self.assertIn('BreadcrumbList', html)
        self.assertIn('ItemList', html)
        self.assertIn('rel="canonical"', html)
        self.assertIn(self.annonce.slug, html)

    def test_page_quartier_et_type(self):
        self.assertEqual(self.client.get('/logements/louer/douala/bonamoussadi/').status_code, 200)
        r = self.client.get('/logements/louer/douala/bonamoussadi/appartement/')
        self.assertEqual(r.status_code, 200)
        self.assertIn(self.annonce.slug, r.content.decode())

    def test_combo_type_chambres(self):
        # L'annonce a 2 chambres → présente sur la page combo « 2 chambres ».
        r = self.client.get('/logements/louer/douala/bonamoussadi/appartement-2-chambres/')
        self.assertEqual(r.status_code, 200)
        self.assertIn(self.annonce.slug, r.content.decode())
        # 5 chambres → aucune annonce.
        r = self.client.get('/logements/louer/douala/bonamoussadi/appartement-5-chambres/')
        self.assertEqual(r.status_code, 200)
        self.assertNotIn(self.annonce.slug, r.content.decode())

    def test_recherche_noindex(self):
        r = self.client.get('/logements/recherche/?ville=douala&type=appartement')
        self.assertEqual(r.status_code, 200)
        self.assertIn('noindex', r.content.decode())
        self.assertIn(self.annonce.slug, r.content.decode())

    def test_404_ville_et_type_invalides(self):
        self.assertEqual(self.client.get('/logements/louer/inexistante/').status_code, 404)
        self.assertEqual(
            self.client.get('/logements/louer/douala/bonamoussadi/xxx/').status_code, 404)

    def test_sitemap_inclut_localisations(self):
        html = self.client.get('/logements/sitemap.xml').content.decode()
        self.assertIn('/logements/louer/douala/', html)
        self.assertIn('/logements/louer/douala/bonamoussadi/', html)
        self.assertIn(self.annonce.slug, html)


@override_settings(DEBUG=True)  # nécessaire pour récupérer le dev_code de l'OTP
class MessagerieTests(TestCase):
    def setUp(self):
        self.bailleur = User.objects.create_user(email='b@test.cm', password='x')
        self.ville = Ville.objects.create(nom='Douala', slug='douala')
        self.annonce = Annonce.objects.create(
            bailleur=self.bailleur, ville=self.ville, titre='Bel appart',
            type_bien='appartement', loyer=Decimal('120000'))

    def _chercheur_verifie(self, tel='650000000'):
        ch, extra = envoyer_otp_chercheur(tel, nom='Ali')
        self.assertTrue(verifier_otp_chercheur(ch, extra['dev_code']))
        ch.refresh_from_db()
        return ch

    def test_otp_envoi_et_verification(self):
        ch, extra = envoyer_otp_chercheur('650000001', nom='Ali')
        self.assertIn('dev_code', extra)          # DEBUG
        self.assertFalse(ch.est_verifie)
        self.assertFalse(verifier_otp_chercheur(ch, '000000'))  # mauvais code
        self.assertTrue(verifier_otp_chercheur(ch, extra['dev_code']))
        ch.refresh_from_db()
        self.assertTrue(ch.est_verifie)

    def test_otp_antispam(self):
        envoyer_otp_chercheur('650000002')
        with self.assertRaises(MessagerieError):
            envoyer_otp_chercheur('650000002')  # < 60 s → bloqué

    def test_contact_exige_verification(self):
        ch = Chercheur.objects.create(telephone='650000003')  # non vérifié
        with self.assertRaises(MessagerieError):
            demarrer_conversation(self.annonce, ch, 'Bonjour')

    def test_demarrer_conversation_notifie_bailleur_et_masque_numero(self):
        from locataires.models import Notification
        ch = self._chercheur_verifie()
        conv = demarrer_conversation(self.annonce, ch, 'Dispo ? Appelez 690112233')
        self.assertEqual(conv.messages.count(), 1)
        msg = conv.messages.first()
        self.assertEqual(msg.expediteur, 'chercheur')
        self.assertNotIn('690112233', msg.corps)          # numéro masqué
        self.annonce.refresh_from_db()
        self.assertEqual(self.annonce.nb_contacts, 1)
        self.assertTrue(Notification.objects.filter(
            bailleur=self.bailleur, type_notif='discussion').exists())

    def test_conversation_unique_par_annonce_chercheur(self):
        ch = self._chercheur_verifie()
        c1 = demarrer_conversation(self.annonce, ch, 'Premier')
        c2 = demarrer_conversation(self.annonce, ch, 'Deuxième')
        self.assertEqual(c1.pk, c2.pk)                     # même conversation
        self.assertEqual(c1.messages.count(), 2)

    def test_repondre(self):
        ch = self._chercheur_verifie()
        conv = demarrer_conversation(self.annonce, ch, 'Bonjour')
        repondre(conv, 'bailleur', 'Oui, disponible.')
        self.assertEqual(conv.messages.count(), 2)
        self.assertEqual(conv.messages.last().expediteur, 'bailleur')


@override_settings(MEDIA_ROOT=tempfile.mkdtemp(), DEBUG=True)
class MessagerieWebTests(TestCase):
    def setUp(self):
        self.bailleur = User.objects.create_user(email='b@test.cm', password='x')
        self.ville = Ville.objects.create(nom='Douala', slug='douala')
        self.annonce = Annonce.objects.create(
            bailleur=self.bailleur, ville=self.ville, titre='Bel appart',
            type_bien='appartement', loyer=Decimal('120000'), description='Joli.')
        PhotoAnnonce.objects.create(
            annonce=self.annonce, est_couverture=True,
            image=SimpleUploadedFile('p.jpg', _JPEG, content_type='image/jpeg'))
        services.publier(self.annonce)
        self.annonce.refresh_from_db()
        self.url = f'/logements/annonce/{self.annonce.slug}/contacter/'

    def test_cta_active_sur_detail(self):
        html = self.client.get(f'/logements/annonce/{self.annonce.slug}/').content.decode()
        self.assertIn(f'/logements/annonce/{self.annonce.slug}/contacter/', html)
        self.assertIn('/signaler/', html)

    def test_parcours_contact_complet(self):
        # 1) téléphone → étape OTP (dev_code exposé en DEBUG)
        r = self.client.post(self.url, {'etape': 'phone', 'telephone': '650000010', 'nom': 'Ali'})
        self.assertEqual(r.status_code, 200)
        self.assertEqual(r.context['etape'], 'otp')
        code = r.context['dev_code']
        self.assertTrue(code)
        # 2) OTP → étape message
        r = self.client.post(self.url, {'etape': 'otp', 'code': code})
        self.assertEqual(r.context['etape'], 'message')
        # 3) message → redirection vers le fil + conversation créée
        r = self.client.post(self.url, {'etape': 'message', 'corps': 'Dispo ? 690112233'})
        self.assertEqual(r.status_code, 302)
        self.assertIn('/logements/messages/', r['Location'])
        self.assertEqual(Conversation.objects.count(), 1)
        conv = Conversation.objects.first()
        self.assertNotIn('690112233', conv.messages.first().corps)  # numéro masqué

    def test_numero_deja_verifie_saute_otp(self):
        Chercheur.objects.create(telephone='650000011', verifie_le=timezone.now())
        r = self.client.post(self.url, {'etape': 'phone', 'telephone': '650000011'})
        self.assertEqual(r.context['etape'], 'message')  # OTP sauté

    def test_fil_et_reponse_chercheur(self):
        ch = Chercheur.objects.create(telephone='650000012', verifie_le=timezone.now())
        conv = demarrer_conversation(self.annonce, ch, 'Bonjour')
        url = f'/logements/messages/{conv.token}/'
        self.assertEqual(self.client.get(url).status_code, 200)
        r = self.client.post(url, {'corps': 'Je peux visiter demain ?'})
        self.assertEqual(r.status_code, 302)
        conv.refresh_from_db()
        self.assertEqual(conv.messages.count(), 2)

    def test_signaler(self):
        url = f'/logements/annonce/{self.annonce.slug}/signaler/'
        r = self.client.post(url, {'motif': 'Logement déjà loué'})
        self.assertEqual(r.status_code, 200)
        self.assertTrue(r.context['envoye'])
        self.assertEqual(Signalement.objects.filter(annonce=self.annonce).count(), 1)


class MessagerieAPITests(TestCase):
    def setUp(self):
        self.bailleur = User.objects.create_user(email='b@test.cm', password='x')
        self.autre = User.objects.create_user(email='autre@test.cm', password='x')
        self.ville = Ville.objects.create(nom='Douala', slug='douala')
        self.annonce = Annonce.objects.create(
            bailleur=self.bailleur, ville=self.ville, titre='Bel appart',
            type_bien='appartement', loyer=Decimal('120000'))
        self.chercheur = Chercheur.objects.create(
            telephone='650000020', nom='Ali', verifie_le=timezone.now())
        self.conv = demarrer_conversation(self.annonce, self.chercheur, 'Bonjour, dispo ?')
        self.client = APIClient()
        self.client.force_authenticate(self.bailleur)

    def test_liste_conversations_scoping_et_non_lus(self):
        r = self.client.get('/api/v1/conversations/')
        self.assertEqual(r.status_code, 200)
        self.assertEqual(len(r.data['results']), 1)
        self.assertEqual(r.data['results'][0]['non_lus'], 1)  # message chercheur non lu
        # L'autre bailleur ne voit rien.
        self.client.force_authenticate(self.autre)
        self.assertEqual(len(self.client.get('/api/v1/conversations/').data['results']), 0)

    def test_retrieve_marque_lu(self):
        r = self.client.get(f'/api/v1/conversations/{self.conv.id}/')
        self.assertEqual(r.status_code, 200)
        self.assertEqual(len(r.data['messages']), 1)
        # Après ouverture, plus de non-lus.
        r = self.client.get('/api/v1/conversations/')
        self.assertEqual(r.data['results'][0]['non_lus'], 0)

    def test_repondre(self):
        r = self.client.post(f'/api/v1/conversations/{self.conv.id}/repondre/',
                             {'corps': 'Oui, disponible.'}, format='json')
        self.assertEqual(r.status_code, 200)
        self.assertEqual(len(r.data['messages']), 2)
        self.assertEqual(r.data['messages'][-1]['expediteur'], 'bailleur')

    def test_scoping_404(self):
        self.client.force_authenticate(self.autre)
        self.assertEqual(
            self.client.get(f'/api/v1/conversations/{self.conv.id}/').status_code, 404)

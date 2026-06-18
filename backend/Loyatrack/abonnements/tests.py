from datetime import timedelta

from django.contrib.auth import get_user_model
from django.test import Client
from django.utils import timezone
from rest_framework.test import APITestCase

from . import constants, services
from .models import Abonnement, JetonAccesBailleur

Bailleur = get_user_model()


def _token_de_url(url):
    return url.rstrip('/').split('/')[-1]


def _u(email='b@test.local'):
    return Bailleur.objects.create_user(email=email, password='Passw0rd!')


class AbonnementModeleTests(APITestCase):
    def test_essai_cree_a_inscription(self):
        u = _u()
        ab = u.abonnement  # créé par le signal post_save
        self.assertEqual(ab.statut, 'essai')
        self.assertTrue(ab.est_actif)
        self.assertEqual(ab.droits, 'pro')               # Pro débloqué pendant l'essai
        self.assertTrue(ab.a_droit('comptabilite'))
        self.assertIsNone(ab.max_biens)                  # illimité

    def test_essai_expire_bloque_tout(self):
        u = _u()
        ab = u.abonnement
        ab.date_fin_essai = timezone.now() - timedelta(days=1)
        ab.save()
        self.assertFalse(ab.est_actif)
        self.assertIsNone(ab.droits)
        self.assertFalse(ab.a_droit('rappels_auto'))
        self.assertEqual(ab.max_biens, 0)

    def test_essentiel_actif_droits_limites(self):
        u = _u()
        services.activer_abonnement(u, 'essentiel', 'mensuel')
        ab = u.abonnement
        ab.refresh_from_db()
        self.assertEqual(ab.statut, 'actif')
        self.assertEqual(ab.droits, 'essentiel')
        self.assertTrue(ab.a_droit('quittance'))         # non listé Pro → autorisé
        self.assertFalse(ab.a_droit('comptabilite'))     # Pro → refusé
        self.assertEqual(ab.max_biens, 1)

    def test_grace_3_jours(self):
        u = _u()
        services.activer_abonnement(u, 'pro', 'mensuel')
        ab = u.abonnement
        # fin dépassée d'1 jour → encore actif via grâce
        ab.statut = 'grace'
        ab.date_fin = timezone.now() - timedelta(days=1)
        ab.save()
        self.assertTrue(ab.est_actif)
        # au-delà de 3 jours → plus actif
        ab.date_fin = timezone.now() - timedelta(days=4)
        ab.save()
        self.assertFalse(ab.est_actif)


class ActivationTests(APITestCase):
    def test_activation_prolonge_un_mois(self):
        u = _u()
        ab = services.activer_abonnement(u, 'pro', 'mensuel')
        attendu = timezone.now() + timedelta(days=27)
        self.assertGreater(ab.date_fin, attendu)
        self.assertEqual(ab.statut, 'actif')

    def test_webhook_idempotent(self):
        u = _u()
        tx = services.creer_transaction(u, 'pro', 'mensuel')
        services.activer_depuis_transaction(tx)
        fin1 = u.abonnement.date_fin
        # rejouer la même transaction ne doit pas re-prolonger
        services.activer_depuis_transaction(tx)
        u.abonnement.refresh_from_db()
        self.assertEqual(u.abonnement.date_fin, fin1)

    def test_expirer_abonnements_transitions(self):
        u1, u2, u3 = _u('a@t.l'), _u('b@t.l'), _u('c@t.l')
        # essai dépassé
        u1.abonnement.date_fin_essai = timezone.now() - timedelta(days=1)
        u1.abonnement.save()
        # actif dépassé → grâce
        services.activer_abonnement(u2, 'pro', 'mensuel')
        u2.abonnement.date_fin = timezone.now() - timedelta(days=1)
        u2.abonnement.save()
        # grâce dépassée → expiré
        services.activer_abonnement(u3, 'pro', 'mensuel')
        u3.abonnement.statut = 'grace'
        u3.abonnement.date_fin = timezone.now() - timedelta(days=5)
        u3.abonnement.save()

        res = services.expirer_abonnements()
        u1.abonnement.refresh_from_db(); u2.abonnement.refresh_from_db(); u3.abonnement.refresh_from_db()
        self.assertEqual(u1.abonnement.statut, 'expire')
        self.assertEqual(u2.abonnement.statut, 'grace')
        self.assertEqual(u3.abonnement.statut, 'expire')
        self.assertEqual(res['expire'], 2)


class GatingApiTests(APITestCase):
    def test_statut_endpoint_accessible_meme_expire(self):
        u = _u()
        u.abonnement.date_fin_essai = timezone.now() - timedelta(days=1)
        u.abonnement.save()
        self.client.force_authenticate(u)
        r = self.client.get('/api/v1/abonnement/')
        self.assertEqual(r.status_code, 200)
        self.assertFalse(r.data['est_actif'])
        self.assertIsNone(r.data['droits'])

    def test_expire_bloque_locataires(self):
        u = _u()
        u.abonnement.date_fin_essai = timezone.now() - timedelta(days=1)
        u.abonnement.save()
        self.client.force_authenticate(u)
        r = self.client.get('/api/v1/locataires/')
        self.assertEqual(r.status_code, 403)
        self.assertEqual(r.data.get('code'), 'abonnement_expire')

    def test_essentiel_bloque_comptabilite(self):
        u = _u()
        services.activer_abonnement(u, 'essentiel', 'mensuel')
        self.client.force_authenticate(u)
        r = self.client.get('/api/v1/depenses/')
        self.assertEqual(r.status_code, 403)
        self.assertEqual(r.data.get('code'), 'fonction_pro')

    def test_essentiel_bloque_contrat(self):
        u = _u()
        services.activer_abonnement(u, 'essentiel', 'mensuel')
        self.client.force_authenticate(u)
        r = self.client.get('/api/v1/locataires/1/contrat/')
        self.assertEqual(r.status_code, 403)
        self.assertEqual(r.data.get('code'), 'fonction_pro')

    def test_essai_autorise_comptabilite(self):
        u = _u()
        self.client.force_authenticate(u)
        r = self.client.get('/api/v1/depenses/')
        self.assertEqual(r.status_code, 200)  # essai = Pro

    def test_checkout_puis_webhook_active(self):
        u = _u()
        # expire l'essai pour repartir d'un état non actif
        u.abonnement.date_fin_essai = timezone.now() - timedelta(days=1)
        u.abonnement.save()
        self.client.force_authenticate(u)
        r = self.client.post('/api/v1/abonnement/checkout/', {'plan': 'pro', 'periodicite': 'mensuel'}, format='json')
        self.assertEqual(r.status_code, 201)
        ref = r.data['reference']
        self.assertEqual(r.data['montant'], 8000)
        # webhook prestataire (fake) → activation
        w = self.client.post('/api/v1/webhooks/paiement/', {'reference': ref, 'statut': 'reussi'}, format='json')
        self.assertEqual(w.status_code, 200)
        u.abonnement.refresh_from_db()
        self.assertEqual(u.abonnement.statut, 'actif')
        self.assertEqual(u.abonnement.plan, 'pro')

    def test_plans_catalogue(self):
        u = _u()
        self.client.force_authenticate(u)
        r = self.client.get('/api/v1/abonnement/plans/')
        self.assertEqual(r.status_code, 200)
        plans = {p['cle']: p for p in r.data['plans']}
        self.assertEqual(plans['pro']['mensuel'], 8000)
        self.assertEqual(plans['essentiel']['mensuel'], 3000)


class MagicLinkWebTests(APITestCase):
    def test_lien_usage_unique_ouvre_session(self):
        u = _u()
        self.client.force_authenticate(u)
        r = self.client.post('/api/v1/abonnement/lien-web/')
        self.assertEqual(r.status_code, 200)
        token = _token_de_url(r.data['url'])

        web = Client()
        resp = web.get(f'/abonnement/acces/{token}/')
        self.assertEqual(resp.status_code, 302)          # connexion → redirect espace
        self.assertEqual(web.get('/abonnement/').status_code, 200)

        # réutilisation du même token → invalide (usage unique)
        autre = Client()
        self.assertEqual(autre.get(f'/abonnement/acces/{token}/').status_code, 404)

    def test_lien_expire_apres_10_min(self):
        u = _u()
        j = JetonAccesBailleur.objects.create(bailleur=u)
        JetonAccesBailleur.objects.filter(pk=j.pk).update(
            date_creation=timezone.now() - timedelta(minutes=11))
        self.assertEqual(Client().get(f'/abonnement/acces/{j.token}/').status_code, 404)

    def test_paiement_web_fake_active(self):
        u = _u()
        u.abonnement.date_fin_essai = timezone.now() - timedelta(days=1)
        u.abonnement.save()
        self.client.force_authenticate(u)
        token = _token_de_url(self.client.post('/api/v1/abonnement/lien-web/').data['url'])

        web = Client()
        web.get(f'/abonnement/acces/{token}/')  # ouvre la session
        r = web.post('/abonnement/payer/', {'plan': 'essentiel', 'periodicite': 'mensuel'})
        self.assertEqual(r.status_code, 302)
        self.assertIn('checkout/fake', r.url)
        ref = r.url.split('ref=')[-1]
        r2 = web.post(f'/abonnement/checkout/fake/?ref={ref}')
        self.assertEqual(r2.status_code, 302)
        u.abonnement.refresh_from_db()
        self.assertEqual(u.abonnement.statut, 'actif')
        self.assertEqual(u.abonnement.plan, 'essentiel')


class RappelsExpirationTests(APITestCase):
    def test_rappel_essai_et_throttle(self):
        from .tasks import rappels_expiration
        from locataires.models import Notification
        u = _u()
        u.abonnement.date_fin_essai = timezone.now() + timedelta(days=1, hours=1)  # J-1
        u.abonnement.save()

        n = rappels_expiration()
        self.assertGreaterEqual(n, 1)
        self.assertTrue(Notification.objects.filter(bailleur=u, type_notif='systeme').exists())

        # relancer le même jour ne crée pas de doublon (throttle)
        avant = Notification.objects.filter(bailleur=u).count()
        rappels_expiration()
        self.assertEqual(Notification.objects.filter(bailleur=u).count(), avant)


class RecuPdfTests(APITestCase):
    def test_recu_pdf_genere(self):
        from .pdf import generer_recu_abonnement_pdf
        u = _u()
        tx = services.creer_transaction(u, 'pro', 'mensuel')
        services.activer_depuis_transaction(tx)
        pdf = generer_recu_abonnement_pdf(tx)
        self.assertTrue(pdf.startswith(b'%PDF'))

    def test_recu_web_proprietaire(self):
        u = _u()
        tx = services.creer_transaction(u, 'pro', 'mensuel')
        services.activer_depuis_transaction(tx)
        self.client.force_authenticate(u)
        token = _token_de_url(self.client.post('/api/v1/abonnement/lien-web/').data['url'])
        web = Client()
        web.get(f'/abonnement/acces/{token}/')  # session
        r = web.get(f'/abonnement/recu/{tx.reference_interne}/')
        self.assertEqual(r.status_code, 200)
        self.assertEqual(r['Content-Type'], 'application/pdf')

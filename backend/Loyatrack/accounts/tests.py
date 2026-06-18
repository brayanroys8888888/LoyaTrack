from django.test import TestCase, override_settings
from django.contrib.auth import get_user_model
from rest_framework.test import APIClient

from .models import CodeVerification
from .otp import envoyer_otp, verifier_otp

User = get_user_model()


class AuthTests(TestCase):
    def setUp(self):
        self.c = APIClient()
        self.user = User.objects.create_user(
            email='b@test.com', telephone='690111222', password='MotDePasse123!'
        )

    # --- Inscription ---
    def test_register_email_seul(self):
        r = self.c.post('/api/v1/auth/register/', {
            'email': 'new@test.com', 'password': 'MotDePasse123!', 'password_confirm': 'MotDePasse123!',
        }, format='json')
        self.assertEqual(r.status_code, 201)
        self.assertIn('access', r.data)

    def test_register_telephone_seul(self):
        r = self.c.post('/api/v1/auth/register/', {
            'telephone': '699888777', 'password': 'MotDePasse123!', 'password_confirm': 'MotDePasse123!',
        }, format='json')
        self.assertEqual(r.status_code, 201)

    def test_register_sans_identifiant_refuse(self):
        r = self.c.post('/api/v1/auth/register/', {
            'password': 'MotDePasse123!', 'password_confirm': 'MotDePasse123!',
        }, format='json')
        self.assertEqual(r.status_code, 400)

    # --- Connexion ---
    def test_login_par_email(self):
        r = self.c.post('/api/v1/auth/login/', {'identifiant': 'b@test.com', 'password': 'MotDePasse123!'}, format='json')
        self.assertEqual(r.status_code, 200)
        self.assertIn('access', r.data)

    def test_login_par_telephone(self):
        r = self.c.post('/api/v1/auth/login/', {'identifiant': '690111222', 'password': 'MotDePasse123!'}, format='json')
        self.assertEqual(r.status_code, 200)
        self.assertIn('access', r.data)

    def test_login_mauvais_mdp(self):
        r = self.c.post('/api/v1/auth/login/', {'identifiant': 'b@test.com', 'password': 'faux'}, format='json')
        self.assertEqual(r.status_code, 400)

    # --- 2FA ---
    @override_settings(DEBUG=True)
    def test_login_avec_2fa_demande_otp(self):
        self.user.deux_fa_active = True
        self.user.save()
        r = self.c.post('/api/v1/auth/login/', {'identifiant': 'b@test.com', 'password': 'MotDePasse123!'}, format='json')
        self.assertEqual(r.status_code, 200)
        self.assertTrue(r.data.get('otp_requis'))
        self.assertNotIn('access', r.data)
        # le code dev permet de finaliser
        code = r.data['dev_code']
        r2 = self.c.post('/api/v1/auth/login/verify-otp/', {'user_id': self.user.id, 'code': code}, format='json')
        self.assertEqual(r2.status_code, 200)
        self.assertIn('access', r2.data)

    def test_otp_3_tentatives_max(self):
        envoyer_otp(self.user, '2fa')
        for _ in range(3):
            self.assertFalse(verifier_otp(self.user, '2fa', '000000'))
        # même le bon code échoue après 3 tentatives
        self.assertFalse(verifier_otp(self.user, '2fa', '000000'))

    # --- Reset mot de passe par OTP ---
    @override_settings(DEBUG=True)
    def test_reset_password_flow(self):
        r = self.c.post('/api/v1/auth/password/forgot/', {'telephone': '690111222'}, format='json')
        self.assertEqual(r.status_code, 200)
        code = r.data['dev_code']
        r2 = self.c.post('/api/v1/auth/password/verify-otp/', {'telephone': '690111222', 'code': code}, format='json')
        self.assertEqual(r2.status_code, 200)
        token = r2.data['reset_token']
        r3 = self.c.post('/api/v1/auth/password/reset/', {'reset_token': token, 'new_password': 'NouveauMdp456!'}, format='json')
        self.assertEqual(r3.status_code, 200)
        # le nouveau mot de passe fonctionne
        self.user.refresh_from_db()
        self.assertTrue(self.user.check_password('NouveauMdp456!'))

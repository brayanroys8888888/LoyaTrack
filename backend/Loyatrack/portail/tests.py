from datetime import date

from django.contrib.auth import get_user_model
from django.test import TestCase
from django.utils import timezone

from locataires.models import Locataire
from .models import AccesPortail

User = get_user_model()


class PortailTests(TestCase):
    def setUp(self):
        self.b = User.objects.create_user(email='b@test.com', password='x')
        self.loc = Locataire.objects.create(
            bailleur=self.b, nom='Doe', prenom='J', telephone='690',
            montant_loyer=50000, jour_echeance=1, date_entree=date(2024, 1, 1),
        )

    def test_creation_et_validite_token(self):
        acces = AccesPortail.creer_ou_regenerer(self.loc)
        self.assertTrue(acces.est_valide)
        self.assertGreater(len(acces.token), 20)

    def test_page_publique_valide(self):
        acces = AccesPortail.creer_ou_regenerer(self.loc)
        resp = self.client.get(f'/portail/{acces.token}/')
        self.assertEqual(resp.status_code, 200)
        self.assertContains(resp, 'Doe')

    def test_page_token_invalide(self):
        resp = self.client.get('/portail/inexistant/')
        self.assertEqual(resp.status_code, 404)

    def test_token_expire(self):
        acces = AccesPortail.creer_ou_regenerer(self.loc)
        acces.date_expiration = timezone.now() - timezone.timedelta(days=1)
        acces.save()
        resp = self.client.get(f'/portail/{acces.token}/')
        self.assertEqual(resp.status_code, 404)

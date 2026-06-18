import secrets
from datetime import timedelta

from django.db import models
from django.utils import timezone

from locataires.models import Locataire


def _token():
    return secrets.token_urlsafe(32)


class AccesPortail(models.Model):
    """Accès web sécurisé en lecture seule pour un locataire — module 3.5."""
    locataire = models.OneToOneField(Locataire, on_delete=models.CASCADE, related_name='acces_portail')
    token = models.CharField(max_length=64, unique=True, default=_token, db_index=True)
    date_creation = models.DateTimeField(auto_now_add=True)
    date_expiration = models.DateTimeField()
    actif = models.BooleanField(default=True)

    def __str__(self):
        return f"Accès portail - {self.locataire}"

    @property
    def est_valide(self):
        return self.actif and self.date_expiration > timezone.now()

    def regenerer(self, jours=90):
        self.token = _token()
        self.date_expiration = timezone.now() + timedelta(days=jours)
        self.actif = True
        self.save()
        return self

    @classmethod
    def creer_ou_regenerer(cls, locataire, jours=90):
        acces, _ = cls.objects.get_or_create(
            locataire=locataire,
            defaults={'date_expiration': timezone.now() + timedelta(days=jours)},
        )
        return acces.regenerer(jours)

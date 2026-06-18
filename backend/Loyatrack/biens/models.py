from django.db import models
from django.conf import settings


class Propriete(models.Model):
    TYPE_CHOICES = (
        ('appartement', 'Appartement'),
        ('villa', 'Villa'),
        ('studio', 'Studio'),
        ('immeuble', 'Immeuble'),
        ('autre', 'Autre'),
    )

    bailleur = models.ForeignKey(
        settings.AUTH_USER_MODEL, on_delete=models.CASCADE, related_name='proprietes'
    )
    titre = models.CharField(max_length=150)
    adresse = models.CharField(max_length=255, blank=True)
    type = models.CharField(max_length=20, choices=TYPE_CHOICES, default='immeuble')
    date_creation = models.DateTimeField(auto_now_add=True)

    class Meta:
        ordering = ['titre']

    def __str__(self):
        return self.titre


class UniteLogement(models.Model):
    STATUT_CHOICES = (
        ('occupe', 'Occupé'),
        ('vacant', 'Vacant'),
    )

    propriete = models.ForeignKey(Propriete, on_delete=models.CASCADE, related_name='unites')
    numero = models.CharField(max_length=100)
    loyer_standard = models.DecimalField(max_digits=10, decimal_places=2, default=0)
    statut = models.CharField(max_length=10, choices=STATUT_CHOICES, default='vacant')
    date_creation = models.DateTimeField(auto_now_add=True)

    class Meta:
        ordering = ['propriete', 'numero']

    def __str__(self):
        return f"{self.propriete.titre} - {self.numero}"

    @property
    def est_occupee(self):
        """Une unité est occupée si un locataire non supprimé y est rattaché."""
        return self.locataires.filter(is_deleted=False).exists()

    def synchroniser_statut(self):
        nouveau = 'occupe' if self.est_occupee else 'vacant'
        if self.statut != nouveau:
            self.statut = nouveau
            self.save(update_fields=['statut'])

from django.db import models
from django.conf import settings


class Depense(models.Model):
    """Dépense liée à un bien (entretien, taxe, etc.) — module 3.4."""
    CATEGORIE_CHOICES = (
        ('entretien', 'Entretien / Réparation'),
        ('taxe', 'Taxe / Impôt'),
        ('charge', 'Charge (eau, électricité…)'),
        ('assurance', 'Assurance'),
        ('autre', 'Autre'),
    )

    bailleur = models.ForeignKey(settings.AUTH_USER_MODEL, on_delete=models.CASCADE, related_name='depenses')
    bien = models.ForeignKey('biens.Propriete', on_delete=models.SET_NULL, null=True, blank=True, related_name='depenses')
    libelle = models.CharField(max_length=200)
    montant = models.DecimalField(max_digits=12, decimal_places=2)
    date = models.DateField()
    categorie = models.CharField(max_length=20, choices=CATEGORIE_CHOICES, default='autre')
    date_creation = models.DateTimeField(auto_now_add=True)

    class Meta:
        ordering = ['-date']

    def __str__(self):
        return f"{self.libelle} - {self.montant} FCFA"

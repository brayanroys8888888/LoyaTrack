from django.db import models
from locataires.models import Locataire


class Paiement(models.Model):
    MODE_CHOICES = (
        ('Mobile Money', 'Mobile Money'),
        ('Espèces', 'Espèces'),
        ('Virement', 'Virement'),
    )
    STATUT_CHOICES = (
        ('complet', 'Complet'),
        ('partiel', 'Partiel'),
        ('avance', 'Avance'),
    )

    locataire = models.ForeignKey(Locataire, on_delete=models.CASCADE, related_name='paiements')
    montant = models.DecimalField(max_digits=10, decimal_places=2)
    date_paiement = models.DateField()
    mode_paiement = models.CharField(max_length=20, choices=MODE_CHOICES)
    reference = models.CharField(max_length=100, blank=True)

    # Période de loyer couverte par ce paiement
    periode_debut = models.DateField(null=True, blank=True)
    periode_fin = models.DateField(null=True, blank=True)
    nb_mois = models.IntegerField(default=1)

    statut = models.CharField(max_length=10, choices=STATUT_CHOICES, default='complet')
    # Reste dû sur la période après ce paiement (0 si complet/avance)
    reste_du = models.DecimalField(max_digits=10, decimal_places=2, default=0)

    date_creation = models.DateTimeField(auto_now_add=True)

    class Meta:
        ordering = ['-date_paiement', '-id']

    def __str__(self):
        return f"Paiement {self.montant} - {self.locataire}"

import calendar
from datetime import date
from decimal import Decimal

from django.db import models
from locataires.models import Locataire


class ConfigPenalite(models.Model):
    """
    Configuration de pénalité paramétrable par le bailleur, pour un locataire donné.
    Permet un délai de grâce et un calcul fixe (FCFA/jour) ou en pourcentage du loyer.
    """
    TYPE_CHOICES = (
        ('fixe', 'Montant fixe par jour'),
        ('pourcentage', 'Pourcentage du loyer par jour'),
    )

    locataire = models.OneToOneField(
        Locataire, on_delete=models.CASCADE, related_name='config_penalite'
    )
    actif = models.BooleanField(default=True)
    delai_grace = models.IntegerField(
        default=0, help_text="Nombre de jours de tolérance après l'échéance avant pénalité"
    )
    type_penalite = models.CharField(max_length=12, choices=TYPE_CHOICES, default='fixe')
    montant_fixe = models.DecimalField(
        max_digits=10, decimal_places=2, null=True, blank=True,
        help_text="Pénalité journalière en FCFA (si type=fixe)"
    )
    pourcentage = models.DecimalField(
        max_digits=5, decimal_places=2, default=0,
        help_text="Pourcentage du loyer par jour de retard (si type=pourcentage)"
    )

    def __str__(self):
        return f"Config pénalité - {self.locataire}"

    def montant_journalier(self):
        """Montant de la pénalité pour une journée de retard."""
        if self.type_penalite == 'pourcentage':
            return (self.locataire.montant_loyer * self.pourcentage / Decimal('100')).quantize(Decimal('0.01'))
        if self.montant_fixe is not None:
            return self.montant_fixe
        # Repli sur le défaut du bailleur
        return self.locataire.bailleur.penalite_defaut


def echeance_du_mois(annee, mois, jour_echeance):
    """Renvoie la date d'échéance pour un mois donné en gérant les mois courts
    (ex : jour 31 en février -> dernier jour du mois)."""
    dernier_jour = calendar.monthrange(annee, mois)[1]
    return date(annee, mois, min(jour_echeance, dernier_jour))


class Penalite(models.Model):
    STATUT_CHOICES = (
        ('Active', 'Active'),
        ('Clôturée', 'Clôturée'),
        ('Remise', 'Remise'),
    )

    locataire = models.ForeignKey(Locataire, on_delete=models.CASCADE, related_name='penalites')
    # Période de loyer concernée (1er jour du mois) — clé d'anti-doublon
    periode = models.DateField(null=True, blank=True)
    date_debut = models.DateField()
    date_fin = models.DateField(null=True, blank=True)
    montant_journalier = models.DecimalField(max_digits=10, decimal_places=2)
    total = models.DecimalField(max_digits=10, decimal_places=2, default=0)
    statut = models.CharField(max_length=10, choices=STATUT_CHOICES, default='Active')

    # Date de la dernière application journalière (anti double-comptage le même jour)
    date_derniere_application = models.DateField(null=True, blank=True)

    # Remise / annulation
    montant_remise = models.DecimalField(max_digits=10, decimal_places=2, default=0)
    motif_remise = models.TextField(blank=True)
    date_remise = models.DateTimeField(null=True, blank=True)

    class Meta:
        ordering = ['-date_debut']
        constraints = [
            models.UniqueConstraint(
                fields=['locataire', 'periode'],
                name='unique_penalite_par_periode',
                condition=models.Q(periode__isnull=False),
            )
        ]

    def __str__(self):
        return f"Pénalité {self.statut} - {self.locataire}"

    @property
    def montant_net(self):
        """Montant réellement dû après remise éventuelle."""
        net = self.total - self.montant_remise
        return net if net > 0 else Decimal('0')

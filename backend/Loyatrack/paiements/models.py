import uuid
from decimal import Decimal

from django.conf import settings
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


class CompteMarchand(models.Model):
    """Destination de reversement du bailleur — mode « encaissement centralisé ».

    LoyaTrack encaisse les loyers sur SON propre compte prestataire
    (settings.CINETPAY_*), puis reverse automatiquement le loyer net sur le
    numéro Mobile Money du bailleur renseigné ici. Le bailleur ne fournit donc
    aucune clé d'API : il indique seulement où recevoir son argent.
    """
    OPERATEUR_CHOICES = (
        ('mtn', 'MTN Mobile Money'),
        ('orange', 'Orange Money'),
    )
    bailleur = models.OneToOneField(
        settings.AUTH_USER_MODEL, on_delete=models.CASCADE, related_name='compte_marchand')
    prestataire = models.CharField(max_length=20, default='cinetpay')
    # Numéro Mobile Money sur lequel LoyaTrack reverse le loyer encaissé.
    numero_momo = models.CharField(max_length=20, blank=True)
    operateur = models.CharField(max_length=10, choices=OPERATEUR_CHOICES, default='mtn')
    # Frais (collecte + reversement) répercutés au locataire (ajoutés au montant).
    frais_pourcentage = models.DecimalField(max_digits=5, decimal_places=2, default=Decimal('2.00'))
    actif = models.BooleanField(default=False)
    date_creation = models.DateTimeField(auto_now_add=True)

    def est_configure(self):
        return bool(self.actif and self.numero_momo)

    def destination_reversement(self):
        """Cible du transfert Mobile Money (numéro + opérateur)."""
        return {'numero': self.numero_momo, 'operateur': self.operateur}

    def __str__(self):
        return f"CompteMarchand({self.bailleur} · {self.operateur})"


class DemandePaiement(models.Model):
    """Demande d'encaissement envoyée à un locataire (intention de paiement).

    Distincte d'un `Paiement` (= argent réellement reçu) : une demande peut
    échouer/expirer. Une fois payée, elle crée le `Paiement` correspondant.
    """
    STATUT_CHOICES = (
        ('en_attente', 'En attente'),
        ('payee', 'Payée'),
        ('echouee', 'Échouée'),
        ('expiree', 'Expirée'),
    )

    locataire = models.ForeignKey(Locataire, on_delete=models.CASCADE, related_name='demandes_paiement')
    reference_interne = models.UUIDField(default=uuid.uuid4, unique=True, editable=False)
    # Détail du montant (Décision : frais répercutés au locataire).
    montant = models.DecimalField(max_digits=10, decimal_places=2)      # total à payer
    montant_loyer = models.DecimalField(max_digits=10, decimal_places=2, default=0)
    frais = models.DecimalField(max_digits=10, decimal_places=2, default=0)
    periode = models.DateField(null=True, blank=True)                   # mois visé

    statut = models.CharField(max_length=12, choices=STATUT_CHOICES, default='en_attente')
    prestataire = models.CharField(max_length=20, default='cinetpay')
    url_paiement = models.URLField(max_length=500, blank=True)
    payload = models.JSONField(blank=True, null=True)                   # réponse webhook
    paiement = models.OneToOneField(
        Paiement, on_delete=models.SET_NULL, null=True, blank=True, related_name='demande')

    # Reversement du loyer net vers le compte Mobile Money du bailleur.
    REVERSEMENT_CHOICES = (
        ('non_requis', 'Non requis'),   # bailleur sans compte de reversement configuré
        ('en_attente', 'En attente'),
        ('effectue', 'Effectué'),
        ('echoue', 'Échoué'),
    )
    reversement_statut = models.CharField(
        max_length=12, choices=REVERSEMENT_CHOICES, default='non_requis')
    reversement_ref = models.CharField(max_length=100, blank=True)
    reversement_erreur = models.TextField(blank=True)

    date_creation = models.DateTimeField(auto_now_add=True)
    date_paiement = models.DateTimeField(null=True, blank=True)

    class Meta:
        ordering = ['-date_creation', '-id']

    def __str__(self):
        return f"Demande {self.montant} - {self.locataire} [{self.statut}]"

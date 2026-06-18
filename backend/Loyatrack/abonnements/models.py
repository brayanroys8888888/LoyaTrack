import calendar
import secrets
import uuid
from datetime import timedelta

from django.conf import settings
from django.db import models
from django.utils import timezone

from . import constants


def _token():
    return secrets.token_urlsafe(32)


def ajouter_mois_dt(dt, mois):
    """Ajoute `mois` mois à un datetime, en gérant les mois courts."""
    total = dt.month - 1 + mois
    annee = dt.year + total // 12
    m = total % 12 + 1
    jour = min(dt.day, calendar.monthrange(annee, m)[1])
    return dt.replace(year=annee, month=m, day=jour)


class Abonnement(models.Model):
    """Abonnement d'un bailleur (1-1). Gère l'essai, l'état payant et la grâce.

    `droits` est le niveau de fonctionnalités effectif : Pro pendant l'essai,
    sinon le plan payé tant que l'accès est valide, sinon None (expiré → blocage).
    """
    PLAN_CHOICES = (('essentiel', 'Essentiel'), ('pro', 'Pro'))
    STATUT_CHOICES = (
        ('essai', 'Essai'),
        ('actif', 'Actif'),
        ('grace', 'Grâce'),
        ('expire', 'Expiré'),
        ('annule', 'Annulé'),
    )
    PERIODICITE_CHOICES = (('mensuel', 'Mensuel'), ('annuel', 'Annuel'))

    bailleur = models.OneToOneField(
        settings.AUTH_USER_MODEL, on_delete=models.CASCADE, related_name='abonnement'
    )
    plan = models.CharField(max_length=12, choices=PLAN_CHOICES, default='pro')
    statut = models.CharField(max_length=10, choices=STATUT_CHOICES, default='essai')
    date_debut = models.DateTimeField(auto_now_add=True)
    date_fin_essai = models.DateTimeField(null=True, blank=True)
    date_fin = models.DateTimeField(null=True, blank=True)  # fin de période payée
    periodicite = models.CharField(max_length=10, choices=PERIODICITE_CHOICES, null=True, blank=True)
    date_derniere_relance = models.DateField(null=True, blank=True)  # anti-doublon rappels d'expiration

    def __str__(self):
        return f"Abonnement {self.statut}/{self.plan} - {self.bailleur}"

    # — Dates —
    @property
    def date_fin_effective(self):
        """Date jusqu'à laquelle l'accès est valable selon le statut courant."""
        if self.statut == 'essai':
            return self.date_fin_essai
        if self.statut == 'actif':
            return self.date_fin
        if self.statut == 'grace' and self.date_fin:
            return self.date_fin + timedelta(days=constants.DUREE_GRACE_JOURS)
        return None

    @property
    def jours_restants(self):
        fin = self.date_fin_effective
        if not fin:
            return 0
        return max((fin.date() - timezone.now().date()).days, 0)

    # — Droits —
    @property
    def est_actif(self):
        fin = self.date_fin_effective
        return bool(fin and timezone.now() <= fin)

    @property
    def droits(self):
        """Plan effectif si l'accès est valide (Pro durant l'essai), sinon None."""
        if not self.est_actif:
            return None
        return constants.PLAN_PRO if self.statut == 'essai' else self.plan

    def a_droit(self, feature):
        d = self.droits
        if d is None:
            return False
        if d == constants.PLAN_PRO:
            return True
        return feature not in constants.FEATURES_PRO

    @property
    def max_biens(self):
        d = self.droits
        if d is None:
            return 0
        return constants.PLANS[d]['max_biens']  # None = illimité


class TransactionAbonnement(models.Model):
    """Trace d'un paiement d'abonnement (web). Sert d'audit + d'idempotence.

    Le prestataire est branché via abonnements/providers/* ; en dev on utilise
    FakeProvider. L'activation effective se fait dans services.activer_depuis_transaction.
    """
    STATUT_CHOICES = (
        ('en_attente', 'En attente'),
        ('reussi', 'Réussi'),
        ('echoue', 'Échoué'),
        ('annule', 'Annulé'),
    )

    bailleur = models.ForeignKey(
        settings.AUTH_USER_MODEL, on_delete=models.CASCADE, related_name='transactions_abonnement'
    )
    plan = models.CharField(max_length=12, choices=Abonnement.PLAN_CHOICES)
    periodicite = models.CharField(max_length=10, choices=Abonnement.PERIODICITE_CHOICES)
    montant = models.DecimalField(max_digits=10, decimal_places=2)
    devise = models.CharField(max_length=8, default='XAF')
    statut = models.CharField(max_length=12, choices=STATUT_CHOICES, default='en_attente')
    prestataire = models.CharField(max_length=20, default='fake')
    reference_interne = models.UUIDField(default=uuid.uuid4, unique=True, editable=False)
    reference_externe = models.CharField(max_length=128, blank=True, null=True, db_index=True)
    payload = models.JSONField(default=dict, blank=True)
    date_creation = models.DateTimeField(auto_now_add=True)
    date_paiement = models.DateTimeField(null=True, blank=True)

    class Meta:
        ordering = ['-date_creation']

    def __str__(self):
        return f"Tx {self.statut} {self.montant} {self.devise} - {self.bailleur}"


class JetonAccesBailleur(models.Model):
    """Magic-link à usage unique (≤ 10 min) ouvrant l'espace web d'abonnement.

    Émis par l'app (le bailleur est déjà authentifié en JWT), consommé par la vue
    web qui ouvre une session Django. Invalidé dès la première utilisation.
    """
    DUREE_MINUTES = 10

    bailleur = models.ForeignKey(
        settings.AUTH_USER_MODEL, on_delete=models.CASCADE, related_name='jetons_abonnement'
    )
    token = models.CharField(max_length=64, unique=True, default=_token, db_index=True)
    date_creation = models.DateTimeField(auto_now_add=True)
    utilise = models.BooleanField(default=False)

    def __str__(self):
        return f"Jeton {'utilisé' if self.utilise else 'actif'} - {self.bailleur}"

    @property
    def est_valide(self):
        return (not self.utilise) and self.date_creation > timezone.now() - timedelta(minutes=self.DUREE_MINUTES)

    def consommer(self):
        self.utilise = True
        self.save(update_fields=['utilise'])

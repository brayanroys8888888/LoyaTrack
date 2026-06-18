"""Logique métier des abonnements : création d'essai, activation, expiration, gating.

Toutes les vérifications de droits passent par ici ou par permissions.py, de sorte
que l'API ET les tâches Celery appliquent les mêmes règles (jamais l'UI seule).
"""
from datetime import timedelta

from django.utils import timezone

from . import constants
from .models import Abonnement, TransactionAbonnement, ajouter_mois_dt


def assurer_abonnement(bailleur):
    """Renvoie l'abonnement du bailleur, en créant un essai 14 j au besoin."""
    ab = getattr(bailleur, 'abonnement', None)
    if ab is not None:
        return ab
    return creer_essai(bailleur)


def creer_essai(bailleur):
    """Crée un abonnement d'essai (Pro débloqué) de 14 jours."""
    return Abonnement.objects.create(
        bailleur=bailleur,
        plan=constants.PLAN_PRO,
        statut='essai',
        date_fin_essai=timezone.now() + timedelta(days=constants.DUREE_ESSAI_JOURS),
    )


def octroyer_pro_courtoisie(bailleur, jours=constants.DUREE_COURTOISIE_JOURS):
    """Pro de courtoisie (bailleurs existants à la bascule payante)."""
    ab = assurer_abonnement(bailleur)
    ab.plan = constants.PLAN_PRO
    ab.statut = 'actif'
    ab.date_fin = timezone.now() + timedelta(days=jours)
    ab.save()
    return ab


def activer_abonnement(bailleur, plan, periodicite):
    """Active/prolonge un abonnement payé. Idempotent au niveau période :
    on prolonge depuis max(maintenant, date_fin actuelle)."""
    if plan not in constants.PLANS:
        raise ValueError(f"Plan inconnu : {plan}")
    if periodicite not in constants.PERIODICITES:
        raise ValueError(f"Périodicité inconnue : {periodicite}")
    ab = assurer_abonnement(bailleur)
    now = timezone.now()
    base = ab.date_fin if (ab.date_fin and ab.date_fin > now) else now
    ab.plan = plan
    ab.periodicite = periodicite
    ab.statut = 'actif'
    ab.date_fin = ajouter_mois_dt(base, 12 if periodicite == 'annuel' else 1)
    ab.save()
    return ab


def creer_transaction(bailleur, plan, periodicite, prestataire='fake'):
    return TransactionAbonnement.objects.create(
        bailleur=bailleur,
        plan=plan,
        periodicite=periodicite,
        montant=constants.prix(plan, periodicite),
        statut='en_attente',
        prestataire=prestataire,
    )


def activer_depuis_transaction(transaction, reference_externe=None, payload=None):
    """Active l'abonnement à partir d'une transaction réussie. **Idempotent** :
    rejouer un webhook déjà traité ne prolonge pas la période une 2ᵉ fois."""
    if transaction.statut == 'reussi':
        return transaction  # déjà traité
    transaction.statut = 'reussi'
    transaction.date_paiement = timezone.now()
    if reference_externe:
        transaction.reference_externe = reference_externe
    if payload is not None:
        transaction.payload = payload
    transaction.save()
    activer_abonnement(transaction.bailleur, transaction.plan, transaction.periodicite)
    return transaction


# ─── Gating fonctionnel (Pro) ────────────────────────────────────────────────
def exiger_pro(bailleur, feature):
    """Lève FonctionPro si le bailleur n'a pas droit à `feature` (plan/essai/expiration)."""
    from .permissions import FonctionPro  # import local pour éviter les cycles
    ab = assurer_abonnement(bailleur)
    if not ab.a_droit(feature):
        raise FonctionPro()


def peut_creer_bien(bailleur, nb_biens_actuels):
    ab = assurer_abonnement(bailleur)
    mx = ab.max_biens
    return mx is None or nb_biens_actuels < mx


# ─── Expiration (Celery) ─────────────────────────────────────────────────────
def expirer_abonnements(now=None):
    """Fait transiter les abonnements dont la date est passée. Renvoie un compte.

    - essai dépassé → 'expire' (pas de grâce sur l'essai).
    - actif dépassé → 'grace' (3 j de tolérance).
    - grace dépassée (date_fin + 3 j) → 'expire'.
    """
    now = now or timezone.now()
    n_expire = n_grace = 0

    for ab in Abonnement.objects.filter(statut='essai', date_fin_essai__lt=now):
        ab.statut = 'expire'
        ab.save(update_fields=['statut'])
        n_expire += 1

    for ab in Abonnement.objects.filter(statut='actif', date_fin__lt=now):
        ab.statut = 'grace'
        ab.save(update_fields=['statut'])
        n_grace += 1

    limite_grace = now - timedelta(days=constants.DUREE_GRACE_JOURS)
    for ab in Abonnement.objects.filter(statut='grace', date_fin__lt=limite_grace):
        ab.statut = 'expire'
        ab.save(update_fields=['statut'])
        n_expire += 1

    return {'expire': n_expire, 'grace': n_grace}

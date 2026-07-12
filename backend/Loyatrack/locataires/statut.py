"""Recalcul minimal du statut d'un locataire (patch autonome).

Corrige l'incohérence « statut Payé alors que l'échéance est dépassée sans
paiement ». Se limite à basculer entre 'Payé' et 'En retard' ; ne rétrograde
jamais 'En discussion' / 'En pénalité' (arrangements en cours). Recalculé à la
lecture (dashboard, liste, détail) pour ne pas dépendre de Celery.

NB : la version complète (statut 'Nouveau', ancrage 1er paiement, tâche beat)
vit sur la branche `fix/encaissement-momo-corrections` ; ce module est un
correctif ciblé pour la branche courante, à réconcilier lors du merge.
"""
import calendar
from datetime import date

from django.db.models import Sum
from django.utils import timezone


def _fin_de_mois(d):
    return date(d.year, d.month, calendar.monthrange(d.year, d.month)[1])


def _mois_courant_couvert(locataire, aujourd_hui):
    """Le mois courant est-il couvert : par un paiement (chevauchement de
    période) ou, à défaut, par le cumulé versé ce mois-ci ?"""
    debut = aujourd_hui.replace(day=1)
    fin = _fin_de_mois(debut)
    if locataire.paiements.filter(
        periode_debut__isnull=False, periode_debut__lte=fin, periode_fin__gte=debut
    ).exists():
        return True
    paye = locataire.paiements.filter(
        date_paiement__year=debut.year, date_paiement__month=debut.month
    ).aggregate(s=Sum('montant'))['s'] or 0
    return bool(locataire.montant_loyer) and paye >= locataire.montant_loyer


def recalculer_statut(locataire, aujourd_hui=None, persister=True):
    """Met le statut en cohérence avec les paiements et l'échéance du mois."""
    aujourd_hui = aujourd_hui or timezone.localdate()
    if locataire.statut in ('En discussion', 'En pénalité'):
        return locataire.statut  # arrangement en cours : on ne touche pas

    if _mois_courant_couvert(locataire, aujourd_hui):
        nouveau = 'Payé'
    else:
        debut_fact = locataire.date_debut_facturation or locataire.date_entree
        jour = min(locataire.jour_echeance or 1, _fin_de_mois(aujourd_hui).day)
        echeance = aujourd_hui.replace(day=jour)
        apres_debut = (debut_fact is None) or (debut_fact <= aujourd_hui)
        # Passé l'échéance et non payé → En retard ; avant l'échéance → inchangé.
        nouveau = 'En retard' if (aujourd_hui > echeance and apres_debut) else locataire.statut

    if persister and nouveau != locataire.statut:
        locataire.statut = nouveau
        locataire.save(update_fields=['statut'])
    return nouveau


def recalculer_statuts_bailleur(bailleur, aujourd_hui=None):
    """Recalcule le statut de tous les locataires actifs d'un bailleur."""
    aujourd_hui = aujourd_hui or timezone.localdate()
    for loc in bailleur.locataires.filter(is_deleted=False, archive=False):
        recalculer_statut(loc, aujourd_hui)

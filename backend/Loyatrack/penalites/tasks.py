import logging

from celery import shared_task
from django.utils import timezone

from locataires.models import Locataire
from .services import appliquer_penalite_locataire

logger = logging.getLogger(__name__)


@shared_task
def calculer_penalites():
    """Calcule/actualise les pénalités de retard pour tous les locataires non payés.

    Idempotent : le total de chaque pénalité est recalculé à partir du nombre de
    jours de retard, donc relancer la tâche ne crée pas de double comptage.
    """
    from abonnements.services import assurer_abonnement

    aujourd_hui = timezone.now().date()
    # « En discussion » gèle les pénalités (arrangement/négociation en cours).
    locataires = Locataire.objects.filter(is_deleted=False).exclude(
        statut__in=['Payé', 'En discussion']
    ).select_related('bailleur')

    for locataire in locataires:
        try:
            # Pénalités automatiques = fonction Pro : on saute les bailleurs sans ce droit.
            if not assurer_abonnement(locataire.bailleur).a_droit('penalites_auto'):
                continue
            appliquer_penalite_locataire(locataire, aujourd_hui)
        except Exception as e:
            logger.error(f"Erreur calcul pénalité pour {locataire}: {e}")

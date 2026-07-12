from celery import shared_task
from django.utils import timezone


@shared_task
def expirer_annonces():
    """Passe à 'expiree' les annonces publiées dont la date d'expiration est dépassée.

    Beat quotidien (voir CELERY_BEAT_SCHEDULE). Renvoie le nombre d'annonces expirées.
    """
    from .models import Annonce
    return Annonce.objects.filter(
        statut='publiee', date_expiration__lt=timezone.now()
    ).update(statut='expiree')

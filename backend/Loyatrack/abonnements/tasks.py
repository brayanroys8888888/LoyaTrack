import logging

from celery import shared_task
from django.utils import timezone

from . import services
from .models import Abonnement

logger = logging.getLogger(__name__)


@shared_task
def expirer_abonnements():
    """Fait transiter essais/abos arrivés à terme (→ grâce → expiré). Quotidien."""
    res = services.expirer_abonnements()
    logger.info(f"Abonnements : {res['grace']} passés en grâce, {res['expire']} expirés.")
    return res


@shared_task
def rappels_expiration():
    """Prévient le bailleur quand son accès approche de la fin.

    - essai / actif : à J-3, J-1, J0.
    - grâce : chaque jour (J0/J+1/J+2 de la tolérance).
    Throttle : une notification par jour max (date_derniere_relance).
    """
    from locataires.models import Notification

    today = timezone.now().date()
    envoyes = 0
    qs = Abonnement.objects.filter(statut__in=['essai', 'actif', 'grace']).select_related('bailleur')

    for ab in qs:
        if ab.date_derniere_relance == today:
            continue
        jr = ab.jours_restants
        a_prevenir = ab.statut == 'grace' or jr in (3, 1, 0)
        if not a_prevenir:
            continue

        if ab.statut == 'essai':
            titre = "Votre essai se termine bientôt"
            corps = (f"Il vous reste {jr} jour(s) d'essai. Abonnez-vous pour continuer "
                     f"à gérer vos locataires sans interruption.")
        elif ab.statut == 'grace':
            titre = "Paiement en attente"
            corps = ("Votre abonnement a expiré. Vous bénéficiez d'un court délai de grâce : "
                     "renouvelez maintenant pour éviter la coupure d'accès.")
        else:  # actif
            titre = "Votre abonnement arrive à échéance"
            corps = f"Votre abonnement se termine dans {jr} jour(s). Pensez à le renouveler."

        Notification.objects.create(
            bailleur=ab.bailleur, locataire=None, titre=titre, corps=corps, type_notif='systeme',
        )
        ab.date_derniere_relance = today
        ab.save(update_fields=['date_derniere_relance'])
        envoyes += 1

        try:
            from Loyatrack.utils.firebase import send_push_notification
            if ab.bailleur.fcm_token:
                send_push_notification(token=ab.bailleur.fcm_token, title=titre, body=corps,
                                       data={'type': 'abonnement'})
        except Exception as e:
            logger.error(f"Push rappel abonnement: {e}")

    logger.info(f"Rappels d'expiration envoyés : {envoyes}")
    return envoyes

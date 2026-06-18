from celery import shared_task
from django.utils import timezone
from .models import Locataire, Rappel, Notification
from .services import execute_rappel
from datetime import timedelta
import logging

logger = logging.getLogger(__name__)


# Canal de rappel préféré (ConfigBailleur) -> type de Rappel
_CANAL_TO_TYPE = {'sms': 'SMS', 'whatsapp': 'WhatsApp', 'appel': 'Appel'}


@shared_task
def verifier_echeances():
    from penalites.models import echeance_du_mois
    from accounts.models import ConfigBailleur
    aujourd_hui = timezone.now().date()
    locataires = (Locataire.objects.filter(is_deleted=False, archive=False)
                  .exclude(statut='Payé').select_related('bailleur'))

    from abonnements.services import assurer_abonnement

    for locataire in locataires:
        try:
            # Rappels automatiques = fonction Pro : on saute les bailleurs sans ce droit
            # (Essentiel ou abonnement expiré) pour ne pas engager de coûts Twilio.
            if not assurer_abonnement(locataire.bailleur).a_droit('rappels_auto'):
                continue
            config = ConfigBailleur.pour(locataire.bailleur)
            if not config.rappels_automatiques_actifs:
                continue
            jours = config.jours_avant_rappel or 3
            type_rappel = _CANAL_TO_TYPE.get(config.canal_rappel_prefere, 'SMS')

            # Échéance de ce mois et du mois prochain (gère les mois courts)
            echeances = [
                echeance_du_mois(aujourd_hui.year, aujourd_hui.month, locataire.jour_echeance),
            ]
            nxt = (aujourd_hui.replace(day=1) + timedelta(days=32)).replace(day=1)
            echeances.append(echeance_du_mois(nxt.year, nxt.month, locataire.jour_echeance))

            # Rappel préventif J-(jours_avant_rappel) via le canal préféré du bailleur
            if any(e == aujourd_hui + timedelta(days=jours) for e in echeances):
                rappel = Rappel.objects.create(locataire=locataire, type_rappel=type_rappel, statut='En attente')
                execute_rappel(rappel, contexte='avant', jours=jours)
            # Appel vocal la veille (J-1), sauf si le rappel préventif tombe déjà la veille
            elif jours != 1 and any(e == aujourd_hui + timedelta(days=1) for e in echeances):
                rappel = Rappel.objects.create(locataire=locataire, type_rappel='Appel', statut='En attente')
                execute_rappel(rappel, contexte='avant', jours=1)
        except Exception as e:
            logger.error(f"Erreur vérification échéance pour {locataire}: {str(e)}")


@shared_task
def appliquer_augmentations():
    """Applique les révisions de loyer programmées dont la date est arrivée (3.3)."""
    from .gestion import appliquer_augmentations_dues
    nb = appliquer_augmentations_dues()
    logger.info(f"{nb} augmentation(s) de loyer appliquée(s)")
    return nb


@shared_task
def alerter_fin_bail():
    """Alerte le bailleur 2 mois (M-2) avant l'expiration d'un bail (2.7)."""
    aujourd_hui = timezone.now().date()
    cible = aujourd_hui + timedelta(days=60)
    locataires = Locataire.objects.filter(is_deleted=False, archive=False, date_fin_bail=cible)
    for loc in locataires:
        Notification.objects.create(
            locataire=loc, bailleur=loc.bailleur,
            titre="Fin de bail proche",
            corps=f"Le bail de {loc.prenom} {loc.nom} expire le {loc.date_fin_bail} (dans 2 mois).",
            type_notif='systeme',
        )
    return locataires.count()

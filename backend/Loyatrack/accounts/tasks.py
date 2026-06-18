import logging

from celery import shared_task
from django.core.management import call_command

logger = logging.getLogger(__name__)


@shared_task
def sauvegarder_donnees():
    """Sauvegarde quotidienne des données (2.5)."""
    try:
        call_command('backup_data')
        return True
    except Exception as e:
        logger.error(f"Échec de la sauvegarde : {e}")
        return False

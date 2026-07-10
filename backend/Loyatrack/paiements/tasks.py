import logging

from celery import shared_task

logger = logging.getLogger(__name__)


@shared_task
def relancer_reversements():
    """Relance les reversements de loyer bloqués (échec réseau, worker tué…).

    Cible les demandes déjà encaissées (`statut='payee'`) dont le loyer n'est
    pas encore parvenu au bailleur (`reversement_statut` ∈ {en_attente, echoue}).
    Les demandes 'non_requis' (bailleur sans compte de reversement) sont
    volontairement exclues. `_reverser_loyer` étant idempotent, relancer la
    tâche ne provoque pas de double transfert.
    """
    from .models import DemandePaiement
    from .services import _reverser_loyer

    demandes = DemandePaiement.objects.filter(
        statut='payee', paiement__isnull=False,
        reversement_statut__in=['en_attente', 'echoue'],
    ).select_related('locataire__bailleur')

    for demande in demandes:
        try:
            _reverser_loyer(demande)
        except Exception as e:  # une demande en échec ne doit pas bloquer les autres
            logger.error(f"Relance reversement échouée pour {demande}: {e}")

import logging
from datetime import date, timedelta
from decimal import Decimal

from django.db.models import Sum
from django.utils import timezone

from locataires.models import Locataire, Notification
from .models import Penalite, echeance_du_mois

logger = logging.getLogger(__name__)


def recalculer_total_penalites(locataire):
    """Recalcule total_penalites du locataire à partir de ses pénalités actives (net de remise)."""
    actives = locataire.penalites.filter(statut='Active')
    total = sum((p.montant_net for p in actives), Decimal('0'))
    locataire.total_penalites = total
    locataire.save(update_fields=['total_penalites'])
    return total


def appliquer_penalite_locataire(locataire, aujourd_hui=None):
    """
    Applique/actualise la pénalité du mois courant pour un locataire, de façon idempotente.

    - Comparaison par date absolue (échéance du mois + délai de grâce).
    - Le total est recalculé (jours de retard * montant journalier), donc relancer la
      tâche plusieurs fois le même jour ne double pas les pénalités.
    - Une seule pénalité par (locataire, période/mois).
    """
    aujourd_hui = aujourd_hui or timezone.now().date()
    # « En discussion » = arrangement en cours : on gèle les pénalités (aucune
    # nouvelle, et les existantes ne sont pas réincrémentées). Garde-fou ici aussi
    # pour les appels directs / forcer_automatisations.
    if locataire.statut == 'En discussion':
        return None
    config = getattr(locataire, 'config_penalite', None)
    if config and not config.actif:
        return None

    echeance = echeance_du_mois(aujourd_hui.year, aujourd_hui.month, locataire.jour_echeance)
    delai_grace = config.delai_grace if config else 0
    date_limite = echeance + timedelta(days=delai_grace)

    if aujourd_hui <= date_limite:
        return None  # Pas encore en retard (grâce incluse)

    montant_journalier = config.montant_journalier() if config else locataire.get_penalite_journaliere
    date_debut = date_limite + timedelta(days=1)
    jours_retard = (aujourd_hui - date_debut).days + 1
    if jours_retard < 1:
        return None

    periode = date(aujourd_hui.year, aujourd_hui.month, 1)
    penalite, _created = Penalite.objects.get_or_create(
        locataire=locataire,
        periode=periode,
        defaults={
            'date_debut': date_debut,
            'montant_journalier': montant_journalier,
            'statut': 'Active',
        },
    )
    if penalite.statut != 'Active':
        return penalite  # Déjà clôturée (payée) ou remise pour cette période

    # Anti-doublon : déjà appliqué aujourd'hui -> rien à faire
    if penalite.date_derniere_application == aujourd_hui:
        return penalite

    penalite.montant_journalier = montant_journalier
    penalite.total = (montant_journalier * jours_retard).quantize(Decimal('0.01'))
    penalite.date_derniere_application = aujourd_hui
    penalite.save()

    if locataire.statut != 'En pénalité':
        locataire.statut = 'En pénalité'
        locataire.save(update_fields=['statut'])

    recalculer_total_penalites(locataire)

    notif = Notification.objects.create(
        locataire=locataire,
        bailleur=locataire.bailleur,
        titre="Pénalité de retard",
        corps=(
            f"{locataire.prenom} {locataire.nom} : {jours_retard} jour(s) de retard. "
            f"Pénalité cumulée : {penalite.montant_net} FCFA."
        ),
        type_notif='penalite',
    )
    try:
        from Loyatrack.utils.firebase import send_push_notification
        if locataire.bailleur.fcm_token:
            send_push_notification(
                token=locataire.bailleur.fcm_token,
                title=notif.titre,
                body=notif.corps,
                data={'type': 'penalite', 'locataire_id': str(locataire.pk)},
            )
    except Exception as e:
        logger.error(f"Erreur push notification (pénalité): {e}")

    return penalite


def remettre_penalite(penalite, motif, montant=None):
    """Accorde une remise (annulation totale ou partielle) sur une pénalité.

    motif est obligatoire. Si montant est None, remise totale.
    """
    if not motif or not motif.strip():
        raise ValueError("Le motif de remise est obligatoire.")

    montant_remise = penalite.total if montant is None else min(Decimal(str(montant)), penalite.total)
    penalite.montant_remise = montant_remise
    penalite.motif_remise = motif.strip()
    penalite.date_remise = timezone.now()
    if penalite.montant_net <= 0:
        penalite.statut = 'Remise'
        penalite.date_fin = timezone.now().date()
    penalite.save()

    recalculer_total_penalites(penalite.locataire)
    return penalite

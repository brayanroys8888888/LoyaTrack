"""Logique métier de gestion locative : augmentation de loyer, caution, résiliation."""
from datetime import date as _date, datetime
from decimal import Decimal

from django.utils import timezone

from .models import HistoriqueLoyer, MouvementCaution, Notification


def _coerce_date(valeur):
    """Accepte une date ou une chaîne ISO/française et renvoie un objet date."""
    if isinstance(valeur, _date):
        return valeur
    valeur = str(valeur).strip()
    for fmt in ('%Y-%m-%d', '%d/%m/%Y', '%d-%m-%Y'):
        try:
            return datetime.strptime(valeur, fmt).date()
        except ValueError:
            continue
    raise ValueError(f"date invalide: {valeur}")


# ---------------------------------------------------------------- Augmentation
def programmer_augmentation(locataire, montant, date_debut, motif=''):
    """Crée une révision de loyer. Appliquée immédiatement si la date est passée/aujourd'hui."""
    montant = Decimal(str(montant))
    date_debut = _coerce_date(date_debut)
    hist = HistoriqueLoyer.objects.create(
        locataire=locataire, montant=montant, date_debut=date_debut, motif=motif,
    )
    if date_debut <= timezone.now().date():
        appliquer_revision(hist)
    return hist


def appliquer_revision(hist):
    """Applique une révision : clôt la précédente et met à jour le loyer du locataire."""
    locataire = hist.locataire
    # Clôture des révisions actives antérieures
    HistoriqueLoyer.objects.filter(
        locataire=locataire, applique=True, date_fin__isnull=True
    ).exclude(pk=hist.pk).update(date_fin=hist.date_debut)
    locataire.montant_loyer = hist.montant
    locataire.save(update_fields=['montant_loyer'])
    hist.applique = True
    hist.save(update_fields=['applique'])
    return hist


def appliquer_augmentations_dues(aujourd_hui=None):
    """Tâche : applique toutes les révisions programmées dont la date est arrivée."""
    aujourd_hui = aujourd_hui or timezone.now().date()
    en_attente = HistoriqueLoyer.objects.filter(applique=False, date_debut__lte=aujourd_hui)
    for hist in en_attente:
        appliquer_revision(hist)
    return en_attente.count()


# -------------------------------------------------------------------- Caution
def verser_caution(locataire, montant, date, motif=''):
    montant = Decimal(str(montant))
    date = _coerce_date(date)
    mvt = MouvementCaution.objects.create(
        locataire=locataire, type_mouvement='versement', montant=montant, date=date, motif=motif,
    )
    locataire.montant_caution = montant
    locataire.date_versement_caution = date
    locataire.statut_caution = 'versee'
    locataire.save(update_fields=['montant_caution', 'date_versement_caution', 'statut_caution'])
    return mvt


def restituer_caution(locataire, montant, date, motif='', deductions=None):
    """Restitue la caution (totale/partielle). `deductions` = liste de dicts {montant, motif}."""
    montant = Decimal(str(montant))
    date = _coerce_date(date)
    deductions = deductions or []
    for d in deductions:
        MouvementCaution.objects.create(
            locataire=locataire, type_mouvement='deduction',
            montant=Decimal(str(d.get('montant', 0))), date=date, motif=d.get('motif', ''),
        )
    if montant > 0:
        MouvementCaution.objects.create(
            locataire=locataire, type_mouvement='restitution', montant=montant, date=date, motif=motif,
        )
    total_deduit = sum((Decimal(str(d.get('montant', 0))) for d in deductions), Decimal('0'))
    if montant >= locataire.montant_caution:
        locataire.statut_caution = 'restituee_totale'
    elif total_deduit >= locataire.montant_caution:
        locataire.statut_caution = 'conservee'
    else:
        locataire.statut_caution = 'restituee_partielle'
    locataire.save(update_fields=['statut_caution'])
    return locataire


# ------------------------------------------------------------------ Résiliation
def resilier_locataire(locataire, date_sortie, motif=''):
    """Clôture le bail : archive le locataire, libère l'unité, calcule le solde dû."""
    date_sortie = _coerce_date(date_sortie)
    locataire.archive = True
    locataire.date_sortie = date_sortie
    locataire.motif_sortie = motif
    locataire.save(update_fields=['archive', 'date_sortie', 'motif_sortie'])

    unite = locataire.unite
    if unite:
        locataire.unite = None
        locataire.save(update_fields=['unite'])
        unite.synchroniser_statut()

    solde_du = locataire.total_penalites
    Notification.objects.create(
        locataire=locataire, bailleur=locataire.bailleur,
        titre='Bail résilié',
        corps=f"Le bail de {locataire.prenom} {locataire.nom} a été clôturé le {date_sortie}. "
              f"Solde dû : {solde_du} FCFA.",
        type_notif='systeme',
    )
    return {'solde_du': solde_du}

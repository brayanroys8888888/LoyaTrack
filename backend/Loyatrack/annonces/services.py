"""Logique métier de la vitrine d'annonces — Palier 1, étape 2.

- `nettoyer_telephones` : masque les numéros dans un texte (anti-contournement /
  anti-arnaque : force le contact tracé dans l'app plutôt que hors plateforme).
- `publier` / `renouveler` / `depublier` : cycle de vie avec auto-checks.
Voir LOYATRACK_MARKETPLACE_PLAN.md §9.2.
"""
import re
from datetime import timedelta
from decimal import Decimal

from django.core.exceptions import ValidationError
from django.utils import timezone

# Durée de validité d'une annonce publiée (renouvelable en 1 tap).
DUREE_ANNONCE_JOURS = 45
# Garde-fou anti-typo sur le loyer (FCFA) : au-delà, saisie probablement erronée.
LOYER_PLAFOND = Decimal('100000000')

# Numéro camerounais : « +237 » optionnel puis 9 chiffres (mobile 6.., fixe 2..),
# séparateurs espace/point/tiret tolérés. On masque pour couper les arrangements
# hors-plateforme (arnaques) et forcer la messagerie interne (Palier 3).
_TEL_RE = re.compile(r'(?:\+?237[\s.\-]?)?(?:6\d{2}|2\d{2})(?:[\s.\-]?\d{2}){3}')
_MASQUE = '[numéro masqué]'


def nettoyer_telephones(texte):
    """Remplace toute séquence ressemblant à un numéro camerounais par un masque."""
    if not texte:
        return texte
    return _TEL_RE.sub(_MASQUE, texte)


def publier(annonce):
    """Applique les auto-checks puis publie l'annonce pour `DUREE_ANNONCE_JOURS`.

    Nettoie d'abord la description de ses numéros. Lève `ValidationError` avec la
    liste des manques si l'annonce n'est pas publiable. Renvoie l'annonce publiée.
    """
    # La description est nettoyée avant validation (le masque ne doit pas faire
    # échouer le test « description non vide »).
    annonce.description = nettoyer_telephones(annonce.description or '')

    problemes = []
    if annonce.statut not in ('brouillon', 'expiree', 'pourvue'):
        problemes.append("L'annonce n'est pas dans un état publiable.")
    if not annonce.photos.exists():
        problemes.append("Ajoutez au moins une photo.")
    if annonce.loyer is None or annonce.loyer <= 0:
        problemes.append("Indiquez un loyer supérieur à 0.")
    elif annonce.loyer > LOYER_PLAFOND:
        problemes.append("Le loyer semble erroné (trop élevé).")
    if not annonce.ville_id:
        problemes.append("Sélectionnez une ville.")
    if not annonce.description.strip():
        problemes.append("Ajoutez une description.")
    if problemes:
        raise ValidationError(problemes)

    maintenant = timezone.now()
    # À la 1re publication seulement, on (re)calcule le slug pour qu'il reflète la
    # localisation finale (un brouillon a pu être créé sans ville/quartier). Les
    # renouvellements ultérieurs le conservent → l'URL publique reste stable.
    if annonce.date_publication is None:
        annonce.slug = annonce._nouveau_slug()
        annonce.date_publication = maintenant
    annonce.statut = 'publiee'
    annonce.date_expiration = maintenant + timedelta(days=DUREE_ANNONCE_JOURS)
    annonce.refus_motif = ''
    annonce.save()
    return annonce


def renouveler(annonce):
    """Prolonge (ou republie) une annonce publiée ou expirée de `DUREE_ANNONCE_JOURS`."""
    if annonce.statut not in ('publiee', 'expiree'):
        raise ValidationError("Seule une annonce publiée ou expirée peut être renouvelée.")
    maintenant = timezone.now()
    annonce.statut = 'publiee'
    if not annonce.date_publication:
        annonce.date_publication = maintenant
    annonce.date_expiration = maintenant + timedelta(days=DUREE_ANNONCE_JOURS)
    annonce.save()
    return annonce


def depublier(annonce, pourvue=False):
    """Retire l'annonce du public : `pourvue` (logement trouvé) sinon `brouillon`."""
    annonce.statut = 'pourvue' if pourvue else 'brouillon'
    annonce.save()
    return annonce

"""Génération et envoi de codes OTP (2FA + reset mot de passe).

- Code à 6 chiffres, jamais stocké en clair (haché SHA-256 dans CodeVerification).
- Expiration 5 min, 3 tentatives max.
- Anti-spam : 1 SMS par minute et par utilisateur/type.
- Fallback dev : si DEBUG, le code est renvoyé dans la réponse (`dev_code`) et logué,
  car le compte Twilio d'essai n'envoie qu'aux numéros vérifiés.
"""
import logging
import secrets
from datetime import timedelta

from django.conf import settings
from django.utils import timezone

from .models import CodeVerification

logger = logging.getLogger(__name__)

DUREE_VALIDITE = timedelta(minutes=5)
DELAI_ANTISPAM = timedelta(seconds=60)


class OtpError(Exception):
    """Erreur fonctionnelle OTP (ex: pas de téléphone, envoi trop fréquent)."""


def generer_code() -> str:
    return f"{secrets.randbelow(1_000_000):06d}"


def envoyer_otp(user, type_code: str) -> dict:
    """Crée un CodeVerification et envoie le code par SMS. Renvoie un dict d'infos
    additionnelles pour la réponse API (inclut `dev_code` en DEBUG)."""
    if not user.telephone:
        raise OtpError("Aucun numéro de téléphone associé à ce compte.")

    recent = CodeVerification.objects.filter(
        user=user, type_code=type_code,
        created_at__gt=timezone.now() - DELAI_ANTISPAM,
    ).exists()
    if recent:
        raise OtpError("Un code a déjà été envoyé récemment. Réessayez dans une minute.")

    code = generer_code()
    CodeVerification.objects.create(
        user=user,
        code_hash=CodeVerification.hacher(code),
        type_code=type_code,
        expire_at=timezone.now() + DUREE_VALIDITE,
    )

    libelle = "connexion" if type_code == '2fa' else "réinitialisation de mot de passe"
    message = f"Loyatrack : votre code de {libelle} est {code}. Il expire dans 5 minutes."
    try:
        from locataires.services import send_twilio_message
        send_twilio_message(user.telephone, message, 'SMS')
    except Exception as e:
        logger.error(f"Échec envoi OTP SMS: {e}")

    extra = {}
    if settings.DEBUG:
        logger.warning(f"[DEV OTP] {type_code} pour {user.telephone}: {code}")
        extra['dev_code'] = code  # uniquement en DEBUG, pour les tests
    return extra


def verifier_otp(user, type_code: str, code: str) -> bool:
    """Vérifie le dernier code actif de l'utilisateur pour ce type.
    Marque le code utilisé en cas de succès."""
    cv = CodeVerification.objects.filter(
        user=user, type_code=type_code, utilise=False,
    ).order_by('-created_at').first()
    if cv is None:
        return False
    if cv.verifier(code):
        cv.utilise = True
        cv.save(update_fields=['utilise'])
        return True
    return False

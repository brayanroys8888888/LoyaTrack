"""Messagerie chercheur ↔ bailleur — Palier 3.

- OTP téléphone du chercheur (vérification unique, de confiance ensuite).
- Ouverture de conversation + réponses, avec masquage des numéros (anti-arnaque),
  rate-limit, et notifications (in-app + FCM côté bailleur, SMS côté chercheur).
Voir LOYATRACK_MARKETPLACE_PLAN.md §4.
"""
import hashlib
import logging
import secrets
from datetime import timedelta

from django.conf import settings
from django.db import transaction
from django.db.models import F
from django.utils import timezone

from .models import Annonce, Chercheur, Conversation, Message
from .services import nettoyer_telephones

logger = logging.getLogger(__name__)

DUREE_OTP = timedelta(minutes=5)
ANTISPAM_OTP = timedelta(seconds=60)
MAX_CONTACTS_PAR_JOUR = 10
MAX_TENTATIVES_OTP = 3


class MessagerieError(Exception):
    """Erreur fonctionnelle de la messagerie (numéro non vérifié, quota…)."""


def _hacher(code):
    return hashlib.sha256(str(code).encode()).hexdigest()


# ── OTP chercheur ────────────────────────────────────────────────────────────
def envoyer_otp_chercheur(telephone, nom=''):
    """Crée/retrouve le chercheur et lui envoie un code de vérification (SMS).

    Renvoie (chercheur, extra) où `extra` contient `dev_code` en DEBUG.
    Lève MessagerieError si un code a été envoyé il y a moins d'une minute.
    """
    telephone = (telephone or '').strip()
    if not telephone:
        raise MessagerieError("Numéro de téléphone requis.")
    chercheur, _ = Chercheur.objects.get_or_create(telephone=telephone)
    if nom and not chercheur.nom:
        chercheur.nom = nom

    # Anti-spam : un code valide envoyé il y a < 60 s bloque un renvoi.
    if chercheur.otp_expire and chercheur.otp_expire > timezone.now() + DUREE_OTP - ANTISPAM_OTP:
        raise MessagerieError("Un code vient d'être envoyé. Réessayez dans une minute.")

    code = f"{secrets.randbelow(1_000_000):06d}"
    chercheur.otp_hash = _hacher(code)
    chercheur.otp_expire = timezone.now() + DUREE_OTP
    chercheur.otp_tentatives = 0
    chercheur.save()

    message = f"Loyatrack : votre code de contact est {code}. Il expire dans 5 minutes."
    try:
        from locataires.services import send_twilio_message
        send_twilio_message(chercheur.telephone, message, 'SMS')
    except Exception as e:  # l'envoi ne doit pas casser le flux
        logger.error(f"Échec envoi OTP chercheur: {e}")

    extra = {}
    if settings.DEBUG:
        logger.warning(f"[DEV OTP chercheur] {chercheur.telephone}: {code}")
        extra['dev_code'] = code
    return chercheur, extra


def verifier_otp_chercheur(chercheur, code):
    """Vérifie le code ; en cas de succès, marque le numéro comme vérifié."""
    if (not chercheur.otp_hash or not chercheur.otp_expire
            or chercheur.otp_expire < timezone.now()
            or chercheur.otp_tentatives >= MAX_TENTATIVES_OTP):
        return False
    if chercheur.otp_hash == _hacher(code):
        chercheur.verifie_le = timezone.now()
        chercheur.otp_hash = ''
        chercheur.save(update_fields=['verifie_le', 'otp_hash'])
        return True
    chercheur.otp_tentatives += 1
    chercheur.save(update_fields=['otp_tentatives'])
    return False


# ── Conversations ────────────────────────────────────────────────────────────
def demarrer_conversation(annonce, chercheur, corps):
    """Ouvre (ou retrouve) la conversation et poste le 1er message du chercheur."""
    if not chercheur.est_verifie:
        raise MessagerieError("Numéro non vérifié.")
    depuis = timezone.now() - timedelta(days=1)
    if (Conversation.objects.filter(chercheur=chercheur, date_creation__gte=depuis)
            .count() >= MAX_CONTACTS_PAR_JOUR):
        raise MessagerieError("Trop de contacts aujourd'hui. Réessayez demain.")

    with transaction.atomic():
        conv, cree = Conversation.objects.get_or_create(
            annonce=annonce, chercheur=chercheur,
            defaults={'bailleur': annonce.bailleur})
        msg = Message.objects.create(
            conversation=conv, expediteur='chercheur',
            corps=nettoyer_telephones(corps or ''))
        conv.date_dernier_message = timezone.now()
        conv.save(update_fields=['date_dernier_message'])
        if cree:
            Annonce.objects.filter(pk=annonce.pk).update(nb_contacts=F('nb_contacts') + 1)
    _notifier_bailleur(conv, msg)
    return conv


def repondre(conversation, expediteur, corps):
    """Ajoute un message (chercheur ou bailleur) et notifie l'autre partie."""
    if conversation.statut != 'ouverte':
        raise MessagerieError("Cette conversation est fermée.")
    msg = Message.objects.create(
        conversation=conversation, expediteur=expediteur,
        corps=nettoyer_telephones(corps or ''))
    conversation.date_dernier_message = timezone.now()
    conversation.save(update_fields=['date_dernier_message'])
    if expediteur == 'bailleur':
        _notifier_chercheur(conversation, msg)
    else:
        _notifier_bailleur(conversation, msg)
    return msg


# ── Notifications ────────────────────────────────────────────────────────────
def _notifier_bailleur(conv, msg):
    from locataires.models import Notification
    try:
        notif = Notification.objects.create(
            bailleur=conv.bailleur,
            titre=f"Nouveau message — {conv.annonce.titre}",
            corps=f"{conv.chercheur.nom or 'Un intéressé'} : {msg.corps[:120]}",
            type_notif='discussion')
        token = getattr(conv.bailleur, 'fcm_token', '') or ''
        if token:
            from Loyatrack.utils.firebase import send_push_notification
            send_push_notification(
                token=token, title=notif.titre, body=notif.corps,
                data={'type': 'annonce_message', 'conversation_id': str(conv.pk)})
    except Exception as e:
        logger.error(f"Notif bailleur (message annonce): {e}")


def _notifier_chercheur(conv, msg):
    base = getattr(settings, 'SITE_BASE_URL', '') or ''
    lien = f"{base}/logements/messages/{conv.token}/" if base else ""
    texte = f"Loyatrack : réponse du bailleur pour « {conv.annonce.titre} »."
    if lien:
        texte += f" Voir : {lien}"
    try:
        from locataires.services import send_twilio_message
        send_twilio_message(conv.chercheur.telephone, texte, 'SMS')
    except Exception as e:
        logger.error(f"Notif chercheur (réponse bailleur): {e}")

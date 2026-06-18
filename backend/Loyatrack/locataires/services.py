import logging
from django.core.mail import send_mail
from .models import Rappel, Notification

logger = logging.getLogger(__name__)

from twilio.rest import Client
from twilio.twiml.voice_response import VoiceResponse
from django.conf import settings

def send_twilio_message(to, body, type_rappel, langue='fr'):
    """
    Send a message or make a call via Twilio. `langue` ('fr'/'en') pilote la
    langue de synthèse vocale pour les appels.
    """
    logger.info(f"[TWILIO {type_rappel}] to {to}: {body}")
    account_sid = settings.TWILIO_ACCOUNT_SID
    auth_token = settings.TWILIO_AUTH_TOKEN
    twilio_number = settings.TWILIO_NUMBER
    whatsapp_number = settings.TWILIO_WHATSAPP_NUMBER or 'whatsapp:+14155238886'

    # Format the phone number to E.164 format if it doesn't start with '+'
    # Assuming Cameroon (+237) as default for numbers like 69...
    clean_to = to.strip()
    if not clean_to.startswith('+'):
        clean_to = f'+237{clean_to}'

    if type_rappel == 'WhatsApp':
        # Assuming Twilio WhatsApp numbers are prefixed with 'whatsapp:'
        to_number = f'whatsapp:{clean_to}'
        from_number = whatsapp_number
    else:
        to_number = clean_to
        from_number = twilio_number

    try:
        client = Client(account_sid, auth_token)

        if type_rappel == 'Appel':
            # Create a Voice Call using proper TwiML formatting (simplified for trial accounts)
            tts_lang = 'en-US' if langue == 'en' else 'fr-FR'
            response = VoiceResponse()
            response.say(body, voice='alice', language=tts_lang)
            
            call = client.calls.create(
                from_=from_number,
                to=to_number,
                twiml=str(response)
            )
            return {"status": "success", "sid": call.sid, "to": to_number, "type": type_rappel}
        else:
            # Create an SMS or WhatsApp message
            message = client.messages.create(
                from_=from_number,
                body=body,
                to=to_number
            )
            return {"status": "success", "sid": message.sid, "to": to_number, "type": type_rappel}
            
    except Exception as e:
        logger.error(f"Twilio error: {str(e)}")
        return {"status": "failed", "error": str(e), "to": clean_to, "type": type_rappel}

def construire_message(type_rappel, contexte, langue, *, salutation, nom_complet, nom_prononce, jours=None):
    """Construit le texte d'un rappel selon le canal, le contexte, la langue.

    contexte : 'avant' (échéance à venir, avec `jours`), 'retard', ou None (générique).
    Les anciens contextes 'J-5' / 'J-1' restent acceptés (rétro-compat)."""
    if contexte == 'J-5':
        contexte, jours = 'avant', 5
    elif contexte == 'J-1':
        contexte, jours = 'avant', 1

    is_call = type_rappel == 'Appel'
    en = (langue == 'en')

    # Délai exprimé en toutes lettres
    if en:
        delai = "tomorrow" if jours == 1 else f"in {jours} days"
    else:
        delai = "demain" if jours == 1 else f"dans {jours} jours"

    if is_call:
        if en:
            if contexte == 'avant':
                return f"{salutation} {nom_prononce}. This is an automated call from LoyaTrack. Your rent is due {delai}. Without payment, or an agreement with your landlord, penalties may apply. Thank you, and have a great day."
            if contexte == 'retard':
                return f"{salutation} {nom_prononce}. This is an automated call from LoyaTrack. Your rent is currently overdue. Without settlement, penalties will apply. Please contact your landlord, and have a great day."
            return f"{salutation} {nom_prononce}. This is an automated call from LoyaTrack. Your rent is due, or overdue. Without payment, or an agreement with your landlord, penalties may apply. Thank you, and have a great day."
        # FR (la ponctuation aide la synthèse vocale Alice à sonner naturel)
        if contexte == 'avant':
            return f"{salutation} {nom_prononce}. Ceci est un appel automatique, de LoyaTrack. Votre loyer, arrive à échéance {delai}. Sans paiement, ou accord avec le bailleur, des pénalités pourront être appliquées. Merci, et très bonne journée."
        if contexte == 'retard':
            return f"{salutation} {nom_prononce}. Ceci est un appel automatique, de LoyaTrack. Votre loyer, est actuellement en retard de paiement. Sans régularisation, des pénalités vont être appliquées. Merci de contacter votre bailleur, et très bonne journée."
        return f"{salutation} {nom_prononce}. Ceci est un appel automatique, de LoyaTrack. Votre loyer, arrive à échéance, ou est en retard. Sans paiement, ou accord avec le bailleur, des pénalités pourront être appliquées. Merci, et très bonne journée."

    # SMS / WhatsApp
    if en:
        if contexte == 'avant':
            return f"🏠 {salutation} Mr {nom_complet}\n\nYour rent is due {delai}.\n\nPlease make arrangements to avoid penalties.\n\n📞 Contact your landlord if you have any difficulty"
        if contexte == 'retard':
            return f"🏠 {salutation} Mr {nom_complet}\n\nYour rent is currently overdue.\n\nPlease settle the situation immediately to avoid penalties.\n\n📞 Contact your landlord if needed"
        return f"🏠 {salutation} Mr {nom_complet}\n\nYour rent is due or overdue.\n\nPlease make arrangements to avoid penalties.\n\n📞 Contact your landlord if you have any difficulty"
    if contexte == 'avant':
        return f"🏠 {salutation} mr {nom_complet}\n\nVotre loyer arrive à échéance {delai}.\n\nMerci de prendre vos dispositions pour éviter des pénalités.\n\n📞 Contactez le bailleur en cas de difficulté"
    if contexte == 'retard':
        return f"🏠 {salutation} mr {nom_complet}\n\nVotre loyer est actuellement en retard de paiement.\n\nMerci de régulariser la situation immédiatement pour éviter les pénalités.\n\n📞 Contactez le bailleur en cas de difficulté"
    return f"🏠 {salutation} mr {nom_complet}\n\nVotre loyer arrive à échéance ou est en retard.\n\nMerci de prendre vos dispositions pour éviter des pénalités.\n\n📞 Contactez le bailleur en cas de difficulté"


def execute_rappel(rappel: Rappel, contexte=None, jours=None):
    locataire = rappel.locataire
    langue = getattr(locataire, 'langue_preferee', 'fr') or 'fr'
    en = (langue == 'en')

    from django.utils import timezone
    heure_locale = (timezone.now().hour + 1) % 24  # UTC+1 (Cameroun)
    if en:
        salutation = "Good evening" if heure_locale >= 17 else "Good morning"
        nom_prononce = f"Mr or Mrs {locataire.nom.upper()}"
    else:
        salutation = "Bonsoir" if heure_locale >= 17 else "Bonjour"
        nom_prononce = f"Monsieur ou Madame {locataire.nom.upper()}"
    nom_complet = f"{locataire.nom.upper()} {locataire.prenom}".strip()

    message = construire_message(
        rappel.type_rappel, contexte, langue,
        salutation=salutation, nom_complet=nom_complet,
        nom_prononce=nom_prononce, jours=jours,
    )

    if rappel.type_rappel in ['SMS', 'WhatsApp', 'Appel']:
        res = send_twilio_message(locataire.telephone, message, rappel.type_rappel, langue=langue)
        rappel.statut = 'Envoyé' if res.get('status') == 'success' else 'Echoué'
        rappel.reponse_api = res
        rappel.message_sid = res.get('sid', '') or ''
        rappel.statut_livraison = 'queued' if res.get('status') == 'success' else 'failed'
        rappel.save()
        
        if rappel.statut == 'Envoyé':
            notif = Notification.objects.create(
                locataire=locataire,
                bailleur=locataire.bailleur,
                titre=f"Rappel {rappel.type_rappel} envoyé",
                corps=f"Un rappel {rappel.type_rappel} a été envoyé avec succès à {locataire.prenom} {locataire.nom}.",
                type_notif='rappel'
            )
            # Send Firebase Push Notification to the landlord
            try:
                from Loyatrack.utils.firebase import send_push_notification
                bailleur = locataire.bailleur
                if bailleur.fcm_token:
                    send_push_notification(
                        token=bailleur.fcm_token,
                        title=notif.titre,
                        body=notif.corps,
                        data={'type': 'rappel', 'locataire_id': str(locataire.pk)}
                    )
            except Exception as e:
                logger.error(f"Erreur envoi push notification (rappel): {e}")

    # Notification email (mock console). Ne doit JAMAIS faire échouer la requête :
    # le backend console encode en cp1252 sous Windows et plante sur les emojis du SMS.
    if locataire.bailleur.email:
        try:
            send_mail(
                f"Rappel {rappel.type_rappel} pour {locataire.prenom}",
                f"Un {rappel.type_rappel} a ete envoye pour {locataire.prenom} {locataire.nom}.\nStatut: {rappel.statut}",
                'noreply@loyatrack.local',
                [locataire.bailleur.email],
                fail_silently=True,
            )
        except Exception as e:
            logger.error(f"Erreur envoi email mock (rappel): {e}")

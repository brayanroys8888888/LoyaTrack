import os
import logging
from django.conf import settings
import firebase_admin
from firebase_admin import credentials, messaging

logger = logging.getLogger(__name__)

# Initialize Firebase Admin SDK
def initialize_firebase():
    if not firebase_admin._apps:
        # Looking for the key at the root of the Django project
        base_dir = settings.BASE_DIR
        cred_path = os.path.join(base_dir, 'firebase-adminsdk.json')
        
        try:
            if os.path.exists(cred_path):
                cred = credentials.Certificate(cred_path)
                firebase_admin.initialize_app(cred)
                logger.info("Firebase Admin SDK initialized successfully.")
            else:
                logger.warning(f"Firebase credentials not found at {cred_path}")
        except Exception as e:
            logger.error(f"Failed to initialize Firebase Admin SDK: {e}")

# Call it when the module is loaded
initialize_firebase()

def send_push_notification(token, title, body, data=None):
    """
    Send a push notification to a specific FCM token.
    """
    if not firebase_admin._apps:
        logger.error("Firebase is not initialized. Cannot send notification.")
        return False
        
    if not token:
        logger.warning("Attempted to send push notification but FCM token is missing.")
        return False

    try:
        message = messaging.Message(
            notification=messaging.Notification(
                title=title,
                body=body,
            ),
            android=messaging.AndroidConfig(
                priority='high',
                notification=messaging.AndroidNotification(
                    default_sound=True,
                    default_vibrate_timings=True,
                )
            ),
            data=data if data else {},
            token=token,
        )

        response = messaging.send(message)
        logger.info(f"Successfully sent FCM message: {response}")
        return True
    except Exception as e:
        logger.error(f"Error sending FCM message: {e}")
        return False

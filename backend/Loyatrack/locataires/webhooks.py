"""Webhook Twilio : réception des Status Callbacks (accusés de livraison) — module 2.6."""
import logging

from django.utils import timezone
from rest_framework.decorators import api_view, permission_classes, authentication_classes
from rest_framework.permissions import AllowAny
from rest_framework.response import Response

from .models import Rappel

logger = logging.getLogger(__name__)


@api_view(['POST'])
@authentication_classes([])
@permission_classes([AllowAny])
def twilio_status_callback(request):
    """Twilio POSTe MessageSid + MessageStatus à chaque changement d'état du message."""
    sid = request.data.get('MessageSid') or request.data.get('CallSid')
    statut = request.data.get('MessageStatus') or request.data.get('CallStatus')
    if not sid:
        return Response({'error': 'MessageSid manquant'}, status=400)

    rappels = Rappel.objects.filter(message_sid=sid)
    nb = rappels.update(
        statut_livraison=statut or '',
        date_livraison=timezone.now(),
    )
    logger.info(f"[Twilio webhook] {sid} -> {statut} ({nb} rappel(s) mis à jour)")
    return Response({'status': 'ok', 'updated': nb})

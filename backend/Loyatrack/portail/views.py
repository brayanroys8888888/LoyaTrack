from rest_framework.views import APIView
from rest_framework.permissions import IsAuthenticated
from rest_framework.response import Response
from django.shortcuts import render, get_object_or_404

from locataires.models import Locataire
from .models import AccesPortail
from abonnements.permissions import requiere_pro


class GenererAccesPortailView(APIView):
    """Le bailleur génère/regénère le lien d'accès portail d'un de ses locataires,
    et l'envoie par SMS au locataire (3.5). Fonction Pro."""
    permission_classes = [IsAuthenticated, requiere_pro('portail')]

    def post(self, request):
        locataire_id = request.data.get('locataire')
        if not locataire_id:
            return Response({'error': 'locataire requis'}, status=400)
        locataire = get_object_or_404(
            Locataire, pk=locataire_id, bailleur=request.user, is_deleted=False
        )
        acces = AccesPortail.creer_ou_regenerer(locataire)
        lien = request.build_absolute_uri(f'/portail/{acces.token}/')

        envoyer_sms = request.data.get('envoyer_sms', False)
        if envoyer_sms:
            try:
                from locataires.services import send_twilio_message
                send_twilio_message(
                    locataire.telephone,
                    f"Bonjour, accédez à votre espace locataire Loyatrack : {lien}",
                    'SMS',
                )
            except Exception:
                pass

        return Response({
            'lien': lien,
            'token': acces.token,
            'date_expiration': acces.date_expiration,
        })


def portail_locataire(request, token):
    """Page web publique en lecture seule pour le locataire."""
    acces = AccesPortail.objects.filter(token=token).select_related('locataire').first()
    if not acces or not acces.est_valide:
        return render(request, 'portail/invalide.html', status=404)

    locataire = acces.locataire
    paiements = locataire.paiements.all()[:50]
    penalites = locataire.penalites.all()[:50]
    return render(request, 'portail/locataire.html', {
        'locataire': locataire,
        'paiements': paiements,
        'penalites': penalites,
    })

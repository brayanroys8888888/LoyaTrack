from rest_framework import viewsets, status
from rest_framework.decorators import action
from rest_framework.permissions import IsAuthenticated
from rest_framework.response import Response
from django.http import HttpResponse

from .models import Paiement
from .serializers import PaiementSerializer
from .services import (
    appliquer_paiement, generer_quittance_pdf,
    exporter_paiements_pdf, exporter_paiements_excel,
)
from abonnements.permissions import AbonnementActif
from abonnements.services import exiger_pro


class PaiementViewSet(viewsets.ModelViewSet):
    serializer_class = PaiementSerializer
    permission_classes = [IsAuthenticated, AbonnementActif]

    def get_queryset(self):
        if getattr(self, 'swagger_fake_view', False):
            return Paiement.objects.none()
        queryset = Paiement.objects.filter(locataire__bailleur=self.request.user)
        locataire_id = self.request.query_params.get('locataire', None)
        if locataire_id is not None:
            queryset = queryset.filter(locataire_id=locataire_id)
        return queryset

    def perform_create(self, serializer):
        paiement = serializer.save()
        appliquer_paiement(paiement)

    @action(detail=True, methods=['get'])
    def quittance(self, request, pk=None):
        """Télécharge la quittance de loyer (PDF) pour ce paiement."""
        paiement = self.get_object()
        try:
            pdf = generer_quittance_pdf(paiement)
        except ImportError:
            return Response(
                {'error': "reportlab n'est pas installé sur le serveur."},
                status=status.HTTP_501_NOT_IMPLEMENTED,
            )
        response = HttpResponse(pdf, content_type='application/pdf')
        response['Content-Disposition'] = f'attachment; filename="quittance_{paiement.id}.pdf"'
        return response

    @action(detail=False, methods=['get'])
    def exporter(self, request):
        """Exporte la liste des paiements (filtrée) en PDF ou Excel.

        Paramètres : ?fmt=pdf|excel  &  ?mode=<mode_paiement> (optionnel,
        ex. 'Mobile Money')  & ?locataire=<id> (optionnel, géré par get_queryset).
        NB : on évite le nom `format` qui est réservé à la négociation DRF."""
        exiger_pro(request.user, 'comptabilite')
        qs = self.get_queryset().select_related('locataire')
        mode = request.query_params.get('mode')
        if mode:
            qs = qs.filter(mode_paiement=mode)

        fmt = (request.query_params.get('fmt') or 'pdf').lower()
        try:
            if fmt == 'excel':
                data = exporter_paiements_excel(qs)
                ct = 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet'
                ext = 'xlsx'
            else:
                data = exporter_paiements_pdf(qs)
                ct = 'application/pdf'
                ext = 'pdf'
        except ImportError:
            return Response(
                {'error': "Bibliothèque d'export (reportlab/openpyxl) absente du serveur."},
                status=status.HTTP_501_NOT_IMPLEMENTED,
            )
        response = HttpResponse(data, content_type=ct)
        response['Content-Disposition'] = f'attachment; filename="paiements.{ext}"'
        return response

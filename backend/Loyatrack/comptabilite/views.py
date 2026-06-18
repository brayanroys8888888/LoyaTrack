from datetime import date

from rest_framework import viewsets
from rest_framework.decorators import action
from rest_framework.permissions import IsAuthenticated
from rest_framework.response import Response
from django.http import HttpResponse

from .models import Depense
from .serializers import DepenseSerializer
from . import services
from abonnements.permissions import requiere_pro


class DepenseViewSet(viewsets.ModelViewSet):
    serializer_class = DepenseSerializer
    # Toute la comptabilité est une fonction Pro (implique aussi un abonnement actif).
    permission_classes = [IsAuthenticated, requiere_pro('comptabilite')]

    def get_queryset(self):
        if getattr(self, 'swagger_fake_view', False):
            return Depense.objects.none()
        qs = Depense.objects.filter(bailleur=self.request.user)
        annee = self.request.query_params.get('annee')
        if annee:
            qs = qs.filter(date__year=annee)
        return qs

    def perform_create(self, serializer):
        serializer.save(bailleur=self.request.user)

    @action(detail=False, methods=['get'])
    def releve(self, request):
        annee = int(request.query_params.get('annee', date.today().year))
        return Response(services.releve_annuel(request.user, annee))

    @action(detail=False, methods=['get'])
    def export_excel(self, request):
        annee = int(request.query_params.get('annee', date.today().year))
        data = services.export_excel(services.releve_annuel(request.user, annee))
        resp = HttpResponse(
            data, content_type='application/vnd.openxmlformats-officedocument.spreadsheetml.sheet'
        )
        resp['Content-Disposition'] = f'attachment; filename="releve_{annee}.xlsx"'
        return resp

    @action(detail=False, methods=['get'])
    def export_pdf(self, request):
        annee = int(request.query_params.get('annee', date.today().year))
        data = services.export_pdf(services.releve_annuel(request.user, annee))
        resp = HttpResponse(data, content_type='application/pdf')
        resp['Content-Disposition'] = f'attachment; filename="releve_{annee}.pdf"'
        return resp

from rest_framework import viewsets
from rest_framework.permissions import IsAuthenticated
from .models import Propriete, UniteLogement
from .serializers import ProprieteSerializer, UniteLogementSerializer
from abonnements.permissions import AbonnementActif
from abonnements.services import exiger_pro, peut_creer_bien


class ProprieteViewSet(viewsets.ModelViewSet):
    serializer_class = ProprieteSerializer
    permission_classes = [IsAuthenticated, AbonnementActif]

    def get_queryset(self):
        if getattr(self, 'swagger_fake_view', False):
            return Propriete.objects.none()
        return Propriete.objects.filter(bailleur=self.request.user)

    def perform_create(self, serializer):
        # Essentiel = 1 bien : au-delà, on exige le plan Pro (multi_biens).
        nb = Propriete.objects.filter(bailleur=self.request.user).count()
        if not peut_creer_bien(self.request.user, nb):
            exiger_pro(self.request.user, 'multi_biens')
        serializer.save(bailleur=self.request.user)


class UniteLogementViewSet(viewsets.ModelViewSet):
    serializer_class = UniteLogementSerializer
    permission_classes = [IsAuthenticated, AbonnementActif]

    def get_queryset(self):
        if getattr(self, 'swagger_fake_view', False):
            return UniteLogement.objects.none()
        qs = UniteLogement.objects.filter(propriete__bailleur=self.request.user)
        propriete_id = self.request.query_params.get('propriete')
        if propriete_id:
            qs = qs.filter(propriete_id=propriete_id)
        return qs

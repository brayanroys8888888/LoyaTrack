from rest_framework import viewsets, mixins, status
from rest_framework.decorators import action
from rest_framework.permissions import IsAuthenticated
from rest_framework.response import Response
from django.db.models import Sum

from .models import Penalite, ConfigPenalite
from .serializers import PenaliteSerializer, ConfigPenaliteSerializer, RemiseSerializer
from .services import remettre_penalite
from abonnements.permissions import AbonnementActif


class PenaliteViewSet(mixins.ListModelMixin, mixins.RetrieveModelMixin, viewsets.GenericViewSet):
    serializer_class = PenaliteSerializer
    permission_classes = [IsAuthenticated, AbonnementActif]

    def get_queryset(self):
        if getattr(self, 'swagger_fake_view', False):
            return Penalite.objects.none()
        qs = Penalite.objects.filter(locataire__bailleur=self.request.user)
        locataire_id = self.request.query_params.get('locataire')
        if locataire_id:
            qs = qs.filter(locataire_id=locataire_id)
        return qs

    @action(detail=True, methods=['post'])
    def remise(self, request, pk=None):
        """Accorde une remise (totale ou partielle) sur une pénalité. Motif obligatoire."""
        penalite = self.get_object()
        serializer = RemiseSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        try:
            remettre_penalite(
                penalite,
                motif=serializer.validated_data['motif'],
                montant=serializer.validated_data.get('montant'),
            )
        except ValueError as e:
            return Response({'error': str(e)}, status=status.HTTP_400_BAD_REQUEST)
        return Response(PenaliteSerializer(penalite).data)

    @action(detail=False, methods=['get'])
    def resume(self, request):
        """Synthèse des pénalités du bailleur pour le tableau de bord."""
        qs = self.get_queryset()
        actives = qs.filter(statut='Active')
        total_actif = sum((p.montant_net for p in actives), 0)
        agg = qs.aggregate(total_brut=Sum('total'), total_remises=Sum('montant_remise'))
        return Response({
            'penalites_actives': actives.count(),
            'locataires_en_penalite': actives.values('locataire').distinct().count(),
            'montant_du': total_actif,
            'total_brut': agg['total_brut'] or 0,
            'total_remises': agg['total_remises'] or 0,
        })


class ConfigPenaliteViewSet(viewsets.ModelViewSet):
    serializer_class = ConfigPenaliteSerializer
    permission_classes = [IsAuthenticated, AbonnementActif]

    def get_queryset(self):
        if getattr(self, 'swagger_fake_view', False):
            return ConfigPenalite.objects.none()
        qs = ConfigPenalite.objects.filter(locataire__bailleur=self.request.user)
        locataire_id = self.request.query_params.get('locataire')
        if locataire_id:
            qs = qs.filter(locataire_id=locataire_id)
        return qs

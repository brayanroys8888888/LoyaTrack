from django.core.exceptions import ValidationError as DjangoValidationError
from django.shortcuts import get_object_or_404

from rest_framework import viewsets, status, generics
from rest_framework.decorators import action
from rest_framework.permissions import IsAuthenticated
from rest_framework.response import Response

from biens.models import UniteLogement

from . import services, messagerie
from .models import Ville, Annonce, PhotoAnnonce, Conversation
from .serializers import (
    VilleSerializer, AnnonceSerializer, PhotoAnnonceSerializer,
    ConversationSerializer, ConversationDetailSerializer,
)

# Type de propriété (biens) → type d'annonce. Une unité d'immeuble se loue
# comme un appartement ; sinon on reprend le type s'il est valide.
_TYPES_ANNONCE = dict(Annonce.TYPE_CHOICES)


def _type_depuis_propriete(propriete):
    t = propriete.type
    if t == 'immeuble' or t not in _TYPES_ANNONCE:
        return 'appartement'
    return t


class AnnonceViewSet(viewsets.ModelViewSet):
    """CRUD des annonces du bailleur + actions de cycle de vie et photos.

    Volontairement NON gardé par `AbonnementActif` : la vitrine est le canal
    d'acquisition (les limites par plan viendront au Palier 4).
    """
    serializer_class = AnnonceSerializer
    permission_classes = [IsAuthenticated]

    def get_queryset(self):
        if getattr(self, 'swagger_fake_view', False):
            return Annonce.objects.none()
        qs = Annonce.objects.filter(bailleur=self.request.user).prefetch_related('photos')
        statut = self.request.query_params.get('statut')
        if statut:
            qs = qs.filter(statut=statut)
        return qs

    def perform_create(self, serializer):
        serializer.save(bailleur=self.request.user)

    @action(detail=False, methods=['post'], url_path='depuis-unite')
    def depuis_unite(self, request):
        """Crée un brouillon pré-rempli à partir d'une unité vacante du bailleur."""
        unite = get_object_or_404(
            UniteLogement, pk=request.data.get('unite'),
            propriete__bailleur=request.user)
        type_bien = _type_depuis_propriete(unite.propriete)
        annonce = Annonce.objects.create(
            bailleur=request.user, unite=unite,
            loyer=unite.loyer_standard or 0, type_bien=type_bien,
            titre=f"{_TYPES_ANNONCE[type_bien]} à louer",
        )
        return Response(self.get_serializer(annonce).data, status=status.HTTP_201_CREATED)

    @action(detail=True, methods=['post'])
    def publier(self, request, pk=None):
        annonce = self.get_object()
        try:
            services.publier(annonce)
        except DjangoValidationError as e:
            return Response({'erreurs': e.messages}, status=status.HTTP_400_BAD_REQUEST)
        return Response(self.get_serializer(annonce).data)

    @action(detail=True, methods=['post'])
    def renouveler(self, request, pk=None):
        annonce = self.get_object()
        try:
            services.renouveler(annonce)
        except DjangoValidationError as e:
            return Response({'erreurs': e.messages}, status=status.HTTP_400_BAD_REQUEST)
        return Response(self.get_serializer(annonce).data)

    @action(detail=True, methods=['post'])
    def depublier(self, request, pk=None):
        annonce = self.get_object()
        services.depublier(annonce, pourvue=bool(request.data.get('pourvue')))
        return Response(self.get_serializer(annonce).data)

    @action(detail=True, methods=['post'], url_path='photos')
    def ajouter_photo(self, request, pk=None):
        annonce = self.get_object()
        if annonce.photos.count() >= 10:
            return Response({'erreur': 'Maximum 10 photos par annonce.'},
                            status=status.HTTP_400_BAD_REQUEST)
        image = request.FILES.get('image')
        if not image:
            return Response({'erreur': 'Fichier « image » requis.'},
                            status=status.HTTP_400_BAD_REQUEST)
        photo = PhotoAnnonce.objects.create(
            annonce=annonce, image=image, ordre=annonce.photos.count(),
            est_couverture=not annonce.photos.exists(),  # 1re photo = couverture
        )
        return Response(
            PhotoAnnonceSerializer(photo, context=self.get_serializer_context()).data,
            status=status.HTTP_201_CREATED)

    @action(detail=True, methods=['delete'], url_path=r'photos/(?P<photo_id>\d+)')
    def supprimer_photo(self, request, pk=None, photo_id=None):
        annonce = self.get_object()
        photo = get_object_or_404(annonce.photos, pk=photo_id)
        etait_couverture = photo.est_couverture
        photo.delete()
        # Promeut une nouvelle couverture si on a supprimé l'ancienne.
        if etait_couverture:
            suivante = annonce.photos.first()
            if suivante:
                suivante.est_couverture = True
                suivante.save(update_fields=['est_couverture'])
        return Response(status=status.HTTP_204_NO_CONTENT)


class VilleListView(generics.ListAPIView):
    """Villes + quartiers pour les sélecteurs du formulaire d'annonce."""
    serializer_class = VilleSerializer
    permission_classes = [IsAuthenticated]
    pagination_class = None  # référentiel court : tout renvoyer d'un coup

    def get_queryset(self):
        return Ville.objects.prefetch_related('quartiers').all()


class ConversationViewSet(viewsets.ReadOnlyModelViewSet):
    """Conversations reçues par le bailleur sur ses annonces (messagerie)."""
    permission_classes = [IsAuthenticated]

    def get_queryset(self):
        if getattr(self, 'swagger_fake_view', False):
            return Conversation.objects.none()
        return (Conversation.objects.filter(bailleur=self.request.user)
                .select_related('annonce', 'chercheur').prefetch_related('messages'))

    def get_serializer_class(self):
        return ConversationDetailSerializer if self.action == 'retrieve' else ConversationSerializer

    def _detail(self, pk):
        # Re-requête fraîche (le prefetch de messages est mis en cache).
        conv = self.get_queryset().get(pk=pk)
        return Response(ConversationDetailSerializer(conv, context=self.get_serializer_context()).data)

    def retrieve(self, request, *args, **kwargs):
        conv = self.get_object()
        # Ouvrir le fil marque comme lus les messages du chercheur.
        conv.messages.filter(expediteur='chercheur', lu=False).update(lu=True)
        return self._detail(conv.pk)

    @action(detail=True, methods=['post'])
    def repondre(self, request, pk=None):
        conv = self.get_object()
        corps = (request.data.get('corps') or '').strip()
        if not corps:
            return Response({'erreur': 'Message vide.'}, status=status.HTTP_400_BAD_REQUEST)
        try:
            messagerie.repondre(conv, 'bailleur', corps)
        except messagerie.MessagerieError as e:
            return Response({'erreur': str(e)}, status=status.HTTP_400_BAD_REQUEST)
        return self._detail(conv.pk)

    @action(detail=True, methods=['post'])
    def bloquer(self, request, pk=None):
        conv = self.get_object()
        conv.statut = 'bloquee'
        conv.save(update_fields=['statut'])
        return Response(self.get_serializer(conv).data)

    @action(detail=True, methods=['post'])
    def archiver(self, request, pk=None):
        conv = self.get_object()
        conv.statut = 'archivee'
        conv.save(update_fields=['statut'])
        return Response(ConversationSerializer(conv, context=self.get_serializer_context()).data)

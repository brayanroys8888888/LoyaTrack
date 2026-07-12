from django.urls import path, include
from rest_framework.routers import DefaultRouter

from .views import AnnonceViewSet, VilleListView, ConversationViewSet

router = DefaultRouter()
router.register(r'annonces', AnnonceViewSet, basename='annonce')
router.register(r'conversations', ConversationViewSet, basename='conversation')

urlpatterns = [
    path('localisations/villes/', VilleListView.as_view(), name='annonces-villes'),
    path('', include(router.urls)),
]

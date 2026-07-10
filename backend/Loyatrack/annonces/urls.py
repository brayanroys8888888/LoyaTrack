from django.urls import path, include
from rest_framework.routers import DefaultRouter

from .views import AnnonceViewSet, VilleListView

router = DefaultRouter()
router.register(r'annonces', AnnonceViewSet, basename='annonce')

urlpatterns = [
    path('localisations/villes/', VilleListView.as_view(), name='annonces-villes'),
    path('', include(router.urls)),
]

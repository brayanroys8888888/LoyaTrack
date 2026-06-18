from django.urls import path
from .views import GenererAccesPortailView, portail_locataire

# API (sous /api/v1/) : génération du lien par le bailleur
api_urlpatterns = [
    path('portail/generer/', GenererAccesPortailView.as_view(), name='portail_generer'),
]

# Web (à la racine) : page publique du locataire
web_urlpatterns = [
    path('portail/<str:token>/', portail_locataire, name='portail_locataire'),
]

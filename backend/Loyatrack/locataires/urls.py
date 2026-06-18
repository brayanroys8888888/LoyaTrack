from django.urls import path, include
from rest_framework.routers import DefaultRouter
from .views import (
    LocataireViewSet, DashboardView, NotificationViewSet,
    EtatDesLieuxViewSet, PhotoEtatDesLieuxViewSet,
)
from .webhooks import twilio_status_callback

router = DefaultRouter()
router.register(r'locataires', LocataireViewSet, basename='locataire')
router.register(r'notifications', NotificationViewSet, basename='notification')
router.register(r'etats-des-lieux', EtatDesLieuxViewSet, basename='etat-des-lieux')
router.register(r'photos-etat-des-lieux', PhotoEtatDesLieuxViewSet, basename='photo-etat-des-lieux')

urlpatterns = [
    path('', include(router.urls)),
    path('dashboard/', DashboardView.as_view(), name='dashboard'),
    path('webhooks/twilio/', twilio_status_callback, name='twilio_webhook'),
]

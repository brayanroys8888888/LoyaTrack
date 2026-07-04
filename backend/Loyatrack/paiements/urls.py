from django.urls import path, include
from rest_framework.routers import DefaultRouter
from .views import (
    PaiementViewSet, DemandePaiementViewSet, CompteMarchandView, WebhookLoyerView,
)

router = DefaultRouter()
router.register(r'paiements', PaiementViewSet, basename='paiement')
router.register(r'demandes-paiement', DemandePaiementViewSet, basename='demande-paiement')

urlpatterns = [
    path('', include(router.urls)),
    path('compte-marchand/', CompteMarchandView.as_view(), name='compte-marchand'),
    path('webhooks/paiement-loyer/', WebhookLoyerView.as_view(), name='webhook-paiement-loyer'),
]

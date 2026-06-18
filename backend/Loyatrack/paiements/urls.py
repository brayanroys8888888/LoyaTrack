from django.urls import path, include
from rest_framework.routers import DefaultRouter
from .views import PaiementViewSet

router = DefaultRouter()
router.register(r'paiements', PaiementViewSet, basename='paiement')

urlpatterns = [
    path('', include(router.urls)),
]

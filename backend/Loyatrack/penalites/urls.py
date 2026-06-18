from django.urls import path, include
from rest_framework.routers import DefaultRouter
from .views import PenaliteViewSet, ConfigPenaliteViewSet

router = DefaultRouter()
router.register(r'penalites', PenaliteViewSet, basename='penalite')
router.register(r'config-penalites', ConfigPenaliteViewSet, basename='config-penalite')

urlpatterns = [
    path('', include(router.urls)),
]

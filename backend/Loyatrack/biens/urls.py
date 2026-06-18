from django.urls import path, include
from rest_framework.routers import DefaultRouter
from .views import ProprieteViewSet, UniteLogementViewSet

router = DefaultRouter()
router.register(r'proprietes', ProprieteViewSet, basename='propriete')
router.register(r'unites', UniteLogementViewSet, basename='unite')

urlpatterns = [
    path('', include(router.urls)),
]

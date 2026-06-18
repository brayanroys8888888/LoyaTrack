from django.contrib import admin
from django.urls import path, include
from django.conf import settings
from django.conf.urls.static import static
from rest_framework_simplejwt.views import (
    TokenObtainPairView,
    TokenRefreshView,
)

from rest_framework import permissions
from drf_yasg.views import get_schema_view
from drf_yasg import openapi

from portail.urls import api_urlpatterns as portail_api, web_urlpatterns as portail_web
from abonnements.web_urls import web_urlpatterns as abonnements_web
from accounts.views import ParametresView

schema_view = get_schema_view(
    openapi.Info(
        title="Loyatrack API",
        default_version='v1',
        description="API pour l'application mobile de gestion locative",
        contact=openapi.Contact(email="contact@loyatrack.local"),
    ),
    public=True,
    permission_classes=(permissions.AllowAny,),
)


urlpatterns = [
    path('admin/', admin.site.urls),
    
    # Swagger
    path('swagger/', schema_view.with_ui('swagger', cache_timeout=0), name='schema-swagger-ui'),

    # API v1
    path('api/v1/auth/token/', TokenObtainPairView.as_view(), name='token_obtain_pair'),
    path('api/v1/auth/token/refresh/', TokenRefreshView.as_view(), name='token_refresh'),
    path('api/v1/auth/', include('accounts.urls')),
    path('api/v1/parametres/', ParametresView.as_view(), name='parametres'),

    path('api/v1/', include('locataires.urls')),
    path('api/v1/', include('paiements.urls')),
    path('api/v1/', include('penalites.urls')),
    path('api/v1/', include('biens.urls')),
    path('api/v1/', include('comptabilite.urls')),
    path('api/v1/', include('abonnements.urls')),
    path('api/v1/', include(portail_api)),
    # Pages web publiques (à la racine) : portail locataire + espace abonnement bailleur
    path('', include(portail_web)),
    path('', include(abonnements_web)),
]

if settings.DEBUG:
    urlpatterns += static(settings.MEDIA_URL, document_root=settings.MEDIA_ROOT)

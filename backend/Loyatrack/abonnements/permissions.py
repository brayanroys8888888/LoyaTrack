"""Permissions de gating. Le corps des 403 porte un `code` exploité par l'app
Flutter pour router vers le bon écran (paywall vs upsell Pro)."""
from rest_framework.exceptions import PermissionDenied
from rest_framework.permissions import BasePermission

from . import services


class FonctionPro(PermissionDenied):
    """403 spécifique : fonctionnalité réservée au plan Pro."""
    default_detail = {
        'code': 'fonction_pro',
        'message': "Cette fonctionnalité nécessite le plan Pro.",
    }


class AbonnementActif(BasePermission):
    """Bloque tout accès si l'abonnement (essai/payé/grâce) n'est plus valide.

    À combiner avec IsAuthenticated. Les staff (admin) sont exemptés.
    """
    message = {
        'code': 'abonnement_expire',
        'message': "Votre accès a expiré. Gérez votre abonnement en ligne pour continuer.",
    }

    def has_permission(self, request, view):
        user = getattr(request, 'user', None)
        if not user or not user.is_authenticated:
            return False
        if user.is_staff:
            return True
        return services.assurer_abonnement(user).est_actif


def requiere_pro(feature):
    """Fabrique une permission qui exige le droit `feature` (Pro). Implique aussi
    un abonnement actif (a_droit renvoie False si expiré)."""
    class _RequierePro(BasePermission):
        message = FonctionPro.default_detail

        def has_permission(self, request, view):
            user = getattr(request, 'user', None)
            if not user or not user.is_authenticated:
                return False
            if user.is_staff:
                return True
            return services.assurer_abonnement(user).a_droit(feature)

    return _RequierePro

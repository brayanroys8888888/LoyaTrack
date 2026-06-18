from rest_framework import serializers

from . import constants
from .models import Abonnement


class AbonnementSerializer(serializers.ModelSerializer):
    """Statut d'abonnement consommé par l'app (lecture seule)."""
    droits = serializers.SerializerMethodField()
    est_actif = serializers.BooleanField(read_only=True)
    jours_restants = serializers.IntegerField(read_only=True)
    date_fin_effective = serializers.DateTimeField(read_only=True)
    features = serializers.SerializerMethodField()
    max_biens = serializers.SerializerMethodField()

    class Meta:
        model = Abonnement
        fields = (
            'plan', 'statut', 'droits', 'est_actif', 'jours_restants',
            'date_fin_effective', 'date_fin_essai', 'date_fin', 'periodicite',
            'features', 'max_biens',
        )

    def get_droits(self, obj):
        return obj.droits

    def get_features(self, obj):
        """Liste des fonctions Pro débloquées pour ce bailleur (vide si Essentiel/expiré)."""
        if obj.droits == constants.PLAN_PRO:
            return sorted(constants.FEATURES_PRO)
        return []

    def get_max_biens(self, obj):
        return obj.max_biens  # None = illimité


class CheckoutSerializer(serializers.Serializer):
    plan = serializers.ChoiceField(choices=list(constants.PLANS.keys()))
    periodicite = serializers.ChoiceField(choices=list(constants.PERIODICITES))

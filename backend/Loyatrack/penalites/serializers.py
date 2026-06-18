from rest_framework import serializers
from .models import Penalite, ConfigPenalite


class PenaliteSerializer(serializers.ModelSerializer):
    montant_net = serializers.DecimalField(max_digits=10, decimal_places=2, read_only=True)
    locataire_nom = serializers.SerializerMethodField()

    class Meta:
        model = Penalite
        fields = '__all__'

    def get_locataire_nom(self, obj):
        return f"{obj.locataire.prenom} {obj.locataire.nom}"


class ConfigPenaliteSerializer(serializers.ModelSerializer):
    montant_journalier_calcule = serializers.SerializerMethodField()

    class Meta:
        model = ConfigPenalite
        fields = '__all__'

    def get_montant_journalier_calcule(self, obj):
        return obj.montant_journalier()

    def validate_locataire(self, value):
        request = self.context.get('request')
        if request and value.bailleur != request.user:
            raise serializers.ValidationError("Ce locataire ne vous appartient pas.")
        return value


class RemiseSerializer(serializers.Serializer):
    motif = serializers.CharField(required=True, allow_blank=False)
    montant = serializers.DecimalField(
        max_digits=10, decimal_places=2, required=False, allow_null=True,
        help_text="Montant de la remise. Vide = remise totale."
    )

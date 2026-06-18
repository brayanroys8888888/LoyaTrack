from rest_framework import serializers
from .models import Paiement

class PaiementSerializer(serializers.ModelSerializer):
    locataire_nom = serializers.SerializerMethodField()
    locataire_prenom = serializers.SerializerMethodField()

    class Meta:
        model = Paiement
        fields = '__all__'
        # Champs calculés côté serveur par appliquer_paiement()
        read_only_fields = ('statut', 'reste_du', 'nb_mois', 'periode_fin', 'date_creation')

    def get_locataire_nom(self, obj):
        return obj.locataire.nom

    def get_locataire_prenom(self, obj):
        return obj.locataire.prenom

    def validate_locataire(self, value):
        if value.bailleur != self.context['request'].user:
            raise serializers.ValidationError("Ce locataire ne vous appartient pas.")
        return value

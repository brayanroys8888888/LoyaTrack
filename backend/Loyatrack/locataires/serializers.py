from rest_framework import serializers
from .models import (
    Locataire, Rappel, Notification,
    HistoriqueLoyer, MouvementCaution, EtatDesLieux, PhotoEtatDesLieux,
)

class LocataireSerializer(serializers.ModelSerializer):
    class Meta:
        model = Locataire
        fields = '__all__'
        read_only_fields = ('bailleur', 'total_penalites', 'statut_caution', 'archive', 'date_sortie')

class LocataireStatutSerializer(serializers.ModelSerializer):
    class Meta:
        model = Locataire
        fields = ('statut',)

class RappelSerializer(serializers.ModelSerializer):
    class Meta:
        model = Rappel
        fields = '__all__'

class NotificationSerializer(serializers.ModelSerializer):
    locataire_nom = serializers.SerializerMethodField()

    class Meta:
        model = Notification
        fields = '__all__'
        read_only_fields = ('bailleur',)

    def get_locataire_nom(self, obj):
        if obj.locataire:
            return f"{obj.locataire.prenom} {obj.locataire.nom}"
        return "Système"


class HistoriqueLoyerSerializer(serializers.ModelSerializer):
    class Meta:
        model = HistoriqueLoyer
        fields = '__all__'


class MouvementCautionSerializer(serializers.ModelSerializer):
    class Meta:
        model = MouvementCaution
        fields = '__all__'


class PhotoEtatDesLieuxSerializer(serializers.ModelSerializer):
    class Meta:
        model = PhotoEtatDesLieux
        fields = '__all__'


class EtatDesLieuxSerializer(serializers.ModelSerializer):
    photos = PhotoEtatDesLieuxSerializer(many=True, read_only=True)

    class Meta:
        model = EtatDesLieux
        fields = '__all__'

    def validate_locataire(self, value):
        request = self.context.get('request')
        if request and value.bailleur != request.user:
            raise serializers.ValidationError("Ce locataire ne vous appartient pas.")
        return value

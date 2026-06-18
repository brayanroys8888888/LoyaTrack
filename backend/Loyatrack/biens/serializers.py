from rest_framework import serializers
from django.db.models import Sum
from .models import Propriete, UniteLogement


class UniteLogementSerializer(serializers.ModelSerializer):
    est_occupee = serializers.BooleanField(read_only=True)
    propriete_titre = serializers.CharField(source='propriete.titre', read_only=True)
    locataire_nom = serializers.SerializerMethodField()

    class Meta:
        model = UniteLogement
        fields = '__all__'
        read_only_fields = ('statut',)

    def get_locataire_nom(self, obj):
        loc = obj.locataires.filter(is_deleted=False).first()
        return f"{loc.prenom} {loc.nom}" if loc else None

    def validate_propriete(self, value):
        request = self.context.get('request')
        if request and value.bailleur != request.user:
            raise serializers.ValidationError("Cette propriété ne vous appartient pas.")
        return value


class ProprieteSerializer(serializers.ModelSerializer):
    nb_unites = serializers.SerializerMethodField()
    nb_occupees = serializers.SerializerMethodField()
    taux_occupation = serializers.SerializerMethodField()
    revenus_attendus = serializers.SerializerMethodField()

    class Meta:
        model = Propriete
        fields = '__all__'
        read_only_fields = ('bailleur',)

    def get_nb_unites(self, obj):
        return obj.unites.count()

    def get_nb_occupees(self, obj):
        return obj.unites.filter(locataires__is_deleted=False).distinct().count()

    def get_taux_occupation(self, obj):
        total = obj.unites.count()
        if not total:
            return 0
        return round(self.get_nb_occupees(obj) / total * 100, 1)

    def get_revenus_attendus(self, obj):
        return obj.unites.aggregate(t=Sum('loyer_standard'))['t'] or 0

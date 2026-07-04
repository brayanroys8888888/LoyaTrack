from rest_framework import serializers
from .models import Paiement, DemandePaiement, CompteMarchand

class PaiementSerializer(serializers.ModelSerializer):
    locataire_nom = serializers.SerializerMethodField()
    locataire_prenom = serializers.SerializerMethodField()
    locataire_logement = serializers.SerializerMethodField()

    class Meta:
        model = Paiement
        fields = '__all__'
        # Champs calculés côté serveur par appliquer_paiement()
        read_only_fields = ('statut', 'reste_du', 'nb_mois', 'periode_fin', 'date_creation')

    def get_locataire_nom(self, obj):
        return obj.locataire.nom

    def get_locataire_prenom(self, obj):
        return obj.locataire.prenom

    def get_locataire_logement(self, obj):
        loc = obj.locataire
        return loc.adresse_logement or loc.logement or (str(loc.unite) if loc.unite else '')

    def validate_locataire(self, value):
        if value.bailleur != self.context['request'].user:
            raise serializers.ValidationError("Ce locataire ne vous appartient pas.")
        return value


class DemandePaiementSerializer(serializers.ModelSerializer):
    locataire_nom = serializers.SerializerMethodField()

    class Meta:
        model = DemandePaiement
        fields = (
            'id', 'locataire', 'locataire_nom', 'reference_interne', 'montant',
            'montant_loyer', 'frais', 'periode', 'statut', 'url_paiement',
            'reversement_statut', 'date_creation', 'date_paiement',
        )
        read_only_fields = (
            'reference_interne', 'montant', 'montant_loyer', 'frais', 'periode',
            'statut', 'url_paiement', 'reversement_statut', 'date_creation',
            'date_paiement',
        )

    def get_locataire_nom(self, obj):
        return f"{obj.locataire.prenom} {obj.locataire.nom}".strip()

    def validate_locataire(self, value):
        if value.bailleur != self.context['request'].user:
            raise serializers.ValidationError("Ce locataire ne vous appartient pas.")
        return value


class CompteMarchandSerializer(serializers.ModelSerializer):
    """Destination de reversement du bailleur : simple numéro Mobile Money +
    opérateur (aucune clé d'API — la collecte se fait sur le compte plateforme)."""
    est_configure = serializers.SerializerMethodField()

    class Meta:
        model = CompteMarchand
        fields = ('prestataire', 'numero_momo', 'operateur',
                  'frais_pourcentage', 'actif', 'est_configure')

    def get_est_configure(self, obj):
        return obj.est_configure()

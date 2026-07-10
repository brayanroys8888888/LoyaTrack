from rest_framework import serializers

from .models import Ville, Quartier, Annonce, PhotoAnnonce


class QuartierSerializer(serializers.ModelSerializer):
    class Meta:
        model = Quartier
        fields = ('id', 'nom', 'slug')


class VilleSerializer(serializers.ModelSerializer):
    quartiers = QuartierSerializer(many=True, read_only=True)

    class Meta:
        model = Ville
        fields = ('id', 'nom', 'slug', 'region', 'quartiers')


class PhotoAnnonceSerializer(serializers.ModelSerializer):
    class Meta:
        model = PhotoAnnonce
        fields = ('id', 'image', 'ordre', 'est_couverture')
        read_only_fields = ('ordre', 'est_couverture')


class AnnonceSerializer(serializers.ModelSerializer):
    photos = PhotoAnnonceSerializer(many=True, read_only=True)
    ville_nom = serializers.CharField(source='ville.nom', read_only=True)
    quartier_nom = serializers.CharField(source='quartier.nom', read_only=True)
    url_publique = serializers.SerializerMethodField()
    est_visible = serializers.BooleanField(read_only=True)

    class Meta:
        model = Annonce
        fields = (
            'id', 'reference', 'slug', 'url_publique', 'statut', 'est_visible',
            'unite', 'type_bien', 'nb_chambres', 'nb_salons', 'nb_cuisines',
            'nb_douches', 'superficie_m2', 'meuble', 'standing',
            'ville', 'ville_nom', 'quartier', 'quartier_nom', 'adresse_indicative',
            'loyer', 'charges', 'caution_mois',
            'titre', 'description', 'disponible_le',
            'date_publication', 'date_expiration', 'nb_vues', 'nb_contacts',
            'photos', 'date_creation',
        )
        read_only_fields = (
            'reference', 'slug', 'statut', 'date_publication', 'date_expiration',
            'nb_vues', 'nb_contacts', 'date_creation',
        )

    def get_url_publique(self, obj):
        chemin = f'/logements/annonce/{obj.slug}/'
        request = self.context.get('request')
        return request.build_absolute_uri(chemin) if request else chemin

    def validate_unite(self, value):
        request = self.context.get('request')
        if value and request and value.propriete.bailleur != request.user:
            raise serializers.ValidationError("Cette unité ne vous appartient pas.")
        return value

    def validate(self, attrs):
        # Le quartier doit appartenir à la ville sélectionnée (cohérence SEO).
        ville = attrs.get('ville', getattr(self.instance, 'ville', None))
        quartier = attrs.get('quartier', getattr(self.instance, 'quartier', None))
        if quartier and ville and quartier.ville_id != ville.id:
            raise serializers.ValidationError(
                {'quartier': "Ce quartier n'appartient pas à la ville choisie."})
        return attrs

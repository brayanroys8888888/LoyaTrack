from rest_framework import serializers
from .models import Depense


class DepenseSerializer(serializers.ModelSerializer):
    bien_titre = serializers.CharField(source='bien.titre', read_only=True, default=None)

    class Meta:
        model = Depense
        fields = '__all__'
        read_only_fields = ('bailleur',)

    def validate_bien(self, value):
        request = self.context.get('request')
        if value and request and value.bailleur != request.user:
            raise serializers.ValidationError("Ce bien ne vous appartient pas.")
        return value

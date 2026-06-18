from rest_framework import serializers
from django.contrib.auth import get_user_model
from django.contrib.auth.password_validation import validate_password
from django.db.models import Q

from .models import ConfigBailleur

User = get_user_model()


class RegisterSerializer(serializers.ModelSerializer):
    password = serializers.CharField(write_only=True, required=True, validators=[validate_password])
    password_confirm = serializers.CharField(write_only=True, required=True)
    email = serializers.EmailField(required=False, allow_blank=True)
    telephone = serializers.CharField(required=False, allow_blank=True)

    class Meta:
        model = User
        fields = ('email', 'first_name', 'last_name', 'telephone', 'password', 'password_confirm')

    def validate(self, attrs):
        if attrs['password'] != attrs['password_confirm']:
            raise serializers.ValidationError({"password": "Les mots de passe ne correspondent pas."})
        email = (attrs.get('email') or '').strip()
        telephone = (attrs.get('telephone') or '').strip()
        if not email and not telephone:
            raise serializers.ValidationError("Renseignez un email ou un numéro de téléphone.")
        if email and User.objects.filter(email__iexact=email).exists():
            raise serializers.ValidationError({"email": "Cet email est déjà utilisé."})
        if telephone and User.objects.filter(telephone=telephone).exists():
            raise serializers.ValidationError({"telephone": "Ce numéro est déjà utilisé."})
        attrs['email'] = email or None
        attrs['telephone'] = telephone or None
        return attrs

    def create(self, validated_data):
        validated_data.pop('password_confirm')
        return User.objects.create_user(
            email=validated_data.get('email'),
            telephone=validated_data.get('telephone'),
            password=validated_data['password'],
            first_name=validated_data.get('first_name', ''),
            last_name=validated_data.get('last_name', ''),
        )


class LoginSerializer(serializers.Serializer):
    """Connexion par téléphone OU email + mot de passe."""
    identifiant = serializers.CharField(write_only=True)
    password = serializers.CharField(write_only=True)

    def validate(self, attrs):
        ident = attrs['identifiant'].strip()
        user = User.objects.filter(Q(email__iexact=ident) | Q(telephone=ident)).first()
        if user is None or not user.check_password(attrs['password']):
            raise serializers.ValidationError("Identifiants invalides.")
        if not user.is_active:
            raise serializers.ValidationError("Ce compte est désactivé.")
        attrs['user'] = user
        return attrs


class UserSerializer(serializers.ModelSerializer):
    class Meta:
        model = User
        fields = ('id', 'email', 'first_name', 'last_name', 'telephone',
                  'penalite_defaut', 'deux_fa_active', 'date_creation')
        read_only_fields = ('id', 'date_creation', 'deux_fa_active')


class ConfigBailleurSerializer(serializers.ModelSerializer):
    """Paramètres du bailleur. `penalite_defaut` est miroir de `Bailleur.penalite_defaut`
    (montant fixe par défaut — source de vérité unique côté utilisateur)."""
    penalite_defaut = serializers.DecimalField(
        source='user.penalite_defaut', max_digits=10, decimal_places=2, required=False
    )
    adresse_bailleur = serializers.CharField(
        source='user.adresse', required=False, allow_blank=True
    )

    class Meta:
        model = ConfigBailleur
        fields = (
            'langue_interface', 'devise', 'fuseau_horaire', 'format_date',
            'theme', 'sons_notifications',
            'canal_rappel_prefere', 'jours_avant_rappel',
            'rappels_automatiques_actifs', 'notifications_push_actives',
            'delai_grace_defaut', 'type_penalite_defaut', 'pourcentage_penalite_defaut',
            'penalite_defaut', 'adresse_bailleur', 'updated_at',
        )
        read_only_fields = ('updated_at',)

    def update(self, instance, validated_data):
        # Champs miroir du modèle Bailleur (penalite_defaut, adresse).
        user_data = validated_data.pop('user', {})
        if user_data:
            for champ, valeur in user_data.items():
                setattr(instance.user, champ, valeur)
            instance.user.save()
        return super().update(instance, validated_data)


class ChangePasswordSerializer(serializers.Serializer):
    """Changement de mot de passe pour un utilisateur connecté."""
    ancien_mot_de_passe = serializers.CharField(write_only=True)
    nouveau_mot_de_passe = serializers.CharField(write_only=True)

    def validate_ancien_mot_de_passe(self, value):
        user = self.context['request'].user
        if not user.check_password(value):
            raise serializers.ValidationError("Mot de passe actuel incorrect.")
        return value

    def validate_nouveau_mot_de_passe(self, value):
        validate_password(value, self.context['request'].user)
        return value

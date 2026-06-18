from rest_framework import generics, permissions
from rest_framework.views import APIView
from rest_framework.response import Response
from rest_framework_simplejwt.tokens import RefreshToken
from django.contrib.auth import get_user_model
from .models import ConfigBailleur
from .serializers import (
    RegisterSerializer, UserSerializer, LoginSerializer,
    ConfigBailleurSerializer, ChangePasswordSerializer,
)

User = get_user_model()


def tokens_pour(user):
    """Construit la réponse standard {user, access, refresh} pour un utilisateur."""
    refresh = RefreshToken.for_user(user)
    return {
        "user": UserSerializer(user).data,
        "refresh": str(refresh),
        "access": str(refresh.access_token),
    }


class LoginView(APIView):
    """Connexion par téléphone OU email + mot de passe.

    Si la 2FA est activée, renvoie {otp_requis: True, user_id} et envoie un code
    par SMS (voir module 2FA) au lieu des tokens.
    """
    permission_classes = (permissions.AllowAny,)

    def post(self, request):
        serializer = LoginSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        user = serializer.validated_data['user']

        if user.deux_fa_active:
            from .otp import envoyer_otp
            extra = envoyer_otp(user, '2fa')
            return Response({"otp_requis": True, "user_id": user.id, **extra}, status=200)

        return Response(tokens_pour(user), status=200)


class RegisterView(generics.CreateAPIView):
    queryset = User.objects.all()
    permission_classes = (permissions.AllowAny,)
    serializer_class = RegisterSerializer

    def create(self, request, *args, **kwargs):
        serializer = self.get_serializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        user = serializer.save()
        
        # Generates token right after registration so user is logged in
        refresh = RefreshToken.for_user(user)
        
        return Response({
            "user": UserSerializer(user, context=self.get_serializer_context()).data,
            "refresh": str(refresh),
            "access": str(refresh.access_token),
        }, status=201)

class UserProfileView(generics.RetrieveUpdateAPIView):
    serializer_class = UserSerializer
    permission_classes = (permissions.IsAuthenticated,)

    def get_object(self):
        return self.request.user

class UpdateFCMTokenView(APIView):
    permission_classes = (permissions.IsAuthenticated,)

    def post(self, request):
        fcm_token = request.data.get('fcm_token')
        if fcm_token:
            request.user.fcm_token = fcm_token
            request.user.save(update_fields=['fcm_token'])
            return Response({"status": "Token mis à jour"}, status=200)
        return Response({"error": "Jeton manquant"}, status=400)


class ParametresView(generics.RetrieveUpdateAPIView):
    """GET / PATCH des préférences du bailleur connecté (écran Paramètres)."""
    serializer_class = ConfigBailleurSerializer
    permission_classes = (permissions.IsAuthenticated,)

    def get_object(self):
        return ConfigBailleur.pour(self.request.user)


class ChangePasswordView(APIView):
    """Changement de mot de passe pour l'utilisateur connecté."""
    permission_classes = (permissions.IsAuthenticated,)

    def post(self, request):
        serializer = ChangePasswordSerializer(data=request.data, context={'request': request})
        serializer.is_valid(raise_exception=True)
        user = request.user
        user.set_password(serializer.validated_data['nouveau_mot_de_passe'])
        user.save()
        # Invalide les autres sessions, puis renvoie un nouveau couple de tokens
        _blacklister_refresh_tokens(user)
        return Response(tokens_pour(user), status=200)


# ============================ 2FA ============================
from django.contrib.auth.password_validation import validate_password
from django.core.exceptions import ValidationError
from django.core import signing
from .otp import envoyer_otp, verifier_otp, OtpError

RESET_TOKEN_SALT = 'loyatrack.password.reset'
RESET_TOKEN_MAX_AGE = 600  # 10 minutes


def _blacklister_refresh_tokens(user):
    """Invalide tous les refresh tokens actifs de l'utilisateur (sécurité)."""
    try:
        from rest_framework_simplejwt.token_blacklist.models import OutstandingToken, BlacklistedToken
        for ot in OutstandingToken.objects.filter(user=user):
            BlacklistedToken.objects.get_or_create(token=ot)
    except Exception:
        pass


class Login2FAVerifyView(APIView):
    """Valide le code OTP de connexion (2FA) et renvoie les tokens."""
    permission_classes = (permissions.AllowAny,)

    def post(self, request):
        user_id = request.data.get('user_id')
        code = request.data.get('code')
        if not user_id or not code:
            return Response({"error": "user_id et code requis"}, status=400)
        user = User.objects.filter(pk=user_id).first()
        if user is None:
            return Response({"error": "Utilisateur introuvable"}, status=404)
        if not verifier_otp(user, '2fa', code):
            return Response({"error": "Code invalide ou expiré"}, status=400)
        return Response(tokens_pour(user), status=200)


class Toggle2FAView(APIView):
    """Active / désactive la 2FA pour l'utilisateur connecté."""
    permission_classes = (permissions.IsAuthenticated,)

    def post(self, request):
        user = request.user
        activer = request.data.get('active')
        activer = (not user.deux_fa_active) if activer is None else bool(activer)
        if activer and not user.telephone:
            return Response({"error": "Ajoutez un numéro de téléphone pour activer la 2FA."}, status=400)
        user.deux_fa_active = activer
        user.save(update_fields=['deux_fa_active'])
        return Response({"deux_fa_active": user.deux_fa_active}, status=200)


# ============ Réinitialisation de mot de passe par OTP SMS ============
class PasswordForgotView(APIView):
    permission_classes = (permissions.AllowAny,)

    def post(self, request):
        ident = (request.data.get('telephone') or request.data.get('identifiant') or '').strip()
        generic = {"status": "Si un compte existe, un code a été envoyé par SMS."}
        if not ident:
            return Response({"error": "Téléphone requis"}, status=400)
        from django.db.models import Q
        user = User.objects.filter(Q(telephone=ident) | Q(email__iexact=ident)).first()
        if user is None:
            return Response(generic, status=200)
        try:
            extra = envoyer_otp(user, 'reset_password')
        except OtpError as e:
            return Response({"error": str(e)}, status=400)
        return Response({**generic, **extra}, status=200)


class PasswordVerifyOtpView(APIView):
    permission_classes = (permissions.AllowAny,)

    def post(self, request):
        ident = (request.data.get('telephone') or request.data.get('identifiant') or '').strip()
        code = request.data.get('code')
        from django.db.models import Q
        user = User.objects.filter(Q(telephone=ident) | Q(email__iexact=ident)).first()
        if user is None or not code or not verifier_otp(user, 'reset_password', code):
            return Response({"error": "Code invalide ou expiré"}, status=400)
        reset_token = signing.dumps({'uid': user.id}, salt=RESET_TOKEN_SALT)
        return Response({"reset_token": reset_token}, status=200)


class PasswordResetView(APIView):
    permission_classes = (permissions.AllowAny,)

    def post(self, request):
        reset_token = request.data.get('reset_token')
        new_password = request.data.get('new_password')
        if not reset_token or not new_password:
            return Response({"error": "reset_token et new_password requis"}, status=400)
        try:
            data = signing.loads(reset_token, salt=RESET_TOKEN_SALT, max_age=RESET_TOKEN_MAX_AGE)
        except signing.SignatureExpired:
            return Response({"error": "Lien expiré, recommencez la procédure."}, status=400)
        except signing.BadSignature:
            return Response({"error": "Jeton invalide."}, status=400)
        user = User.objects.filter(pk=data.get('uid')).first()
        if user is None:
            return Response({"error": "Utilisateur introuvable"}, status=404)
        try:
            validate_password(new_password, user)
        except ValidationError as e:
            return Response({"error": list(e.messages)}, status=400)
        user.set_password(new_password)
        user.save()
        _blacklister_refresh_tokens(user)
        return Response({"status": "Mot de passe réinitialisé avec succès"}, status=200)

import hashlib

from django.conf import settings
from django.contrib.auth.models import AbstractUser, BaseUserManager
from django.db import models
from django.utils import timezone
from django.utils.translation import gettext_lazy as _


class BailleurManager(BaseUserManager):
    """
    Gestionnaire du modèle utilisateur. La connexion se fait par email OU
    téléphone : au moins l'un des deux est requis à la création.
    """
    def create_user(self, email=None, password=None, telephone=None, **extra_fields):
        if not email and not telephone:
            raise ValueError(_("Un email ou un numéro de téléphone est obligatoire"))
        if email:
            email = self.normalize_email(email)
        user = self.model(email=email or None, telephone=telephone or None, **extra_fields)
        user.set_password(password)
        user.save()
        return user

    def create_superuser(self, email, password, **extra_fields):
        extra_fields.setdefault('is_staff', True)
        extra_fields.setdefault('is_superuser', True)
        extra_fields.setdefault('is_active', True)

        if extra_fields.get('is_staff') is not True:
            raise ValueError(_('Superuser doit avoir is_staff=True.'))
        if extra_fields.get('is_superuser') is not True:
            raise ValueError(_('Superuser doit avoir is_superuser=True.'))
        if not email:
            raise ValueError(_("Le superuser doit avoir un email."))
        return self.create_user(email=email, password=password, **extra_fields)


class Bailleur(AbstractUser):
    username = None
    # email et téléphone sont tous deux facultatifs mais uniques : l'utilisateur
    # peut se connecter avec l'un ou l'autre. USERNAME_FIELD reste l'email pour
    # l'admin/superuser ; la connexion applicative passe par une vue dédiée.
    email = models.EmailField(_('adresse email'), unique=True, blank=True, null=True)
    telephone = models.CharField(max_length=20, unique=True, blank=True, null=True)
    pin_securite = models.CharField(max_length=4, blank=True, null=True)
    adresse = models.CharField(max_length=255, blank=True)  # adresse du bailleur (documents légaux)
    fcm_token = models.CharField(max_length=255, blank=True, null=True)
    penalite_defaut = models.DecimalField(max_digits=10, decimal_places=2, default=5000)
    deux_fa_active = models.BooleanField(default=False)
    date_creation = models.DateTimeField(auto_now_add=True)

    USERNAME_FIELD = 'email'
    REQUIRED_FIELDS = []

    objects = BailleurManager()

    def __str__(self):
        return self.email or self.telephone or f"Bailleur #{self.pk}"


class CodeVerification(models.Model):
    """Code OTP à usage unique (2FA ou réinitialisation de mot de passe).
    Le code n'est jamais stocké en clair (haché SHA-256)."""
    TYPE_CHOICES = (
        ('2fa', 'Double authentification'),
        ('reset_password', 'Réinitialisation mot de passe'),
    )

    user = models.ForeignKey('accounts.Bailleur', on_delete=models.CASCADE, related_name='codes_verification')
    code_hash = models.CharField(max_length=128)
    type_code = models.CharField(max_length=20, choices=TYPE_CHOICES)
    expire_at = models.DateTimeField()
    tentatives = models.PositiveSmallIntegerField(default=0)
    utilise = models.BooleanField(default=False)
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        ordering = ['-created_at']

    def __str__(self):
        return f"{self.type_code} - {self.user} ({'utilisé' if self.utilise else 'actif'})"

    @staticmethod
    def hacher(code: str) -> str:
        return hashlib.sha256(str(code).encode()).hexdigest()

    @property
    def est_valide(self):
        return (not self.utilise) and self.tentatives < 3 and self.expire_at > timezone.now()

    def verifier(self, code: str) -> bool:
        """Vérifie un code saisi ; incrémente les tentatives ; invalide après 3 échecs."""
        if not self.est_valide:
            return False
        if self.code_hash == self.hacher(code):
            return True
        self.tentatives += 1
        if self.tentatives >= 3:
            self.utilise = True  # invalide le code après 3 échecs
        self.save(update_fields=['tentatives', 'utilise'])
        return False


class ConfigBailleur(models.Model):
    """Préférences du bailleur (écran Paramètres) : régional/affichage,
    notifications & rappels, défauts financiers de pré-remplissage.

    NB : le montant fixe par défaut des pénalités reste `Bailleur.penalite_defaut`
    (une seule source de vérité, déjà utilisée par le moteur de pénalités)."""
    LANGUE_CHOICES = (('fr', 'Français'), ('en', 'English'))
    THEME_CHOICES = (('clair', 'Clair'), ('sombre', 'Sombre'))
    CANAL_CHOICES = (('sms', 'SMS'), ('whatsapp', 'WhatsApp'), ('appel', 'Appel vocal'))
    TYPE_PENALITE_CHOICES = (('fixe', 'Fixe'), ('pourcentage', 'Pourcentage'))

    user = models.OneToOneField(
        settings.AUTH_USER_MODEL, on_delete=models.CASCADE, related_name='config'
    )

    # Régional & Affichage
    langue_interface = models.CharField(max_length=5, choices=LANGUE_CHOICES, default='fr')
    devise = models.CharField(max_length=10, default='FCFA')
    fuseau_horaire = models.CharField(max_length=50, default='Africa/Douala')
    format_date = models.CharField(max_length=20, default='DD/MM/YYYY')
    theme = models.CharField(max_length=10, choices=THEME_CHOICES, default='clair')
    sons_notifications = models.BooleanField(default=True)

    # Notifications & Rappels
    canal_rappel_prefere = models.CharField(max_length=20, choices=CANAL_CHOICES, default='sms')
    jours_avant_rappel = models.PositiveSmallIntegerField(default=3)
    rappels_automatiques_actifs = models.BooleanField(default=True)
    notifications_push_actives = models.BooleanField(default=True)

    # Paramètres financiers par défaut (pré-remplissent le formulaire locataire)
    # Montant fixe par défaut = Bailleur.penalite_defaut (pas de duplication).
    delai_grace_defaut = models.PositiveIntegerField(default=0)
    type_penalite_defaut = models.CharField(max_length=20, choices=TYPE_PENALITE_CHOICES, default='fixe')
    pourcentage_penalite_defaut = models.DecimalField(max_digits=5, decimal_places=2, default=0)

    updated_at = models.DateTimeField(auto_now=True)

    def __str__(self):
        return f"Config - {self.user}"

    @classmethod
    def pour(cls, user):
        """Renvoie (en créant au besoin) la config du bailleur."""
        config, _ = cls.objects.get_or_create(user=user)
        return config

"""Modèles de la vitrine d'annonces (marketplace de location) — Palier 1.

Voir LOYATRACK_MARKETPLACE_PLAN.md §9. Ce palier pose les tables ;
la logique métier riche (auto-checks de publication, strip des numéros,
synchro d'occupation, tâches) est ajoutée à l'étape 2 (`services.py`/`tasks.py`).
"""
import uuid

from django.conf import settings
from django.db import models
from django.utils import timezone
from django.utils.text import slugify

from biens.models import UniteLogement


class Ville(models.Model):
    """Ville — socle de la taxonomie de localisation pour le SEO."""
    nom = models.CharField(max_length=100)
    slug = models.SlugField(max_length=120, unique=True)
    region = models.CharField(max_length=100, blank=True)
    latitude = models.FloatField(null=True, blank=True)
    longitude = models.FloatField(null=True, blank=True)
    # Priorité d'affichage/SEO (les grandes villes d'abord).
    ordre = models.PositiveSmallIntegerField(default=100)

    class Meta:
        ordering = ['ordre', 'nom']

    def save(self, *args, **kwargs):
        if not self.slug:
            self.slug = slugify(self.nom)
        super().save(*args, **kwargs)

    def __str__(self):
        return self.nom


class Quartier(models.Model):
    """Quartier rattaché à une ville (ex. Bonamoussadi → Douala)."""
    ville = models.ForeignKey(Ville, on_delete=models.CASCADE, related_name='quartiers')
    nom = models.CharField(max_length=100)
    slug = models.SlugField(max_length=120)

    class Meta:
        ordering = ['nom']
        unique_together = (('ville', 'slug'),)

    def save(self, *args, **kwargs):
        if not self.slug:
            self.slug = slugify(self.nom)
        super().save(*args, **kwargs)

    def __str__(self):
        return f"{self.nom} ({self.ville.nom})"


class Annonce(models.Model):
    """Annonce publique de location, adossée à une unité (vacante) du bailleur.

    Scopée `bailleur` côté gestion ; le public ne voit que `statut='publiee'`
    non expirées. Une annonce vient de préférence d'une `UniteLogement`
    (pré-remplissage + dépublication auto à la re-location), mais `unite` reste
    facultatif pour autoriser une annonce autonome.
    """
    TYPE_CHOICES = (
        ('appartement', 'Appartement'),
        ('villa', 'Villa'),
        ('studio', 'Studio'),
        ('chambre', 'Chambre'),
        ('immeuble', 'Immeuble'),
        ('bureau', 'Bureau'),
        ('autre', 'Autre'),
    )
    STANDING_CHOICES = (
        ('economique', 'Économique'),
        ('moyen', 'Moyen standing'),
        ('haut', 'Haut standing'),
    )
    STATUT_CHOICES = (
        ('brouillon', 'Brouillon'),
        ('en_moderation', 'En modération'),   # réservé au Palier 3 (découvrabilité publique)
        ('publiee', 'Publiée'),
        ('suspendue', 'Suspendue'),
        ('pourvue', 'Pourvue'),               # logement trouvé / unité re-louée
        ('expiree', 'Expirée'),
    )

    # ── Rattachement ─────────────────────────────────────────────────────────
    bailleur = models.ForeignKey(
        settings.AUTH_USER_MODEL, on_delete=models.CASCADE, related_name='annonces')
    unite = models.ForeignKey(
        UniteLogement, on_delete=models.SET_NULL, null=True, blank=True,
        related_name='annonces')
    reference = models.CharField(max_length=12, unique=True, editable=False)
    slug = models.SlugField(max_length=180, unique=True, editable=False)

    # ── Caractéristiques ─────────────────────────────────────────────────────
    type_bien = models.CharField(max_length=20, choices=TYPE_CHOICES, default='appartement')
    nb_chambres = models.PositiveSmallIntegerField(default=1)
    nb_salons = models.PositiveSmallIntegerField(default=1)
    nb_cuisines = models.PositiveSmallIntegerField(default=1)
    nb_douches = models.PositiveSmallIntegerField(default=1)
    superficie_m2 = models.PositiveIntegerField(null=True, blank=True)
    meuble = models.BooleanField(default=False)
    standing = models.CharField(max_length=12, choices=STANDING_CHOICES, blank=True)

    # ── Localisation (jamais l'adresse exacte côté public) ───────────────────
    # `ville` nullable pour autoriser un brouillon incomplet (ex. créé « depuis
    # une unité » qui n'en connaît pas la ville) ; obligatoire à la publication.
    ville = models.ForeignKey(
        Ville, on_delete=models.PROTECT, null=True, blank=True, related_name='annonces')
    quartier = models.ForeignKey(
        Quartier, on_delete=models.SET_NULL, null=True, blank=True, related_name='annonces')
    adresse_indicative = models.CharField(max_length=255, blank=True)

    # ── Prix (FCFA) ──────────────────────────────────────────────────────────
    loyer = models.DecimalField(max_digits=10, decimal_places=2, default=0)
    charges = models.DecimalField(max_digits=10, decimal_places=2, default=0)
    caution_mois = models.PositiveSmallIntegerField(default=1)

    # ── Contenu ──────────────────────────────────────────────────────────────
    titre = models.CharField(max_length=150)
    description = models.TextField(blank=True)
    disponible_le = models.DateField(null=True, blank=True)  # null → disponible immédiatement

    # ── Cycle de vie ─────────────────────────────────────────────────────────
    statut = models.CharField(max_length=14, choices=STATUT_CHOICES, default='brouillon')
    refus_motif = models.TextField(blank=True)
    date_publication = models.DateTimeField(null=True, blank=True)
    date_expiration = models.DateTimeField(null=True, blank=True)

    # ── Signaux ──────────────────────────────────────────────────────────────
    nb_vues = models.PositiveIntegerField(default=0)
    nb_contacts = models.PositiveIntegerField(default=0)   # alimenté au Palier 3

    date_creation = models.DateTimeField(auto_now_add=True)
    date_maj = models.DateTimeField(auto_now=True)

    class Meta:
        ordering = ['-date_creation', '-id']
        indexes = [
            models.Index(fields=['ville', 'quartier', 'type_bien', 'nb_chambres', 'statut']),
            models.Index(fields=['statut', 'date_expiration']),
        ]

    def save(self, *args, **kwargs):
        if not self.reference:
            self.reference = self._nouvelle_reference()
        if not self.slug:
            self.slug = self._nouveau_slug()
        super().save(*args, **kwargs)

    @staticmethod
    def _nouvelle_reference():
        """Référence publique courte et unique (ex. `LT-4F2A`)."""
        while True:
            ref = f"LT-{uuid.uuid4().hex[:4].upper()}"
            if not Annonce.objects.filter(reference=ref).exists():
                return ref

    def _nouveau_slug(self):
        """Slug SEO : type + chambres + quartier + ville + référence (unique).

        On inclut quartier ET ville (ex. « …-bonamoussadi-douala-… ») pour coller
        aux requêtes du type « appartement 2 chambres bonamoussadi douala »."""
        parties = [self.type_bien, f"{self.nb_chambres}-chambres"]
        if self.quartier_id:
            parties.append(self.quartier.slug)
        if self.ville_id:
            parties.append(self.ville.slug)
        base = slugify('-'.join(parties))
        ref = (self.reference or self._nouvelle_reference()).lower().replace('-', '')
        candidat = f"{base}-{ref}" if base else ref
        # `reference` est déjà unique → le slug l'est de facto ; garde-fou par sécurité.
        slug, i = candidat, 2
        while Annonce.objects.filter(slug=slug).exclude(pk=self.pk).exists():
            slug = f"{candidat}-{i}"
            i += 1
        return slug

    @property
    def est_visible(self):
        """Visible publiquement = publiée et non expirée."""
        return (self.statut == 'publiee'
                and self.date_expiration is not None
                and self.date_expiration > timezone.now())

    @property
    def photo_couverture(self):
        """Photo de couverture (marquée, sinon la première). Utiliser
        prefetch_related('photos') pour éviter les requêtes N+1."""
        photos = list(self.photos.all())
        if not photos:
            return None
        return next((p for p in photos if p.est_couverture), photos[0])

    def __str__(self):
        return f"{self.titre} [{self.reference} · {self.statut}]"


class PhotoAnnonce(models.Model):
    """Photo rattachée à une annonce (≥1 requise pour publier, cf. étape 2)."""
    annonce = models.ForeignKey(Annonce, on_delete=models.CASCADE, related_name='photos')
    image = models.ImageField(upload_to='annonces/%Y/%m/')
    ordre = models.PositiveSmallIntegerField(default=0)
    est_couverture = models.BooleanField(default=False)
    date_creation = models.DateTimeField(auto_now_add=True)

    class Meta:
        ordering = ['ordre', 'id']

    def __str__(self):
        return f"Photo #{self.ordre} — {self.annonce.reference}"

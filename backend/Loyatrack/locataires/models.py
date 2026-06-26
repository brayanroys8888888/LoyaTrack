from django.db import models
from django.conf import settings

class Locataire(models.Model):
    STATUT_CHOICES = (
        ('Payé', 'Payé'),
        ('En retard', 'En retard'),
        ('En discussion', 'En discussion'),
        ('En pénalité', 'En pénalité'),
    )

    bailleur = models.ForeignKey(settings.AUTH_USER_MODEL, on_delete=models.CASCADE, related_name='locataires')
    nom = models.CharField(max_length=150)
    prenom = models.CharField(max_length=150)
    telephone = models.CharField(max_length=20)
    logement = models.CharField(max_length=100, blank=True, null=True)
    unite = models.ForeignKey(
        'biens.UniteLogement', on_delete=models.SET_NULL,
        related_name='locataires', null=True, blank=True,
    )

    montant_loyer = models.DecimalField(max_digits=10, decimal_places=2)
    jour_echeance = models.IntegerField() # 1 to 31
    statut = models.CharField(max_length=20, choices=STATUT_CHOICES, default='Payé')
    date_entree = models.DateField()

    # --- Données pour documents légaux (Loi camerounaise 2014/023) ---
    FREQUENCE_CHOICES = (
        ('mensuel', 'Mensuel'),
        ('trimestriel', 'Trimestriel'),
        ('semestriel', 'Semestriel'),
        ('annuel', 'Annuel'),
    )
    adresse_logement = models.CharField(max_length=255, blank=True)
    charges_mensuelles = models.DecimalField(max_digits=10, decimal_places=2, default=0)
    duree_bail_mois = models.PositiveIntegerField(default=12)
    frequence_paiement = models.CharField(max_length=20, choices=FREQUENCE_CHOICES, default='mensuel')

    # Langue du locataire : détermine la langue des rappels SMS/WhatsApp/appel (module Paramètres 6.1)
    LANGUE_CHOICES = (('fr', 'Français'), ('en', 'English'))
    langue_preferee = models.CharField(max_length=5, choices=LANGUE_CHOICES, default='fr')
    
    penalite_journaliere = models.DecimalField(max_digits=10, decimal_places=2, null=True, blank=True)
    total_penalites = models.DecimalField(max_digits=10, decimal_places=2, default=0)
    
    notes = models.TextField(blank=True)
    # Signature manuscrite du locataire (image PNG encodée en base64)
    signature_base64 = models.TextField(blank=True, null=True)
    is_deleted = models.BooleanField(default=False)

    # --- Infos personnelles enrichies (2.3) ---
    PIECE_CHOICES = (
        ('CNI', "Carte Nationale d'Identité"),
        ('Passeport', 'Passeport'),
        ('Permis', 'Permis de conduire'),
    )
    profession = models.CharField(max_length=150, blank=True)
    revenus_mensuels = models.DecimalField(max_digits=12, decimal_places=2, null=True, blank=True)
    type_piece_identite = models.CharField(max_length=20, choices=PIECE_CHOICES, blank=True)
    numero_piece_identite = models.CharField(max_length=100, blank=True)
    piece_identite = models.FileField(upload_to='pieces_identite/', null=True, blank=True)

    # --- Caution (3.2) ---
    CAUTION_CHOICES = (
        ('non_versee', 'Non versée'),
        ('versee', 'Versée'),
        ('restituee_totale', 'Restituée (totale)'),
        ('restituee_partielle', 'Restituée (partielle)'),
        ('conservee', 'Conservée'),
    )
    montant_caution = models.DecimalField(max_digits=10, decimal_places=2, default=0)
    date_versement_caution = models.DateField(null=True, blank=True)
    statut_caution = models.CharField(max_length=20, choices=CAUTION_CHOICES, default='non_versee')

    # --- Migration / facturation (2.4) ---
    solde_initial = models.DecimalField(max_digits=12, decimal_places=2, default=0)
    date_debut_facturation = models.DateField(null=True, blank=True)

    # --- Fin de bail / résiliation (2.7) ---
    archive = models.BooleanField(default=False)
    date_sortie = models.DateField(null=True, blank=True)
    motif_sortie = models.TextField(blank=True)
    date_fin_bail = models.DateField(null=True, blank=True)

    # Mode Test : cycle rapide en secondes
    mode_test = models.BooleanField(default=False)
    test_debut = models.DateTimeField(null=True, blank=True)

    def __str__(self):
        return f"{self.prenom} {self.nom}"

    @property
    def get_penalite_journaliere(self):
        if self.penalite_journaliere is not None:
            return self.penalite_journaliere
        return self.bailleur.penalite_defaut


class PieceIdentiteFichier(models.Model):
    """Fichier de pièce d'identité (recto / verso / PDF). Plusieurs par locataire :
    un document d'identité peut comporter plusieurs faces, ou être un seul PDF.
    Le champ legacy ``Locataire.piece_identite`` reste pour compatibilité."""
    locataire = models.ForeignKey(
        Locataire, on_delete=models.CASCADE, related_name='pieces_identite')
    fichier = models.FileField(upload_to='pieces_identite/')
    libelle = models.CharField(max_length=50, blank=True)  # ex : Recto, Verso
    date_ajout = models.DateTimeField(auto_now_add=True)

    class Meta:
        ordering = ['date_ajout']

    def __str__(self):
        return f"Pièce {self.libelle or self.pk} - {self.locataire}"


class Rappel(models.Model):
    TYPE_CHOICES = (
        ('SMS', 'SMS'),
        ('WhatsApp', 'WhatsApp'),
        ('Appel', 'Appel Vocal'),
    )
    STATUT_CHOICES = (
        ('Envoyé', 'Envoyé'),
        ('Echoué', 'Echoué'),
    )

    locataire = models.ForeignKey(Locataire, on_delete=models.CASCADE, related_name='rappels')
    type_rappel = models.CharField(max_length=10, choices=TYPE_CHOICES)
    date_envoi = models.DateTimeField(auto_now_add=True)
    statut = models.CharField(max_length=10, choices=STATUT_CHOICES)
    reponse_api = models.JSONField(blank=True, null=True)

    # --- Suivi de livraison via webhook Twilio (2.6) ---
    message_sid = models.CharField(max_length=64, blank=True, db_index=True)
    statut_livraison = models.CharField(max_length=20, blank=True)  # queued/sent/delivered/read/failed/undelivered
    date_livraison = models.DateTimeField(null=True, blank=True)

    def __str__(self):
        return f"Rappel {self.type_rappel} - {self.locataire}"

class Notification(models.Model):
    TYPE_NOTIF_CHOICES = (
        ('paiement', 'Paiement'),
        ('retard', 'Retard'),
        ('penalite', 'Pénalité'),
        ('rappel', 'Rappel'),
        ('systeme', 'Système'),
        ('discussion', 'Discussion'),
    )
    
    locataire = models.ForeignKey(Locataire, on_delete=models.CASCADE, related_name='notifications', blank=True, null=True)
    bailleur = models.ForeignKey(settings.AUTH_USER_MODEL, on_delete=models.CASCADE, related_name='notifications')
    titre = models.CharField(max_length=200)
    corps = models.TextField()
    type_notif = models.CharField(max_length=20, choices=TYPE_NOTIF_CHOICES, default='systeme')
    date_creation = models.DateTimeField(auto_now_add=True)
    lue = models.BooleanField(default=False)

    def __str__(self):
        return f"{self.type_notif}: {self.titre}"

    class Meta:
        ordering = ['-date_creation']


class HistoriqueLoyer(models.Model):
    """Historique des montants de loyer (révisions / augmentations) — module 3.3."""
    locataire = models.ForeignKey(Locataire, on_delete=models.CASCADE, related_name='historique_loyers')
    montant = models.DecimalField(max_digits=10, decimal_places=2)
    date_debut = models.DateField()
    date_fin = models.DateField(null=True, blank=True)
    motif = models.CharField(max_length=255, blank=True)
    applique = models.BooleanField(default=False)
    date_creation = models.DateTimeField(auto_now_add=True)

    class Meta:
        ordering = ['-date_debut']

    def __str__(self):
        return f"Loyer {self.montant} dès {self.date_debut} - {self.locataire}"


class MouvementCaution(models.Model):
    """Mouvements de caution : versement, restitution, déduction — module 3.2."""
    TYPE_CHOICES = (
        ('versement', 'Versement'),
        ('restitution', 'Restitution'),
        ('deduction', 'Déduction'),
    )
    locataire = models.ForeignKey(Locataire, on_delete=models.CASCADE, related_name='mouvements_caution')
    type_mouvement = models.CharField(max_length=15, choices=TYPE_CHOICES)
    montant = models.DecimalField(max_digits=10, decimal_places=2)
    date = models.DateField()
    motif = models.TextField(blank=True)
    date_creation = models.DateTimeField(auto_now_add=True)

    class Meta:
        ordering = ['-date']

    def __str__(self):
        return f"{self.type_mouvement} {self.montant} - {self.locataire}"


class EtatDesLieux(models.Model):
    """État des lieux d'entrée ou de sortie — module 3.1."""
    TYPE_CHOICES = (
        ('entree', 'Entrée'),
        ('sortie', 'Sortie'),
    )
    locataire = models.ForeignKey(Locataire, on_delete=models.CASCADE, related_name='etats_des_lieux')
    type_etat = models.CharField(max_length=10, choices=TYPE_CHOICES)
    date = models.DateField()
    observations = models.TextField(blank=True)
    signature_bailleur_base64 = models.TextField(blank=True, null=True)
    signature_locataire_base64 = models.TextField(blank=True, null=True)
    date_creation = models.DateTimeField(auto_now_add=True)

    class Meta:
        ordering = ['-date']

    def __str__(self):
        return f"État des lieux ({self.type_etat}) - {self.locataire}"


class PhotoEtatDesLieux(models.Model):
    etat = models.ForeignKey(EtatDesLieux, on_delete=models.CASCADE, related_name='photos')
    piece = models.CharField(max_length=100)
    description = models.TextField(blank=True)
    photo = models.ImageField(upload_to='etats_des_lieux/')
    horodatage = models.DateTimeField(auto_now_add=True)

    def __str__(self):
        return f"Photo {self.piece} - {self.etat}"

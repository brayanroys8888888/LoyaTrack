"""Crée des biens + unités et publie des annonces de démonstration.

Les photos proviennent du dossier « photo appartement/ » à la racine du repo
(surchargeable via --dir). Idempotent : relance = réinitialise les données démo.

Usage : python manage.py seed_demo_annonces
"""
import os
from decimal import Decimal

from django.conf import settings
from django.contrib.auth import get_user_model
from django.core.files import File
from django.core.management.base import BaseCommand, CommandError

from biens.models import Propriete, UniteLogement
from annonces.models import Ville, Quartier, Annonce, PhotoAnnonce
from annonces import services

# (propriété, ville d'affichage, type de propriété)
PROPRIETES = {
    'Résidence Les Palmiers': ('Douala', 'immeuble'),
    'Immeuble Akwa Center': ('Douala', 'immeuble'),
    'Villa Bonapriso': ('Douala', 'villa'),
    'Résidence Bastos': ('Yaoundé', 'immeuble'),
    'Complexe Makepe': ('Douala', 'immeuble'),
}

# Annonces (chaque unité → une annonce publiée).
DEMO = [
    dict(propriete='Résidence Les Palmiers', unite='Appt A2', titre="Bel appartement 2 chambres à Bonamoussadi",
         type='appartement', ville='douala', quartier='bonamoussadi', ch=2, sal=1, db=1, m2=75,
         meuble=True, loyer=120000, charges=10000, caution=2, repere="près du carrefour Bonamoussadi",
         desc="Appartement lumineux et bien aéré, 2 chambres spacieuses, salon moderne, cuisine équipée. Quartier calme, proche commodités (marché, écoles, transport).", nphotos=3),
    dict(propriete='Résidence Les Palmiers', unite='Studio S1', titre="Studio meublé à Bonamoussadi",
         type='studio', ville='douala', quartier='bonamoussadi', ch=1, sal=1, db=1, m2=30,
         meuble=True, loyer=65000, charges=5000, caution=2, repere="",
         desc="Studio meublé propre et fonctionnel, idéal pour jeune actif ou étudiant. Eau et électricité, sécurité 24h.", nphotos=2),
    dict(propriete='Immeuble Akwa Center', unite='Appt 3B', titre="Appartement 3 chambres à Akwa",
         type='appartement', ville='douala', quartier='akwa', ch=3, sal=2, db=2, m2=120,
         meuble=False, loyer=250000, charges=20000, caution=3, repere="centre-ville, proche des banques",
         desc="Grand appartement en plein centre d'Akwa, 3 chambres, double salon, 2 douches. Parfait pour famille ou colocation haut standing.", nphotos=3),
    dict(propriete='Villa Bonapriso', unite='Villa', titre="Villa 4 chambres avec cour à Bonapriso",
         type='villa', ville='douala', quartier='bonapriso', ch=4, sal=2, db=3, m2=250,
         meuble=False, loyer=550000, charges=0, caution=3, repere="quartier résidentiel Bonapriso",
         desc="Superbe villa dans le quartier chic de Bonapriso : 4 chambres, grand séjour, cuisine américaine, cour clôturée et parking. Standing élevé, environnement sécurisé.", nphotos=3),
    dict(propriete='Résidence Bastos', unite='Appt B1', titre="Appartement 2 chambres à Bastos, Yaoundé",
         type='appartement', ville='yaounde', quartier='bastos', ch=2, sal=1, db=1, m2=85,
         meuble=True, loyer=180000, charges=15000, caution=2, repere="proche des ambassades",
         desc="Appartement meublé de standing à Bastos, quartier diplomatique de Yaoundé. 2 chambres, finitions modernes, très sécurisé.", nphotos=2),
    dict(propriete='Résidence Bastos', unite='Studio B2', titre="Studio moderne à Bastos",
         type='studio', ville='yaounde', quartier='bastos', ch=1, sal=1, db=1, m2=35,
         meuble=True, loyer=90000, charges=8000, caution=2, repere="",
         desc="Joli studio meublé à Bastos, calme et bien situé. Idéal expatrié ou professionnel.", nphotos=2),
    dict(propriete='Complexe Makepe', unite='Chambre C4', titre="Chambre moderne à Makepe",
         type='chambre', ville='douala', quartier='makepe', ch=1, sal=0, db=1, m2=18,
         meuble=True, loyer=40000, charges=3000, caution=1, repere="Makepe Missoke",
         desc="Chambre moderne meublée avec douche interne, dans une résidence sécurisée à Makepe. Eau et courant inclus.", nphotos=2),
    dict(propriete='Complexe Makepe', unite='Appt M2', titre="Appartement 2 chambres à Makepe",
         type='appartement', ville='douala', quartier='makepe', ch=2, sal=1, db=1, m2=70,
         meuble=False, loyer=95000, charges=8000, caution=2, repere="",
         desc="Appartement 2 chambres bien entretenu à Makepe, quartier dynamique et accessible. Bon rapport qualité-prix.", nphotos=3),
]


class Command(BaseCommand):
    help = "Crée des biens/unités et publie des annonces de démonstration (photos depuis 'photo appartement/')."

    def add_arguments(self, parser):
        parser.add_argument('--dir', default=None, help="Dossier des photos")
        parser.add_argument('--bailleur', default=None, help="Email du bailleur (défaut : le premier)")

    def handle(self, *args, **opt):
        User = get_user_model()
        if opt['bailleur']:
            bailleur = User.objects.filter(email=opt['bailleur']).first()
            if not bailleur:
                raise CommandError(f"Aucun bailleur avec l'email {opt['bailleur']}")
        else:
            bailleur = User.objects.order_by('id').first()
        if not bailleur:
            raise CommandError("Aucun bailleur en base. Créez un compte d'abord.")

        images_dir = opt['dir'] or os.path.join(settings.BASE_DIR.parent.parent, 'photo appartement')
        if not os.path.isdir(images_dir):
            raise CommandError(f"Dossier d'images introuvable : {images_dir}")
        images = sorted(f for f in os.listdir(images_dir)
                        if f.lower().endswith(('.jpg', '.jpeg', '.png', '.webp')))
        if not images:
            raise CommandError(f"Aucune image dans {images_dir}")

        # Réinitialisation des données démo précédentes.
        Annonce.objects.filter(bailleur=bailleur, titre__in=[d['titre'] for d in DEMO]).delete()
        Propriete.objects.filter(bailleur=bailleur, titre__in=list(PROPRIETES)).delete()

        img_i = 0
        for d in DEMO:
            ville_aff, prop_type = PROPRIETES[d['propriete']]
            prop, _ = Propriete.objects.get_or_create(
                bailleur=bailleur, titre=d['propriete'],
                defaults={'type': prop_type, 'adresse': ville_aff})
            unite = UniteLogement.objects.create(
                propriete=prop, numero=d['unite'], loyer_standard=Decimal(d['loyer']))
            ville = Ville.objects.get(slug=d['ville'])
            quartier = Quartier.objects.get(ville=ville, slug=d['quartier'])
            annonce = Annonce.objects.create(
                bailleur=bailleur, unite=unite, ville=ville, quartier=quartier,
                titre=d['titre'], type_bien=d['type'], nb_chambres=d['ch'],
                nb_salons=d['sal'], nb_douches=d['db'], superficie_m2=d['m2'],
                meuble=d['meuble'], loyer=Decimal(d['loyer']), charges=Decimal(d['charges']),
                caution_mois=d['caution'], adresse_indicative=d['repere'], description=d['desc'])
            for k in range(d['nphotos']):
                fname = images[img_i % len(images)]
                img_i += 1
                with open(os.path.join(images_dir, fname), 'rb') as fh:
                    PhotoAnnonce.objects.create(
                        annonce=annonce, image=File(fh, name=f"demo-{annonce.reference}-{k}.jpg"),
                        est_couverture=(k == 0), ordre=k)
            services.publier(annonce)
            self.stdout.write(f"  - {annonce.titre} ({annonce.reference})")

        self.stdout.write(self.style.SUCCESS(
            f"{len(DEMO)} annonces publiées pour {bailleur.email or bailleur.telephone}."))

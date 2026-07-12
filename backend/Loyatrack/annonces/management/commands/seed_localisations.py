"""Amorce la taxonomie de localisation (villes + quartiers) pour la vitrine.

Idempotent (`get_or_create`) : relançable sans créer de doublons.
Étendre au fil de l'eau ; un quartier absent sera proposé à la modération
(Palier 3) plutôt que saisi en texte libre non indexable.

Usage : python manage.py seed_localisations
"""
from django.core.management.base import BaseCommand
from django.utils.text import slugify

from annonces.models import Ville, Quartier

# ville_slug : (nom, region, ordre, [quartiers…])
LOCALISATIONS = {
    'douala': ('Douala', 'Littoral', 1, [
        'Akwa', 'Bonanjo', 'Bonapriso', 'Bonamoussadi', 'Makepe', 'Bonabéri',
        'Bépanda', 'Deido', 'New Bell', 'Ndokotti', 'Logbessou', 'Kotto',
        'Logpom', 'PK', 'Village', 'Bali', 'Cité des Palmiers', 'Yassa',
    ]),
    'yaounde': ('Yaoundé', 'Centre', 2, [
        'Bastos', 'Biyem-Assi', 'Mvan', 'Nsam', 'Mvog-Mbi', 'Mvog-Ada',
        'Essos', 'Nlongkak', 'Mendong', 'Odza', 'Ngousso', 'Emana',
        'Nkolbisson', 'Etoudi', 'Ekounou', 'Mimboman', 'Damas',
    ]),
    'bafoussam': ('Bafoussam', 'Ouest', 3, [
        'Tamdja', 'Kamkop', 'Djeleng', 'Tougang', 'Banengo',
    ]),
    'bamenda': ('Bamenda', 'Nord-Ouest', 4, [
        'Commercial Avenue', 'Nkwen', 'Bambili', 'Up Station', 'Mankon',
    ]),
    'kribi': ('Kribi', 'Sud', 5, [
        'Dombe', 'Afan-Mabé', 'Talla', 'Mpangou',
    ]),
    'limbe': ('Limbé', 'Sud-Ouest', 6, [
        'Down Beach', 'Mile 4', 'Bota', 'Church Street',
    ]),
    'garoua': ('Garoua', 'Nord', 7, [
        'Roumdé Adjia', 'Poumpoumré', 'Djamboutou',
    ]),
    'ngaoundere': ('Ngaoundéré', 'Adamaoua', 8, [
        'Baladji', 'Dang', 'Burkina',
    ]),
}


class Command(BaseCommand):
    help = "Amorce les villes et quartiers du Cameroun pour la vitrine d'annonces."

    def handle(self, *args, **options):
        villes_creees = quartiers_crees = 0
        for slug, (nom, region, ordre, quartiers) in LOCALISATIONS.items():
            ville, cree = Ville.objects.get_or_create(
                slug=slug, defaults={'nom': nom, 'region': region, 'ordre': ordre})
            if cree:
                villes_creees += 1
            for q_nom in quartiers:
                _, q_cree = Quartier.objects.get_or_create(
                    ville=ville, slug=slugify(q_nom), defaults={'nom': q_nom})
                if q_cree:
                    quartiers_crees += 1
        self.stdout.write(self.style.SUCCESS(
            f"Localisations à jour : {villes_creees} ville(s) et "
            f"{quartiers_crees} quartier(s) ajoutés."))

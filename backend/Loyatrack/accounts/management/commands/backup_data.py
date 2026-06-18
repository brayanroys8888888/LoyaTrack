import os
from datetime import datetime

from django.conf import settings
from django.core.management import call_command
from django.core.management.base import BaseCommand


class Command(BaseCommand):
    help = "Sauvegarde les données de l'application (dumpdata JSON) dans backups/."

    def add_arguments(self, parser):
        parser.add_argument('--dossier', type=str, default=None, help='Dossier de destination')

    def handle(self, *args, **options):
        dossier = options['dossier'] or os.path.join(settings.BASE_DIR, 'backups')
        os.makedirs(dossier, exist_ok=True)
        nom = f"backup_{datetime.now():%Y%m%d_%H%M%S}.json"
        chemin = os.path.join(dossier, nom)
        with open(chemin, 'w', encoding='utf-8') as f:
            call_command('dumpdata', '--natural-foreign', '--natural-primary',
                         '--exclude', 'contenttypes', '--exclude', 'auth.permission',
                         '--indent', '2', stdout=f)
        self.stdout.write(self.style.SUCCESS(f"Sauvegarde créée : {chemin}"))

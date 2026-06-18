from django.core.management.base import BaseCommand, CommandError
from django.contrib.auth import get_user_model

from locataires.import_service import importer_locataires

User = get_user_model()


class Command(BaseCommand):
    help = "Importe des locataires depuis un fichier CSV/Excel pour un bailleur donné."

    def add_arguments(self, parser):
        parser.add_argument('fichier', type=str, help='Chemin du fichier CSV ou XLSX')
        parser.add_argument('--bailleur', type=str, required=True, help='Email du bailleur')
        parser.add_argument('--dry-run', action='store_true', help='Valider sans créer')

    def handle(self, *args, **options):
        try:
            bailleur = User.objects.get(email=options['bailleur'])
        except User.DoesNotExist:
            raise CommandError(f"Bailleur introuvable : {options['bailleur']}")

        with open(options['fichier'], 'rb') as f:
            contenu = f.read()

        res = importer_locataires(bailleur, contenu, options['fichier'], dry_run=options['dry_run'])
        self.stdout.write(self.style.SUCCESS(f"{res['crees']} locataire(s) {'validé(s)' if options['dry_run'] else 'créé(s)'}"))
        for err in res['erreurs']:
            self.stdout.write(self.style.WARNING(f"  Ligne {err['ligne']} : {err['message']}"))

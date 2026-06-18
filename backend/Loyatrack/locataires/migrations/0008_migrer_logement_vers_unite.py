from django.db import migrations


def migrer_logements(apps, schema_editor):
    """Crée une propriété par défaut + une unité par logement texte existant,
    et rattache chaque locataire à son unité."""
    Locataire = apps.get_model('locataires', 'Locataire')
    Propriete = apps.get_model('biens', 'Propriete')
    UniteLogement = apps.get_model('biens', 'UniteLogement')

    locataires = Locataire.objects.filter(is_deleted=False, unite__isnull=True)
    proprietes_par_bailleur = {}

    for loc in locataires:
        numero = (loc.logement or '').strip() or 'Logement sans numéro'

        prop = proprietes_par_bailleur.get(loc.bailleur_id)
        if prop is None:
            prop, _ = Propriete.objects.get_or_create(
                bailleur_id=loc.bailleur_id,
                titre='Mon parc immobilier',
                defaults={'type': 'immeuble', 'adresse': ''},
            )
            proprietes_par_bailleur[loc.bailleur_id] = prop

        unite, _ = UniteLogement.objects.get_or_create(
            propriete=prop,
            numero=numero,
            defaults={'loyer_standard': loc.montant_loyer, 'statut': 'occupe'},
        )
        unite.statut = 'occupe'
        unite.save()

        loc.unite = unite
        loc.save(update_fields=['unite'])


def annuler(apps, schema_editor):
    Locataire = apps.get_model('locataires', 'Locataire')
    Locataire.objects.update(unite=None)


class Migration(migrations.Migration):

    dependencies = [
        ('locataires', '0007_locataire_unite'),
        ('biens', '0001_initial'),
    ]

    operations = [
        migrations.RunPython(migrer_logements, annuler),
    ]

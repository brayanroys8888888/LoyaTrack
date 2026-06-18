"""Bascule payante : les bailleurs existants reçoivent un Pro de courtoisie d'1 mois
(geste commercial), au lieu d'un simple essai. Idempotent (skip si abonnement déjà là)."""
from datetime import timedelta

from django.db import migrations
from django.utils import timezone

COURTOISIE_JOURS = 30


def octroyer_courtoisie(apps, schema_editor):
    Bailleur = apps.get_model('accounts', 'Bailleur')
    Abonnement = apps.get_model('abonnements', 'Abonnement')
    now = timezone.now()
    for b in Bailleur.objects.filter(is_staff=False):
        if Abonnement.objects.filter(bailleur=b).exists():
            continue
        Abonnement.objects.create(
            bailleur=b,
            plan='pro',
            statut='actif',
            date_fin=now + timedelta(days=COURTOISIE_JOURS),
        )


def reculer(apps, schema_editor):
    # Pas de rollback de données (on ne supprime pas les abonnements créés).
    pass


class Migration(migrations.Migration):

    dependencies = [
        ('abonnements', '0001_initial'),
    ]

    operations = [
        migrations.RunPython(octroyer_courtoisie, reculer),
    ]

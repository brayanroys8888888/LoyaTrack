"""Crée automatiquement un essai 14 j à l'inscription d'un bailleur."""
from django.conf import settings
from django.db.models.signals import post_save
from django.dispatch import receiver

from . import services


@receiver(post_save, sender=settings.AUTH_USER_MODEL)
def creer_abonnement_essai(sender, instance, created, **kwargs):
    if not created:
        return
    # Les superusers/staff n'ont pas besoin d'abonnement (mais ne plante pas si créé).
    if instance.is_staff:
        return
    if getattr(instance, 'abonnement', None) is None:
        services.creer_essai(instance)

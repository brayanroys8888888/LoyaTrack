"""Sélection du prestataire de paiement (agnostique).

En dev/test : FakeProvider. CinetPay (ou autre) s'ajoutera ici en Phase 3 sans
toucher au reste du code (services/views).
"""
from django.conf import settings

from .fake import FakeProvider
from .cinetpay import CinetPayProvider

_PROVIDERS = {
    'fake': FakeProvider,
    'cinetpay': CinetPayProvider,
}


def get_provider():
    nom = getattr(settings, 'PAIEMENT_PROVIDER', 'fake')
    return _PROVIDERS.get(nom, FakeProvider)()

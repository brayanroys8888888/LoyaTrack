"""Prestataire factice pour le développement et les tests.

`creer_paiement` renvoie une URL de retour locale ; le webhook attend
{"reference": <uuid>, "statut": "reussi"}. Aucune signature.
"""
from .base import PaiementProvider


class FakeProvider(PaiementProvider):
    nom = 'fake'

    def creer_paiement(self, transaction, return_url=None):
        return f"/abonnement/checkout/fake/?ref={transaction.reference_interne}"

    def parse_webhook(self, request):
        data = getattr(request, 'data', {}) or {}
        reference = data.get('reference')
        statut = data.get('statut', 'reussi')
        return reference, statut, dict(data)

    def verifier_signature(self, request):
        return True

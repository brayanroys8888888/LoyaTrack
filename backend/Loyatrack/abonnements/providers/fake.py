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

    def creer_paiement_generique(self, *, reference, montant, devise,
                                 description, return_url, notify_url, credentials):
        return f"/paiements/demande/fake/?ref={reference}&montant={int(montant)}"

    def verifier_paiement(self, reference, credentials):
        return True

    def effectuer_transfert(self, *, reference, montant, devise, numero, operateur):
        # Reversement simulé : toujours réussi (pour les tests).
        return True, f"FAKE-TRANSFER-{reference}", ''

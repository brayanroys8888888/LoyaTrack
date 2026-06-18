"""Interface commune des prestataires de paiement."""


class PaiementProvider:
    nom = 'base'

    def creer_paiement(self, transaction, return_url=None):
        """Initialise le paiement côté prestataire et renvoie l'URL de redirection web."""
        raise NotImplementedError

    def parse_webhook(self, request):
        """Extrait (reference, statut, payload) d'une requête webhook.

        `reference` correspond à `TransactionAbonnement.reference_interne`.
        `statut` ∈ {'reussi','echoue','annule','en_attente'}.
        """
        raise NotImplementedError

    def verifier_signature(self, request):
        """Vérifie l'authenticité du webhook. À surcharger par chaque prestataire réel."""
        return True

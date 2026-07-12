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

    # ── Encaissement générique (hors abonnement : loyers) ────────────────────
    # `credentials` = identifiants marchands du bénéficiaire (mode « compte
    # direct » : chaque bailleur encaisse sur son propre compte).
    def creer_paiement_generique(self, *, reference, montant, devise,
                                 description, return_url, notify_url, credentials):
        """Initialise un paiement arbitraire côté prestataire → URL de redirection."""
        raise NotImplementedError

    def verifier_paiement(self, reference, credentials):
        """Revérifie l'état réel d'une transaction via l'API du prestataire → bool."""
        raise NotImplementedError

    def effectuer_transfert(self, *, reference, montant, devise, numero, operateur):
        """Reverse `montant` vers le numéro Mobile Money du bénéficiaire (bailleur).

        Mode « encaissement centralisé » : le débit part du compte plateforme
        LoyaTrack (settings.CINETPAY_*), pas d'un compte par bailleur.
        Renvoie un triplet (ok: bool, ref: str, erreur: str).
        """
        raise NotImplementedError

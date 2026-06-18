"""Prestataire CinetPay (MTN MoMo + Orange Money + carte).

⚠️ À activer en prod via settings : PAIEMENT_PROVIDER='cinetpay' + CINETPAY_API_KEY,
CINETPAY_SITE_ID, CINETPAY_SECRET_KEY, et les URLs de retour/notification.
Implémentation conforme à l'API CinetPay v2 ; à valider avec un vrai compte marchand.
"""
import hmac
import hashlib

from django.conf import settings

from .base import PaiementProvider

API_INIT = 'https://api-checkout.cinetpay.com/v2/payment'
API_CHECK = 'https://api-checkout.cinetpay.com/v2/payment/check'


class CinetPayProvider(PaiementProvider):
    nom = 'cinetpay'

    def _cfg(self, cle, defaut=''):
        return getattr(settings, cle, defaut)

    def creer_paiement(self, transaction, return_url=None):
        import requests  # import local : dépendance optionnelle
        payload = {
            'apikey': self._cfg('CINETPAY_API_KEY'),
            'site_id': self._cfg('CINETPAY_SITE_ID'),
            'transaction_id': str(transaction.reference_interne),
            'amount': int(transaction.montant),
            'currency': transaction.devise,  # 'XAF'
            'description': f"Abonnement Loyatrack {transaction.plan} ({transaction.periodicite})",
            'return_url': return_url or self._cfg('CINETPAY_RETURN_URL'),
            'notify_url': self._cfg('CINETPAY_NOTIFY_URL'),
            'channels': 'ALL',
        }
        r = requests.post(API_INIT, json=payload, timeout=20)
        data = r.json()
        # CinetPay renvoie data.payment_url en cas de succès (code '201').
        url = (data.get('data') or {}).get('payment_url')
        if not url:
            raise RuntimeError(f"CinetPay init échouée : {data}")
        return url

    def parse_webhook(self, request):
        data = request.data if hasattr(request, 'data') else request.POST
        reference = data.get('cpm_trans_id') or data.get('transaction_id')
        # On ne fait PAS confiance au statut brut : on revérifie via l'API check.
        statut = 'reussi' if self._verifier_via_api(reference) else 'echoue'
        return reference, statut, dict(data)

    def _verifier_via_api(self, reference):
        if not reference:
            return False
        import requests
        try:
            r = requests.post(API_CHECK, json={
                'apikey': self._cfg('CINETPAY_API_KEY'),
                'site_id': self._cfg('CINETPAY_SITE_ID'),
                'transaction_id': str(reference),
            }, timeout=20)
            data = r.json()
            return (data.get('data') or {}).get('status') == 'ACCEPTED'
        except Exception:
            return False

    def verifier_signature(self, request):
        """Vérifie le HMAC du webhook (en-tête x-token) si un secret est configuré.
        La revérification API dans parse_webhook reste la garantie principale."""
        secret = self._cfg('CINETPAY_SECRET_KEY')
        if not secret:
            return True  # pas de secret configuré → on s'appuie sur la revérif API
        recu = request.headers.get('x-token', '')
        corps = request.body or b''
        attendu = hmac.new(secret.encode(), corps, hashlib.sha256).hexdigest()
        return hmac.compare_digest(recu, attendu)

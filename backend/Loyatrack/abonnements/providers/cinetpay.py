"""Prestataire CinetPay (MTN MoMo + Orange Money + carte).

⚠️ À activer en prod via settings : PAIEMENT_PROVIDER='cinetpay' + CINETPAY_API_KEY,
CINETPAY_SITE_ID, CINETPAY_SECRET_KEY, et les URLs de retour/notification.
Implémentation conforme à l'API CinetPay v2 ; à valider avec un vrai compte marchand.
"""
import hmac
import hashlib
import json

from django.conf import settings

from .base import PaiementProvider

API_INIT = 'https://api-checkout.cinetpay.com/v2/payment'
API_CHECK = 'https://api-checkout.cinetpay.com/v2/payment/check'
# API Transfert d'argent (reversement vers le Mobile Money du bailleur).
API_TRANSFER = 'https://client.cinetpay.com/v1'


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

    def _verifier_via_api(self, reference, credentials=None):
        """Revérifie via l'API check. `credentials` (dict api_key/site_id) permet
        le mode multi-comptes ; à défaut on retombe sur les réglages globaux
        (utilisés pour l'abonnement)."""
        if not reference:
            return False
        api_key = (credentials or {}).get('api_key') or self._cfg('CINETPAY_API_KEY')
        site_id = (credentials or {}).get('site_id') or self._cfg('CINETPAY_SITE_ID')
        import requests
        try:
            r = requests.post(API_CHECK, json={
                'apikey': api_key,
                'site_id': site_id,
                'transaction_id': str(reference),
            }, timeout=20)
            data = r.json()
            return (data.get('data') or {}).get('status') == 'ACCEPTED'
        except Exception:
            return False

    # ── Encaissement générique (loyers) : collecte sur le compte PLATEFORME ───
    # `credentials` reste accepté pour compatibilité, mais à défaut on retombe
    # sur les réglages globaux (mode « encaissement centralisé »).
    def creer_paiement_generique(self, *, reference, montant, devise,
                                 description, return_url, notify_url, credentials):
        import requests  # dépendance optionnelle
        payload = {
            'apikey': (credentials or {}).get('api_key') or self._cfg('CINETPAY_API_KEY'),
            'site_id': (credentials or {}).get('site_id') or self._cfg('CINETPAY_SITE_ID'),
            'transaction_id': str(reference),
            # CinetPay/XAF exige un montant entier multiple de 5.
            'amount': int(montant) - (int(montant) % 5),
            'currency': devise,
            'description': description,
            'return_url': return_url,
            'notify_url': notify_url,
            'channels': 'ALL',
        }
        r = requests.post(API_INIT, json=payload, timeout=20)
        data = r.json()
        url = (data.get('data') or {}).get('payment_url')
        if not url:
            raise RuntimeError(f"CinetPay init échouée : {data}")
        return url

    def verifier_paiement(self, reference, credentials):
        return self._verifier_via_api(reference, credentials)

    # ── Reversement (API Transfert d'argent) ─────────────────────────────────
    def effectuer_transfert(self, *, reference, montant, devise, numero, operateur):
        """Reverse le loyer vers le Mobile Money du bailleur via l'API Transfert.

        Flux CinetPay v1 : login (apikey + mot de passe transfert) → token, puis
        enregistrement du contact et envoi. ⚠️ Nécessite l'activation du service
        « Transfert d'argent » et un solde suffisant sur le compte plateforme ;
        à valider avec un compte réel. Renvoie (ok, ref, erreur).
        """
        import requests  # dépendance optionnelle
        apikey = self._cfg('CINETPAY_API_KEY')
        password = self._cfg('CINETPAY_TRANSFER_PASSWORD')
        if not (apikey and password):
            return False, '', "Transfert CinetPay non configuré (CINETPAY_TRANSFER_PASSWORD manquant)."
        try:
            # 1) Authentification → token
            auth = requests.post(f"{API_TRANSFER}/auth/login",
                                 data={'apikey': apikey, 'password': password}, timeout=20)
            token = (auth.json().get('data') or {}).get('token')
            if not token:
                return False, '', f"Auth transfert échouée : {auth.text}"

            # Numéro attendu sans préfixe pays (prefix fourni à part).
            # NB : `operateur` (mtn/orange) n'est volontairement PAS transmis —
            # l'API Transfert CinetPay déduit l'opérateur du numéro (préfixe +237).
            # Il reste dans la signature pour un futur prestataire qui l'exigerait.
            phone = ''.join(ch for ch in (numero or '') if ch.isdigit())
            if phone.startswith('237'):
                phone = phone[3:]
            params = {'token': token, 'lang': 'fr'}

            # 2) Enregistrement du contact (ignoré côté CinetPay s'il existe déjà).
            contact = [{'prefix': '237', 'phone': phone, 'name': 'Bailleur',
                        'surname': 'LoyaTrack', 'email': 'bailleur@loyatrack.com'}]
            requests.post(f"{API_TRANSFER}/transfer/contact", params=params,
                          data={'data': json.dumps(contact)}, timeout=20)

            # 3) Envoi de l'argent (XAF : montant entier multiple de 5).
            montant_xaf = int(montant) - (int(montant) % 5)
            envoi = [{'prefix': '237', 'phone': phone, 'amount': montant_xaf,
                      'client_transaction_id': str(reference),
                      'notify_url': self._cfg('CINETPAY_TRANSFER_NOTIFY_URL')}]
            r = requests.post(f"{API_TRANSFER}/transfer/money/send/contact",
                              params=params, data={'data': json.dumps(envoi)}, timeout=30)
            data = r.json()
            ok = str(data.get('code')) == '0'  # code '0' = succès côté Transfert
            ref = ''
            try:
                ref = (data.get('data') or [{}])[0].get('transaction_id', '') or ''
            except (IndexError, AttributeError, TypeError):
                ref = ''
            return (ok, ref, '' if ok else f"Transfert refusé : {data}")
        except Exception as e:
            return False, '', str(e)

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

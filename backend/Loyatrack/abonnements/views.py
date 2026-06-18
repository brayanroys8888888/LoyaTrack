from rest_framework import permissions, status
from rest_framework.response import Response
from rest_framework.views import APIView

from . import constants, services
from .models import TransactionAbonnement, JetonAccesBailleur
from .providers import get_provider
from .serializers import AbonnementSerializer, CheckoutSerializer


class AbonnementStatutView(APIView):
    """GET le statut d'abonnement du bailleur connecté.

    Accessible même quand l'abonnement est expiré (sinon l'app ne pourrait pas
    afficher le paywall) → IsAuthenticated seulement, pas de gating ici.
    """
    permission_classes = (permissions.IsAuthenticated,)

    def get(self, request):
        ab = services.assurer_abonnement(request.user)
        return Response(AbonnementSerializer(ab).data)


class PlansView(APIView):
    """Catalogue des plans + prix (affichage, sans paiement in-app)."""
    permission_classes = (permissions.IsAuthenticated,)

    def get(self, request):
        plans = []
        for cle, cfg in constants.PLANS.items():
            plans.append({
                'cle': cle,
                'nom': cfg['nom'],
                'mensuel': int(cfg['mensuel']),
                'annuel': int(cfg['annuel']),
                'devise': 'FCFA',
                'max_biens': cfg['max_biens'],
                'features': cfg['features'],
            })
        return Response({'plans': plans, 'features_pro': sorted(constants.FEATURES_PRO)})


class CheckoutView(APIView):
    """(Web) Crée une transaction et renvoie l'URL de paiement du prestataire.

    Accessible même si expiré : c'est précisément l'action qui permet de repayer.
    """
    permission_classes = (permissions.IsAuthenticated,)

    def post(self, request):
        serializer = CheckoutSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        plan = serializer.validated_data['plan']
        periodicite = serializer.validated_data['periodicite']

        provider = get_provider()
        transaction = services.creer_transaction(
            request.user, plan, periodicite, prestataire=provider.nom
        )
        url = provider.creer_paiement(transaction)
        return Response({
            'reference': str(transaction.reference_interne),
            'montant': int(transaction.montant),
            'devise': transaction.devise,
            'url_paiement': url,
        }, status=status.HTTP_201_CREATED)


class LienWebView(APIView):
    """Génère un magic-link à usage unique (≤10 min) vers l'espace web d'abonnement.

    Accessible même si l'abonnement est expiré (c'est le chemin pour aller payer).
    """
    permission_classes = (permissions.IsAuthenticated,)

    def post(self, request):
        jeton = JetonAccesBailleur.objects.create(bailleur=request.user)
        url = request.build_absolute_uri(f'/abonnement/acces/{jeton.token}/')
        return Response({'url': url, 'expire_minutes': JetonAccesBailleur.DUREE_MINUTES})


class WebhookView(APIView):
    """Webhook prestataire → active l'abonnement (idempotent, signature vérifiée)."""
    permission_classes = (permissions.AllowAny,)

    def post(self, request):
        provider = get_provider()
        if not provider.verifier_signature(request):
            return Response({'error': 'Signature invalide'}, status=status.HTTP_400_BAD_REQUEST)

        reference, statut_paiement, payload = provider.parse_webhook(request)
        if not reference:
            return Response({'error': 'Référence manquante'}, status=status.HTTP_400_BAD_REQUEST)

        transaction = TransactionAbonnement.objects.filter(reference_interne=reference).first()
        if transaction is None:
            return Response({'error': 'Transaction introuvable'}, status=status.HTTP_404_NOT_FOUND)

        if statut_paiement == 'reussi':
            services.activer_depuis_transaction(transaction, payload=payload)
            return Response({'status': 'abonnement activé'})

        if transaction.statut == 'en_attente':
            transaction.statut = 'echoue' if statut_paiement == 'echoue' else 'annule'
            transaction.payload = payload
            transaction.save(update_fields=['statut', 'payload'])
        return Response({'status': f'paiement {statut_paiement}'})

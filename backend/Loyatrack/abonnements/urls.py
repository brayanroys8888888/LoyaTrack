from django.urls import path

from .views import AbonnementStatutView, PlansView, CheckoutView, WebhookView, LienWebView

urlpatterns = [
    path('abonnement/', AbonnementStatutView.as_view(), name='abonnement-statut'),
    path('abonnement/plans/', PlansView.as_view(), name='abonnement-plans'),
    path('abonnement/checkout/', CheckoutView.as_view(), name='abonnement-checkout'),
    path('abonnement/lien-web/', LienWebView.as_view(), name='abonnement-lien-web'),
    path('webhooks/paiement/', WebhookView.as_view(), name='abonnement-webhook'),
]

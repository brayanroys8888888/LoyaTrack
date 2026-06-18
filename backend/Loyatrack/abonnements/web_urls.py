from django.urls import path

from . import web_views

# Espace web bailleur (monté à la racine, comme le portail locataire).
web_urlpatterns = [
    path('abonnement/acces/<str:token>/', web_views.acces_web, name='abonnement_acces'),
    path('abonnement/', web_views.espace_abonnement, name='abonnement_espace'),
    path('abonnement/payer/', web_views.payer, name='abonnement_payer'),
    path('abonnement/checkout/fake/', web_views.checkout_fake, name='abonnement_checkout_fake'),
    path('abonnement/retour/', web_views.retour_paiement, name='abonnement_retour'),
    path('abonnement/recu/<uuid:ref>/', web_views.recu_web, name='abonnement_recu'),
]

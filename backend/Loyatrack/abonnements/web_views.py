"""Espace web du bailleur pour gérer/payer son abonnement (hors app mobile).

Le bailleur arrive via un magic-link (usage unique, ≤10 min) émis par l'app, qui
ouvre une session Django. Le paiement passe par le prestataire (FakeProvider en dev).
"""
from django.contrib.auth import login
from django.http import HttpResponse
from django.shortcuts import redirect, render
from django.urls import reverse
from django.views.decorators.http import require_http_methods

from . import constants, services
from .models import JetonAccesBailleur, TransactionAbonnement
from .pdf import generer_recu_abonnement_pdf
from .providers import get_provider


def _plans_contexte():
    return [
        {
            'cle': cle, 'nom': cfg['nom'],
            'mensuel': int(cfg['mensuel']), 'annuel': int(cfg['annuel']),
            'features': cfg['features'],
        }
        for cle, cfg in constants.PLANS.items()
    ]


def acces_web(request, token):
    """Consomme le magic-link et ouvre une session web pour le bailleur."""
    jeton = JetonAccesBailleur.objects.filter(token=token).select_related('bailleur').first()
    if not jeton or not jeton.est_valide:
        return render(request, 'abonnements/invalide.html', status=404)
    jeton.consommer()  # usage unique
    login(request, jeton.bailleur, backend='django.contrib.auth.backends.ModelBackend')
    return redirect('abonnement_espace')


def espace_abonnement(request):
    if not request.user.is_authenticated:
        return render(request, 'abonnements/invalide.html', status=403)
    ab = services.assurer_abonnement(request.user)
    return render(request, 'abonnements/espace.html', {
        'abonnement': ab, 'plans': _plans_contexte(),
    })


@require_http_methods(['POST'])
def payer(request):
    if not request.user.is_authenticated:
        return redirect('abonnement_espace')
    plan = request.POST.get('plan')
    periodicite = request.POST.get('periodicite')
    if plan not in constants.PLANS or periodicite not in constants.PERIODICITES:
        return redirect('abonnement_espace')
    provider = get_provider()
    tx = services.creer_transaction(request.user, plan, periodicite, prestataire=provider.nom)
    return_url = request.build_absolute_uri(reverse('abonnement_retour'))
    url = provider.creer_paiement(tx, return_url=return_url)
    return redirect(url)


def checkout_fake(request):
    """Page de simulation de paiement (FakeProvider, dev uniquement)."""
    ref = request.GET.get('ref')
    tx = TransactionAbonnement.objects.filter(reference_interne=ref).first()
    if not tx:
        return render(request, 'abonnements/invalide.html', status=404)
    if request.method == 'POST':
        services.activer_depuis_transaction(tx)
        return redirect('abonnement_retour')
    return render(request, 'abonnements/fake_checkout.html', {'tx': tx})


def retour_paiement(request):
    ab = services.assurer_abonnement(request.user) if request.user.is_authenticated else None
    derniere = None
    if request.user.is_authenticated:
        derniere = (TransactionAbonnement.objects
                    .filter(bailleur=request.user, statut='reussi').first())
    return render(request, 'abonnements/retour.html', {'abonnement': ab, 'transaction': derniere})


def recu_web(request, ref):
    """Sert le reçu PDF d'une transaction réussie au bailleur connecté (session web)."""
    if not request.user.is_authenticated:
        return render(request, 'abonnements/invalide.html', status=403)
    tx = TransactionAbonnement.objects.filter(
        reference_interne=ref, bailleur=request.user, statut='reussi').first()
    if not tx:
        return render(request, 'abonnements/invalide.html', status=404)
    pdf = generer_recu_abonnement_pdf(tx)
    resp = HttpResponse(pdf, content_type='application/pdf')
    resp['Content-Disposition'] = f'attachment; filename="recu_abonnement_{tx.id}.pdf"'
    return resp

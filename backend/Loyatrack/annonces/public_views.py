"""Pages publiques SSR de la vitrine (SEO) — Palier 1, étape 4.

Rendues côté serveur (indexables), servies sous /logements/. Voir
LOYATRACK_MARKETPLACE_PLAN.md §9.4. La recherche / les pages de localisation
(ItemList) sont au Palier 2 ; ici on livre la page détail partageable.
"""
import json

from django.core.paginator import Paginator
from django.db.models import Avg, Count, F, Q
from django.http import Http404, HttpResponse
from django.shortcuts import get_object_or_404, redirect, render
from django.template.loader import render_to_string
from django.utils import timezone

from .models import Annonce, Ville, Quartier, Chercheur, Conversation, Signalement
from .messagerie import (
    envoyer_otp_chercheur, verifier_otp_chercheur, demarrer_conversation,
    repondre, MessagerieError,
)

_TYPES = dict(Annonce.TYPE_CHOICES)
# Libellés pluriels FR pour les titres des pages de liste.
_PLURIEL = {
    'appartement': 'Appartements', 'villa': 'Villas', 'studio': 'Studios',
    'chambre': 'Chambres', 'immeuble': 'Immeubles', 'bureau': 'Bureaux',
    'autre': 'Logements',
}
_PAR_PAGE = 12


def _fmt_fcfa(montant):
    """Formate un entier FCFA avec séparateur d'espace (style FR)."""
    return f"{int(montant or 0):,}".replace(',', ' ')


def _publiees():
    """Annonces publiées et non expirées (base commune des pages publiques)."""
    return (Annonce.objects
            .filter(statut='publiee', date_expiration__gt=timezone.now())
            .select_related('ville', 'quartier')
            .prefetch_related('photos'))


def _jsonld(data):
    return json.dumps(data, ensure_ascii=False).replace('<', '\\u003c')


def _annonce_publiee(slug):
    """Une annonce publiée non expirée, ou None."""
    return (Annonce.objects
            .filter(slug=slug, statut='publiee', date_expiration__gt=timezone.now())
            .select_related('ville', 'quartier', 'bailleur')
            .prefetch_related('photos').first())


def annonce_publique(request, slug):
    """Page détail publique d'une annonce publiée (SEO + aperçu partage)."""
    annonce = (Annonce.objects
               .filter(slug=slug, statut='publiee', date_expiration__gt=timezone.now())
               .select_related('ville', 'quartier', 'bailleur')
               .prefetch_related('photos')
               .first())
    if annonce is None:
        # Annonce inexistante, en brouillon, pourvue ou expirée → 404 indexable.
        return render(request, 'annonces/introuvable.html', status=404)

    # Compteur de vues : une fois par session (pas à chaque rafraîchissement).
    vues = request.session.get('annonces_vues', [])
    if annonce.id not in vues:
        Annonce.objects.filter(pk=annonce.pk).update(nb_vues=F('nb_vues') + 1)
        request.session['annonces_vues'] = vues + [annonce.id]

    photos = list(annonce.photos.all())
    image_urls = [request.build_absolute_uri(p.image.url) for p in photos]
    cover = next((p for p in photos if p.est_couverture), photos[0] if photos else None)
    cover_url = request.build_absolute_uri(cover.image.url) if cover else ''
    canonical = request.build_absolute_uri(request.path)

    type_label = _TYPES.get(annonce.type_bien, annonce.type_bien)
    localite = annonce.quartier.nom if annonce.quartier else (
        annonce.ville.nom if annonce.ville else '')
    lieu = f"{localite}, {annonce.ville.nom}" if (annonce.quartier and annonce.ville) else (
        annonce.ville.nom if annonce.ville else localite)
    titre_seo = (f"{type_label} {annonce.nb_chambres} chambres à louer à {lieu} "
                 f"— {_fmt_fcfa(annonce.loyer)} FCFA/mois")
    meta_desc = (f"{type_label} de {annonce.nb_chambres} chambre(s) à louer à {lieu}. "
                 f"Loyer {_fmt_fcfa(annonce.loyer)} FCFA/mois. Annonce vérifiée sur Loyatrack.")

    jsonld = {
        "@context": "https://schema.org",
        "@type": "RealEstateListing",
        "name": titre_seo,
        "url": canonical,
        "description": meta_desc,
        "datePosted": annonce.date_publication.isoformat() if annonce.date_publication else None,
        "image": image_urls or None,
        "numberOfRooms": annonce.nb_chambres,
        "offers": {
            "@type": "Offer",
            "price": int(annonce.loyer or 0),
            "priceCurrency": "XAF",
            "availability": "https://schema.org/InStock",
        },
        "address": {
            "@type": "PostalAddress",
            "addressLocality": localite,
            "addressRegion": annonce.ville.nom if annonce.ville else '',
            "addressCountry": "CM",
        },
    }
    if annonce.superficie_m2:
        jsonld["floorSize"] = {"@type": "QuantitativeValue",
                               "value": annonce.superficie_m2, "unitCode": "MTK"}
    jsonld = {k: v for k, v in jsonld.items() if v is not None}
    # Neutralise une éventuelle fermeture </script> dans les données.
    jsonld_str = json.dumps(jsonld, ensure_ascii=False).replace('<', '\\u003c')

    return render(request, 'annonces/detail.html', {
        'annonce': annonce,
        'photos': photos,
        'cover_url': cover_url,
        'canonical': canonical,
        'titre_seo': titre_seo,
        'meta_desc': meta_desc,
        'type_label': type_label,
        'lieu': lieu,
        'loyer_fmt': _fmt_fcfa(annonce.loyer),
        'charges_fmt': _fmt_fcfa(annonce.charges),
        'jsonld': jsonld_str,
    })


def _int(v):
    return int(v) if v and str(v).isdigit() else None


def _form_valeurs(request):
    g = request.GET
    return {'ville': g.get('ville', ''), 'type': g.get('type', ''),
            'chambres': g.get('chambres', ''), 'prix_max': g.get('prix_max', ''),
            'meuble': g.get('meuble', '')}


def _contexte_liste(request, annonces, *, titre, h1, intro, fil, canonical,
                    indexable, sous_liens=()):
    """Pagine, prépare l'affichage et construit les JSON-LD Breadcrumb + ItemList."""
    paginator = Paginator(annonces, _PAR_PAGE)
    page = paginator.get_page(request.GET.get('page'))
    for a in page:
        a.loyer_fmt = _fmt_fcfa(a.loyer)

    blocs = []
    if fil:
        blocs.append(_jsonld({
            "@context": "https://schema.org", "@type": "BreadcrumbList",
            "itemListElement": [
                {"@type": "ListItem", "position": i + 1, "name": nom,
                 "item": request.build_absolute_uri(url)}
                for i, (nom, url) in enumerate(fil)],
        }))
    if page.object_list:
        blocs.append(_jsonld({
            "@context": "https://schema.org", "@type": "ItemList",
            "itemListElement": [
                {"@type": "ListItem", "position": i + 1,
                 "url": request.build_absolute_uri(f'/logements/annonce/{a.slug}/')}
                for i, a in enumerate(page.object_list)],
        }))
    params = request.GET.copy()
    params.pop('page', None)
    return {
        'page': page, 'total': paginator.count, 'titre': titre, 'h1': h1,
        'intro': intro, 'fil': fil, 'canonical': canonical, 'indexable': indexable,
        'jsonld_blocs': blocs, 'sous_liens': list(sous_liens),
        'qs_str': params.urlencode(),
        'form': _form_valeurs(request), 'villes': Ville.objects.all(),
        'types': Annonce.TYPE_CHOICES,
    }


def accueil(request):
    """Page d'accueil de la vitrine : recherche + villes + annonces récentes."""
    now = timezone.now()
    villes = (Ville.objects
              .annotate(n=Count('annonces', filter=Q(annonces__statut='publiee',
                                                     annonces__date_expiration__gt=now)))
              .order_by('ordre', 'nom'))
    recentes = list(_publiees().order_by('-date_publication', '-id')[:6])
    for a in recentes:
        a.loyer_fmt = _fmt_fcfa(a.loyer)
    return render(request, 'annonces/accueil.html', {
        'villes': villes, 'recentes': recentes,
        'form': _form_valeurs(request), 'types': Annonce.TYPE_CHOICES,
        'canonical': request.build_absolute_uri('/logements/'),
    })


def annonces_liste(request, ville_slug, quartier_slug=None, type_bien=None, chambres=None):
    """Page de localisation SEO (ville / quartier / type / combo type-N-chambres)."""
    ville = get_object_or_404(Ville, slug=ville_slug)
    quartier = get_object_or_404(Quartier, ville=ville, slug=quartier_slug) if quartier_slug else None
    if type_bien and type_bien not in _TYPES:
        raise Http404
    chambres = _int(chambres)

    qs = _publiees().filter(ville=ville)
    if quartier:
        qs = qs.filter(quartier=quartier)
    if type_bien:
        qs = qs.filter(type_bien=type_bien)
    if chambres:
        qs = qs.filter(nb_chambres=chambres)
    qs = qs.order_by('-date_publication', '-id')

    lieu = f"{quartier.nom}, {ville.nom}" if quartier else ville.nom
    type_label = _PLURIEL.get(type_bien, 'Logements') if type_bien else 'Logements'
    ch = f"{chambres} chambres " if chambres else ""
    h1 = f"{type_label} {ch}à louer à {lieu}".replace('  ', ' ').strip()
    avg = qs.aggregate(m=Avg('loyer'))['m']
    intro = f"{qs.count()} logement(s) à louer à {lieu}."
    if avg:
        intro += f" Loyer moyen : {_fmt_fcfa(avg)} FCFA/mois."

    base = f'/logements/louer/{ville.slug}/'
    fil = [('Accueil', '/logements/'), (ville.nom, base)]
    if quartier:
        fil.append((quartier.nom, f'{base}{quartier.slug}/'))
    if type_bien:
        fil.append((_TYPES[type_bien], f'{base}{quartier.slug}/{type_bien}/'))

    # Maillage interne (crawlabilité) : sous-pages ayant des annonces.
    sous_liens = []
    if not quartier:
        qids = [x for x in qs.values_list('quartier', flat=True).distinct() if x]
        sous_liens = [(q.nom, f'{base}{q.slug}/')
                      for q in Quartier.objects.filter(id__in=qids).order_by('nom')]
    elif not type_bien:
        for t in qs.values_list('type_bien', flat=True).distinct():
            sous_liens.append((_PLURIEL.get(t, t), f'{base}{quartier.slug}/{t}/'))

    ctx = _contexte_liste(
        request, qs, titre=f"{h1} | Loyatrack", h1=h1, intro=intro, fil=fil,
        canonical=request.build_absolute_uri(request.path), indexable=True,
        sous_liens=sous_liens)
    return render(request, 'annonces/liste.html', ctx)


def recherche(request):
    """Recherche à facettes (query params) — non indexée (noindex, canonical vitrine)."""
    g = request.GET
    qs = _publiees()
    ville = Ville.objects.filter(slug=g.get('ville')).first() if g.get('ville') else None
    if ville:
        qs = qs.filter(ville=ville)
    if g.get('type') in _TYPES:
        qs = qs.filter(type_bien=g['type'])
    if _int(g.get('chambres')):
        qs = qs.filter(nb_chambres__gte=_int(g['chambres']))
    if _int(g.get('prix_max')):
        qs = qs.filter(loyer__lte=_int(g['prix_max']))
    if g.get('meuble') == '1':
        qs = qs.filter(meuble=True)
    qs = qs.order_by('-date_publication', '-id')

    ctx = _contexte_liste(
        request, qs, titre='Recherche de logements à louer | Loyatrack',
        h1='Rechercher un logement', intro=f"{qs.count()} résultat(s).",
        fil=[('Accueil', '/logements/'), ('Recherche', '/logements/recherche/')],
        canonical=request.build_absolute_uri('/logements/recherche/'), indexable=False)
    return render(request, 'annonces/liste.html', ctx)


def sitemap_annonces(request):
    """Sitemap XML : accueil + pages de localisation (villes, quartiers) + annonces."""
    now = timezone.now()
    aujourd_hui = now.date().isoformat()
    urls = [(request.build_absolute_uri('/logements/'), aujourd_hui)]

    for ville in Ville.objects.all():
        if _publiees().filter(ville=ville).exists():
            urls.append((request.build_absolute_uri(f'/logements/louer/{ville.slug}/'), aujourd_hui))
    qids = [x for x in _publiees().values_list('quartier', flat=True).distinct() if x]
    for q in Quartier.objects.filter(id__in=qids).select_related('ville'):
        urls.append((request.build_absolute_uri(
            f'/logements/louer/{q.ville.slug}/{q.slug}/'), aujourd_hui))

    for a in Annonce.objects.filter(
            statut='publiee', date_expiration__gt=now).only('slug', 'date_maj'):
        urls.append((request.build_absolute_uri(f'/logements/annonce/{a.slug}/'),
                     a.date_maj.date().isoformat()))

    xml = render_to_string('annonces/sitemap.xml', {'urls': urls})
    return HttpResponse(xml, content_type='application/xml')


def robots_txt(request):
    """robots.txt : autorise la vitrine, bloque l'API et les espaces privés."""
    sitemap = request.build_absolute_uri('/logements/sitemap.xml')
    lignes = [
        'User-agent: *',
        'Allow: /logements/',
        'Disallow: /api/',
        'Disallow: /admin/',
        'Disallow: /portail/',
        'Disallow: /abonnement/',
        f'Sitemap: {sitemap}',
    ]
    return HttpResponse('\n'.join(lignes) + '\n', content_type='text/plain')


# ── Messagerie côté chercheur (web SSR) ──────────────────────────────────────
def contacter(request, slug):
    """Parcours de contact du chercheur : téléphone → OTP → message.

    Piloté par la session ; si le numéro est déjà vérifié (< 30 j), l'OTP est
    sauté. Ouvre une conversation puis redirige vers le fil (jeton).
    """
    annonce = _annonce_publiee(slug)
    if annonce is None:
        return render(request, 'annonces/introuvable.html', status=404)

    etape, erreur, dev_code = 'phone', None, None
    if request.method == 'POST':
        action = request.POST.get('etape')
        if action == 'phone':
            tel = request.POST.get('telephone', '').strip()
            nom = request.POST.get('nom', '').strip()
            if not tel:
                erreur = "Indiquez votre numéro de téléphone."
            else:
                ch, _ = Chercheur.objects.get_or_create(telephone=tel, defaults={'nom': nom})
                if nom and not ch.nom:
                    ch.nom = nom
                    ch.save(update_fields=['nom'])
                if ch.est_verifie:
                    request.session['chercheur_id'] = ch.id
                    etape = 'message'
                else:
                    try:
                        ch, extra = envoyer_otp_chercheur(tel, nom)
                    except MessagerieError as e:
                        erreur = str(e)
                    else:
                        request.session['chercheur_pending'] = ch.id
                        etape, dev_code = 'otp', extra.get('dev_code')
        elif action == 'otp':
            ch = Chercheur.objects.filter(id=request.session.get('chercheur_pending')).first()
            if ch and verifier_otp_chercheur(ch, request.POST.get('code', '').strip()):
                request.session['chercheur_id'] = ch.id
                etape = 'message'
            else:
                erreur, etape = "Code invalide ou expiré.", 'otp'
        elif action == 'message':
            ch = Chercheur.objects.filter(id=request.session.get('chercheur_id')).first()
            corps = request.POST.get('corps', '').strip()
            if ch and ch.est_verifie and corps:
                try:
                    conv = demarrer_conversation(annonce, ch, corps)
                    return redirect(f'/logements/messages/{conv.token}/')
                except MessagerieError as e:
                    erreur, etape = str(e), 'message'
            else:
                erreur, etape = "Écrivez un message.", 'message'
    else:
        ch = Chercheur.objects.filter(id=request.session.get('chercheur_id')).first()
        if ch and ch.est_verifie:
            # Déjà une conversation sur cette annonce → on y revient directement.
            conv = Conversation.objects.filter(annonce=annonce, chercheur=ch).first()
            if conv:
                return redirect(f'/logements/messages/{conv.token}/')
            etape = 'message'

    return render(request, 'annonces/contacter.html', {
        'annonce': annonce, 'etape': etape, 'erreur': erreur, 'dev_code': dev_code,
        'message_defaut': (f"Bonjour, ce logement (« {annonce.titre} ») est-il "
                           "toujours disponible ? Quand puis-je le visiter ?"),
        'canonical': request.build_absolute_uri(request.path),
    })


def mes_conversations(request):
    """Liste des conversations du chercheur (identifié par la session)."""
    ch = Chercheur.objects.filter(id=request.session.get('chercheur_id')).first()
    convs = []
    if ch:
        convs = (Conversation.objects.filter(chercheur=ch)
                 .select_related('annonce').prefetch_related('messages')
                 .order_by('-date_dernier_message'))
        for c in convs:
            m = c.messages.last()
            c.apercu = m.corps[:80] if m else ''
    return render(request, 'annonces/mes_conversations.html', {
        'convs': convs, 'chercheur': ch,
        'canonical': request.build_absolute_uri('/logements/messages/'),
    })


def fil_messages(request, token):
    """Fil de discussion du chercheur (accès par jeton, sans compte)."""
    conv = (Conversation.objects.filter(token=token)
            .select_related('annonce', 'chercheur').first())
    if conv is None:
        return render(request, 'annonces/introuvable.html', status=404)
    if request.method == 'POST':
        corps = request.POST.get('corps', '').strip()
        if corps and conv.statut == 'ouverte':
            repondre(conv, 'chercheur', corps)
        return redirect(f'/logements/messages/{conv.token}/')
    return render(request, 'annonces/fil.html', {
        'conv': conv, 'annonce': conv.annonce, 'messages': conv.messages.all(),
    })


def signaler(request, slug):
    """Signalement d'une annonce par un visiteur (modération anti-arnaque)."""
    annonce = _annonce_publiee(slug)
    if annonce is None:
        return render(request, 'annonces/introuvable.html', status=404)
    envoye = False
    if request.method == 'POST':
        motif = request.POST.get('motif', '').strip()
        if motif:
            Signalement.objects.create(annonce=annonce, motif=motif[:2000])
            envoye = True
    return render(request, 'annonces/signaler.html', {'annonce': annonce, 'envoye': envoye})

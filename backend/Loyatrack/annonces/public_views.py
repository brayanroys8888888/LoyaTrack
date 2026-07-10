"""Pages publiques SSR de la vitrine (SEO) — Palier 1, étape 4.

Rendues côté serveur (indexables), servies sous /logements/. Voir
LOYATRACK_MARKETPLACE_PLAN.md §9.4. La recherche / les pages de localisation
(ItemList) sont au Palier 2 ; ici on livre la page détail partageable.
"""
import json

from django.db.models import F
from django.http import Http404, HttpResponse
from django.shortcuts import render
from django.template.loader import render_to_string
from django.utils import timezone

from .models import Annonce

_TYPES = dict(Annonce.TYPE_CHOICES)


def _fmt_fcfa(montant):
    """Formate un entier FCFA avec séparateur d'espace (style FR)."""
    return f"{int(montant or 0):,}".replace(',', ' ')


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


def sitemap_annonces(request):
    """Sitemap XML minimal des annonces publiées (l'usine SEO complète = Palier 2)."""
    annonces = Annonce.objects.filter(
        statut='publiee', date_expiration__gt=timezone.now()).only('slug', 'date_maj')
    urls = [(request.build_absolute_uri(f'/logements/annonce/{a.slug}/'),
             a.date_maj.date().isoformat()) for a in annonces]
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

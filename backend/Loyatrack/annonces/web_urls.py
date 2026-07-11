from django.urls import path, re_path

from . import public_views

# Pages publiques SSR (montées à la racine, comme portail/abonnement).
web_urlpatterns = [
    path('logements/', public_views.accueil, name='annonces_accueil'),
    path('logements/recherche/', public_views.recherche, name='annonces_recherche'),
    path('logements/annonce/<slug:slug>/', public_views.annonce_publique, name='annonce_publique'),
    path('logements/annonce/<slug:slug>/contacter/', public_views.contacter, name='annonces_contacter'),
    path('logements/annonce/<slug:slug>/signaler/', public_views.signaler, name='annonces_signaler'),
    path('logements/messages/', public_views.mes_conversations, name='annonces_mes_conversations'),
    path('logements/messages/<uuid:token>/', public_views.fil_messages, name='annonces_fil'),
    path('logements/sitemap.xml', public_views.sitemap_annonces, name='annonces_sitemap'),

    # Pages de localisation SEO. Ordre important : le combo « type-N-chambres »
    # doit précéder le type simple (un slug capturerait « appartement-2-chambres »).
    path('logements/louer/<slug:ville_slug>/',
         public_views.annonces_liste, name='annonces_ville'),
    path('logements/louer/<slug:ville_slug>/<slug:quartier_slug>/',
         public_views.annonces_liste, name='annonces_quartier'),
    re_path(r'^logements/louer/(?P<ville_slug>[-\w]+)/(?P<quartier_slug>[-\w]+)/'
            r'(?P<type_bien>[a-z]+)-(?P<chambres>\d+)-chambres/$',
            public_views.annonces_liste, name='annonces_combo'),
    path('logements/louer/<slug:ville_slug>/<slug:quartier_slug>/<slug:type_bien>/',
         public_views.annonces_liste, name='annonces_type'),

    path('robots.txt', public_views.robots_txt, name='robots_txt'),
]

from django.urls import path

from . import public_views

# Pages publiques SSR (montées à la racine, comme portail/abonnement).
web_urlpatterns = [
    path('logements/annonce/<slug:slug>/', public_views.annonce_publique, name='annonce_publique'),
    path('logements/sitemap.xml', public_views.sitemap_annonces, name='annonces_sitemap'),
    path('robots.txt', public_views.robots_txt, name='robots_txt'),
]

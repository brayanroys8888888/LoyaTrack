from django.contrib import admin
from paiements.models import Paiement, DemandePaiement, CompteMarchand

admin.site.register(Paiement)


@admin.register(DemandePaiement)
class DemandePaiementAdmin(admin.ModelAdmin):
    list_display = ('id', 'locataire', 'montant', 'statut', 'reversement_statut',
                    'date_creation', 'date_paiement')
    list_filter = ('statut', 'reversement_statut', 'prestataire')
    search_fields = ('reference_interne', 'locataire__nom', 'locataire__prenom')
    readonly_fields = ('reference_interne', 'date_creation', 'date_paiement')


@admin.register(CompteMarchand)
class CompteMarchandAdmin(admin.ModelAdmin):
    list_display = ('bailleur', 'operateur', 'numero_momo', 'actif', 'frais_pourcentage')
    list_filter = ('actif', 'operateur')

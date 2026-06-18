from django.contrib import admin
from django.db.models import Sum

from .models import Abonnement, TransactionAbonnement, JetonAccesBailleur


@admin.register(Abonnement)
class AbonnementAdmin(admin.ModelAdmin):
    list_display = ('bailleur', 'plan', 'statut', 'date_fin_essai', 'date_fin', 'periodicite')
    list_filter = ('statut', 'plan', 'periodicite')
    search_fields = ('bailleur__email', 'bailleur__telephone')
    readonly_fields = ('date_debut',)


@admin.register(TransactionAbonnement)
class TransactionAbonnementAdmin(admin.ModelAdmin):
    list_display = ('date_creation', 'bailleur', 'plan', 'periodicite', 'montant', 'devise',
                    'statut', 'prestataire')
    list_filter = ('statut', 'plan', 'periodicite', 'prestataire')
    search_fields = ('bailleur__email', 'reference_externe', 'reference_interne')
    date_hierarchy = 'date_paiement'
    readonly_fields = ('reference_interne', 'date_creation', 'date_paiement', 'payload')

    def changelist_view(self, request, extra_context=None):
        """Affiche le total des revenus encaissés (transactions réussies) en en-tête."""
        response = super().changelist_view(request, extra_context)
        try:
            qs = response.context_data['cl'].queryset.filter(statut='reussi')
            total = qs.aggregate(t=Sum('montant'))['t'] or 0
            response.context_data['title'] = (
                f"Transactions d'abonnement — Revenus encaissés (filtre courant) : "
                f"{total:,.0f} FCFA".replace(',', ' ')
            )
        except (AttributeError, KeyError):
            pass
        return response


@admin.register(JetonAccesBailleur)
class JetonAccesBailleurAdmin(admin.ModelAdmin):
    list_display = ('bailleur', 'date_creation', 'utilise')
    list_filter = ('utilise',)
    search_fields = ('bailleur__email',)
    readonly_fields = ('token', 'date_creation')

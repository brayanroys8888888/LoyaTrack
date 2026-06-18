from django.contrib import admin
from .models import Depense


@admin.register(Depense)
class DepenseAdmin(admin.ModelAdmin):
    list_display = ('libelle', 'montant', 'categorie', 'date', 'bien', 'bailleur')
    list_filter = ('categorie',)

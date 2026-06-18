from django.contrib import admin
from .models import Propriete, UniteLogement


@admin.register(Propriete)
class ProprieteAdmin(admin.ModelAdmin):
    list_display = ('titre', 'type', 'bailleur', 'date_creation')
    search_fields = ('titre', 'adresse')


@admin.register(UniteLogement)
class UniteLogementAdmin(admin.ModelAdmin):
    list_display = ('numero', 'propriete', 'loyer_standard', 'statut')
    list_filter = ('statut',)

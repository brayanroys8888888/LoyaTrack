from django.contrib import admin

from .models import (
    Ville, Quartier, Annonce, PhotoAnnonce,
    Chercheur, Conversation, Message, Signalement,
)


@admin.register(Ville)
class VilleAdmin(admin.ModelAdmin):
    list_display = ('nom', 'region', 'ordre', 'slug')
    search_fields = ('nom', 'region')
    prepopulated_fields = {'slug': ('nom',)}


@admin.register(Quartier)
class QuartierAdmin(admin.ModelAdmin):
    list_display = ('nom', 'ville', 'slug')
    list_filter = ('ville',)
    search_fields = ('nom',)


class PhotoAnnonceInline(admin.TabularInline):
    model = PhotoAnnonce
    extra = 0


@admin.register(Annonce)
class AnnonceAdmin(admin.ModelAdmin):
    list_display = ('reference', 'titre', 'type_bien', 'ville', 'quartier',
                    'loyer', 'statut', 'bailleur', 'date_creation')
    list_filter = ('statut', 'type_bien', 'ville')
    search_fields = ('reference', 'titre', 'slug')
    readonly_fields = ('reference', 'slug', 'nb_vues', 'nb_contacts',
                       'date_creation', 'date_maj')
    inlines = [PhotoAnnonceInline]


@admin.register(Chercheur)
class ChercheurAdmin(admin.ModelAdmin):
    list_display = ('telephone', 'nom', 'verifie_le', 'date_creation')
    search_fields = ('telephone', 'nom')


class MessageInline(admin.TabularInline):
    model = Message
    extra = 0
    readonly_fields = ('expediteur', 'corps', 'date_envoi')


@admin.register(Conversation)
class ConversationAdmin(admin.ModelAdmin):
    list_display = ('id', 'annonce', 'chercheur', 'bailleur', 'statut', 'date_dernier_message')
    list_filter = ('statut',)
    inlines = [MessageInline]


@admin.register(Signalement)
class SignalementAdmin(admin.ModelAdmin):
    list_display = ('id', 'annonce', 'conversation', 'traite', 'date_creation')
    list_filter = ('traite',)

from django.contrib import admin
from locataires.models import Locataire, Rappel, Notification

# Register your models here.

admin.site.register(Locataire)
admin.site.register(Rappel)
admin.site.register(Notification)

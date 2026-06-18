from django.apps import AppConfig


class AbonnementsConfig(AppConfig):
    default_auto_field = 'django.db.models.BigAutoField'
    name = 'abonnements'

    def ready(self):
        from . import signals  # noqa: F401  (enregistre le signal post_save)

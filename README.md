# Loyatrack

Application de **gestion locative** pour bailleurs (Cameroun). Suivi des locataires, paiements de loyer, rappels automatisés (SMS / WhatsApp / appel vocal via Twilio), pénalités de retard, biens & unités, comptabilité, documents légaux (conformes à la **Loi camerounaise n°2014/023**), portail locataire, et **abonnement** (essai + 2 formules).

> Langue métier et valeurs en base : **français** · Devise : **FCFA**.

## Architecture

Monorepo composé de deux applications indépendantes :

| Dossier | Stack |
|---|---|
| `backend/Loyatrack/` | Django 5/6 + Django REST Framework (API REST, JWT) |
| `frontend/papillongestion/` | Flutter (application mobile, package `papillon_gestion`) |

Chaque ressource est **scopée par bailleur** (multi-tenant). Détails techniques dans [`CLAUDE.md`](CLAUDE.md).

## Prérequis

- **Python 3.13**, **Redis** (broker Celery)
- **Flutter** (SDK récent) + Android SDK / émulateur
- Compte **Twilio** (rappels) et **Firebase** (push) pour les fonctions associées

## Démarrage — Backend

```bash
cd backend/Loyatrack

# 1) Environnement virtuel + dépendances
python -m venv ../env
../env/Scripts/python.exe -m pip install -r ../requirements.txt   # Windows
# (Linux/macOS : source ../env/bin/activate puis pip install -r ../requirements.txt)

# 2) Configuration : copier le modèle puis renseigner les valeurs
cp .env.example .env
#   + placer le fichier firebase-adminsdk.json dans ce dossier (pour le push FCM)

# 3) Base de données
../env/Scripts/python.exe manage.py migrate
../env/Scripts/python.exe manage.py createsuperuser

# 4) Lancer l'API (0.0.0.0 pour que l'émulateur Android l'atteigne via 10.0.2.2)
../env/Scripts/python.exe manage.py runserver 0.0.0.0:8000
```

- Documentation API : `http://localhost:8000/swagger/` — tout est sous `/api/v1/`, JWT sur `/api/v1/auth/token/`.
- **Tâches planifiées** (rappels, pénalités, abonnements) — nécessite Redis :
  ```bash
  celery -A Loyatrack worker -l info
  celery -A Loyatrack beat -l info
  ```

## Démarrage — Frontend

```bash
cd frontend/papillongestion
flutter pub get
flutter run            # sur un émulateur/appareil connecté
```

Le baseUrl pointe par défaut sur `http://10.0.2.2:8000/api/v1/` (alias émulateur Android → machine hôte). À adapter dans `lib/core/api_config.dart` pour un appareil physique ou la production.

## Tests

```bash
# Backend
cd backend/Loyatrack && ../env/Scripts/python.exe manage.py test

# Frontend
cd frontend/papillongestion && flutter analyze && flutter test
```

## Abonnement (monétisation)

Essai gratuit **14 jours** (Pro débloqué) puis **2 formules** : **Essentiel** (3 000/mois) et **Pro** (8 000/mois). Le paiement se fait sur un **espace web** (via un agrégateur Mobile Money type CinetPay) ; l'application mobile lit seulement le statut (conformité Play Store / App Store). Voir [`LOYATRACK_ABONNEMENT_PLAN.md`](LOYATRACK_ABONNEMENT_PLAN.md) et le guide de test [`LOYATRACK_TEST_ABONNEMENT.md`](LOYATRACK_TEST_ABONNEMENT.md).

## ⚠️ Secrets

Les fichiers `backend/Loyatrack/.env`, `firebase-adminsdk.json` et `db.sqlite3` sont **gitignorés** et ne doivent **jamais** être committés. Utiliser `.env.example` comme modèle.

## Licence

Projet privé. Les documents légaux générés sont structurés d'après la Loi camerounaise n°2014/023 mais **ne constituent pas un conseil juridique** — faire valider par un notaire avant usage officiel.

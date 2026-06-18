# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project layout

Monorepo with two independent apps:
- `backend/Loyatrack/` — Django 5/6 + DRF REST API. Virtualenv at `backend/env/` (Python 3.13; use `backend/env/Scripts/python.exe` on Windows).
- `frontend/papillongestion/` — Flutter mobile app (Dart package name `papillon_gestion`).

Loyatrack lets landlords ("bailleurs") manage tenants, rent payments, automated reminders (SMS/WhatsApp/voice via Twilio), late-payment penalties, properties/units, documents (PDF), and a tenant web portal. **Domain language and DB string values are French; currency is FCFA.**

Django apps: `accounts` (Bailleur user), `locataires` (tenant + reminders/notifications + lifecycle), `paiements`, `penalites`, `biens` (properties/units), `comptabilite` (expenses/reports), `portail` (tenant portal). `Loyatrack/documents/` is a model-less package holding PDF generators (not in `INSTALLED_APPS`).

## Commands

### Backend (run from `backend/Loyatrack/`, e.g. `../env/Scripts/python.exe manage.py ...`)
- Run API: `python manage.py runserver 0.0.0.0:8000` — bind `0.0.0.0` so the Android emulator reaches it via `10.0.2.2`. **Run only ONE server at a time** (see gotchas).
- Migrations: `python manage.py makemigrations` then `migrate`. If a prompt appears for an added `auto_now_add` field on a populated table, pipe answers: `printf '1\ntimezone.now\n' | ... makemigrations`.
- Tests: `python manage.py test` — single: `python manage.py test penalites.tests.PenaliteServiceTests.test_idempotence_meme_jour`
- Celery worker / beat: `celery -A Loyatrack worker -l info` / `celery -A Loyatrack beat -l info` (needs **Redis**, `REDIS_URL` in `.env`).
- Bulk tenant import (CLI): `python manage.py import_locataires <file.csv|xlsx> --bailleur <email>` (also exposed as `POST /api/v1/locataires/importer/`).
- DB backup: `python manage.py backup_data` (also `scripts/backup.sh`).
- API docs at `/swagger/`. Everything under `/api/v1/`; JWT at `/api/v1/auth/token/`.

### Frontend (run from `frontend/papillongestion/`)
- `flutter pub get`, `flutter run`, `flutter analyze`, `flutter test`
- Native plugins in use: `file_picker`, `image_picker`, `open_filex`, `path_provider`. Changing these requires a full rebuild (not hot reload).

## Architecture (big picture)

### Multi-tenant by Bailleur
`accounts.Bailleur` is the custom user model (login by **email**, no username). Every API resource is scoped to the landlord: all DRF `get_queryset` filter by `bailleur=self.request.user` (directly or via `…__bailleur`) — preserve this in new endpoints. `Bailleur.penalite_defaut` is the fallback daily penalty.

### Locataire status & lifecycle
`Locataire.statut` is a French-string state machine (`Payé / En retard / En discussion / En pénalité`) mapped to Dart enums in `lib/models/models.dart` (`statutFromString`/`_statutToBackend`) — change both sides together. Tenants also carry caution, ID-document, and lifecycle fields; soft-delete via `is_deleted`, and end-of-lease via `archive` (archived tenants are excluded from lists/dashboard unless `?inclure_archives=1`). Lifecycle business logic (rent increase, caution movements, résiliation) lives in `locataires/gestion.py` and is exposed as `LocataireViewSet` actions (`augmenter_loyer`, `verser_caution`, `restituer_caution`, `resilier`).

### Penalty engine — `penalites/services.py`
`appliquer_penalite_locataire` is **idempotent**: it recomputes a penalty's total from days-late (using `echeance_du_mois` for absolute dates + grace period), one `Penalite` per `(locataire, periode)` month. `ConfigPenalite` (per tenant) sets grace days and fixed/percentage mode. `remettre_penalite` applies a waiver (motif required). Called by the Celery task `penalites.tasks.calculer_penalites`. **Penalties are frozen for tenants `En discussion`** (ongoing arrangement): the task excludes `statut__in=['Payé', 'En discussion']` and the service short-circuits `if locataire.statut == 'En discussion': return None` — existing penalties stop accruing and the status is preserved (not overwritten to `En pénalité`). For durable exemptions use `ConfigPenalite.actif = False` instead.

### Payments — `paiements/services.py`
`appliquer_paiement` classifies a payment as `complet` / `partiel` / `avance`, computes `reste_du` and the covered period(s); a full/advance payment closes active penalties and marks the tenant `Payé`. Quittance PDF via `/api/v1/paiements/{id}/quittance/`.

### Multi-property — `biens` app
`Propriete` → `UniteLogement` (occupancy derived from linked non-deleted tenants). `Locataire.unite` FK; the legacy free-text `logement` is kept, and migration `locataires/0008_*` backfilled units from it. Dashboard exposes occupancy stats.

### PDF generation (ReportLab)
Generators live in `documents/services.py` (bail contract — Platypus; état des lieux — canvas), `paiements/services.py` (quittance + filtered-payments list export), `comptabilite/services.py` (annual statement + Excel via openpyxl). All return `bytes`; endpoints stream them with `content_type='application/pdf'`. The **legal documents** (contrat de bail, quittance, état des lieux) are structured to comply with **Cameroon Law n°2014/023** (residential leases): mandatory mentions = parties + **addresses**, lease **duration**, loyer + **charges** breakdown, caution, **contradictoire** état des lieux, both-party signatures. Backing fields added for this: `Bailleur.adresse`, `Locataire.{adresse_logement, charges_mensuelles, duree_bail_mois, frequence_paiement}` (captured in the locataire form + landlord address in Réglages → Mon compte). Empty fields render as `________` blanks. ⚠️ Not legal advice — have a notaire validate before official use.

### Automation pipeline (Celery beat → tasks → services)
`settings.CELERY_BEAT_SCHEDULE`: `verifier_echeances`, `calculer_penalites`, `appliquer_augmentations`, `alerter_fin_bail`, `sauvegarder_donnees`. `verifier_echeances` is **config-driven per landlord** via `accounts.ConfigBailleur` (`rappels_automatiques_actifs` master, `jours_avant_rappel`, `canal_rappel_prefere`→SMS/WhatsApp/Appel), plus a J-1 voice fallback. Reminders funnel through `locataires/services.py::execute_rappel(rappel, contexte='avant'|'retard', jours=…)`; messages are built by `construire_message(...)` in **FR or EN** per `Locataire.langue_preferee` (TwiML `alice` switches fr-FR/en-US). Then → Twilio (`send_twilio_message`, normalizes to `+237…`) → records `Rappel`, in-app `Notification`, FCM push. On-demand: `LocataireViewSet.forcer_automatisations`. "Mode test" (`demarrer_test`) uses in-process `threading.Timer` (demo only).

### Notifications, webhooks, portal
- Dual notifications: in-app `Notification` rows + FCM push via `Loyatrack/utils/firebase.py` (needs `firebase-adminsdk.json`).
- Twilio delivery status: `POST /api/v1/webhooks/twilio/` (`locataires/webhooks.py`) updates `Rappel.statut_livraison` by `message_sid`.
- Portal: `portail.AccesPortail` (per-tenant token); landlord generates a link via `POST /api/v1/portail/generer/`; tenants view a read-only Django-rendered page at `/portail/<token>/`.

### Frontend
`lib/core/api_client.dart` — Dio singleton with a JWT interceptor; services use it plus `api_config.dart` (`baseUrl = http://10.0.2.2:8000/api/v1/`). **Exception:** `firebase_service.dart` and `notification_service.dart` bypass Dio with raw `package:http` and a hardcoded URL — keep in sync. File flows use multipart `FormData` (`uploadPieceIdentite`, `importLocataires`, état-des-lieux `addPhoto`); PDFs are saved + opened via `lib/core/pdf_helper.dart` (`open_filex`).

### Frontend UI conventions
- **Navigation/transitions** (`shared_widgets.dart`): `modalRoute(page)` = bottom-up slide (used **only** for add-locataire / add-paiement); `slideRoute`/`heroRoute` = Cupertino (all other secondary screens). Main tabs use an `IndexedStack` (no route). The 4 tabs keep the `AppBottomNav`; there are **no FABs** — the “+” action lives in each screen's custom sliver header (dashboard/locataires/historique), alongside the **export** button on Historique.
- **Forms in bottom sheets**: creation/action dialogs use `showFormSheet<T>(context, builder: …)` + `sheetHeader(context, title)` (in `shared_widgets.dart`), not `AlertDialog`. Tenant add/edit stays a full page (`AddLocataireScreen`). Reusable creators: `showCreerBien` / `showCreerUnite` (in `biens_screen.dart`) return the created object.
- **Tenant “logement” field** is a unit picker grouped by property (sets `Locataire.unite` FK) with inline “create bien/unité”; selecting a unit prefills rent from `loyer_standard`.
- **Payments export**: `GET /api/v1/paiements/exporter/?fmt=pdf|excel&mode=<FR label>` (filtered list, reuses reportlab/openpyxl). ⚠️ The query param is **`fmt`, not `format`** — `format` collides with DRF content negotiation and 404s.
- Animated sliver headers (réglages, détail locataire) share a pattern: centered group (avatar+name+…) that cross-fades to a left avatar+name row on scroll (`OverflowBox`+`Opacity` keyed on `progress`).
- **Status selector**: the détail-locataire ⋮ menu → "Changer le statut" opens a `showFormSheet` listing the 4 `StatutLocataire` values; selection calls `LocataireService.changerStatut` (→ `PATCH /locataires/{id}/statut/`) then pops `true` to refresh the list. Setting `En discussion` freezes penalties (see Penalty engine).

### Frontend i18n (FR/EN, in progress)
UI is being localized with **gen-l10n** (ARB files in `lib/l10n/app_fr.arb` (template) + `app_en.arb`; `l10n.yaml`; `generate: true`). Use strings via `final t = AppLocalizations.of(context); … t.key` (import `package:flutter_gen/gen_l10n/app_localizations.dart`). After editing ARBs run `flutter gen-l10n`. `lib/core/locale_provider.dart` (Provider, persists to SharedPreferences `app_language`, syncs `ConfigBailleur.langue_interface`) drives `MaterialApp.locale`; FR/EN switch is in Réglages → Apparence. **Default language is French; only display text is translated — DB business values stay French** (statuses, FCFA). Tenant reminder language is separate (`Locataire.langue_preferee`). Rollout is **complete: every screen in `lib/screens/` is translated FR/EN** (`flutter analyze lib` = 0 errors). Localized enum/label helpers live in `models.dart` (`statutLabelL`, `modeLabelL`, `rappelTypeLabelL`, `rappelStatutLabelL`, `relativeDateL`) and per-screen (`notifLabelL`, `typeBienLabelL`, `catDepenseLabelL`). When adding any new user-facing string: add the key to **both** `app_fr.arb` and `app_en.arb`, run `flutter gen-l10n`, and use `AppLocalizations.of(context).key`. The réglages header binds real data (name, email/phone, computed initials, "Bailleur · N biens" from `getProfile()` + `getStats().nombreBiens`).

## Configuration & secrets
- `.env` (read by `django-environ`): `SECRET_KEY`, `DEBUG`, `REDIS_URL`, `TWILIO_*`. Firebase needs `firebase-adminsdk.json`. Uploads served from `MEDIA_ROOT` (`backend/Loyatrack/media/`) under `/media/` in DEBUG.
- These secret files live in the working tree and are **not** gitignored — don't commit them; rotate if exposed.
- Key Python deps beyond `requirements.txt` basics: `reportlab`, `Pillow`, `openpyxl`, `django-environ`, `firebase-admin` (some were missing/transitive historically — install from `requirements.txt`).

## Critical gotchas
- **Impeller is intentionally disabled** in `android/app/src/main/AndroidManifest.xml` (`io.flutter.embedding.android.EnableImpeller=false`). Its Vulkan backend SIGSEGVs on many emulators/weak GPUs (notably when rendering the signature canvas on the tenant form), which presents as the app silently closing. Do **not** re-enable it without testing on the target hardware.
- **Only one `runserver` on port 8000.** A leftover server bound to `127.0.0.1:8000` plus a new one on `0.0.0.0:8000` coexist; the emulator (`10.0.2.2` → host loopback) can hit the stale one → intermittent **404** on newer routes even though the code is correct. If an endpoint 404s unexpectedly, check `netstat -ano | findstr :8000` and kill extra instances.
- **JWT refresh IS implemented** (`api_client.dart` single-flight interceptor: 401 → `auth/token/refresh/` → retry; rotation enabled, `ACCESS=30min`/`REFRESH=14d`). On refresh failure it clears the session and fires `onSessionExpired` → LoginScreen.
- **Frontend fetches only the first DRF page** (`PAGE_SIZE=20`); lists beyond 20 items are truncated.

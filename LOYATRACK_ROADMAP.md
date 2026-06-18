# 🏠 Loyatrack — Roadmap d'implémentation

> Généré suite à l'audit technique du projet Django + Flutter  
> Date : Juin 2026  
> Score initial : **0/14 entièrement implémentés** | 5 partiels | 9 manquants

---

## Légende

| Symbole | Signification |
|---------|---------------|
| ❌ | Manquant — à construire from scratch |
| ⚠️ | Partiel — existe mais à corriger / compléter |
| ✅ | Terminé |
| 🔴 P1 | Priorité critique — bugs ou intégrité financière |
| 🟡 P2 | Priorité haute — structuration & documents |
| 🟢 P3 | Priorité normale — enrichissement fonctionnel |

---

## 🔴 PRIORITÉ 1 — Corrections critiques (bugs & intégrité financière)

> Ces points touchent directement la fiabilité financière de l'application.  
> Ils doivent être traités **avant toute nouvelle fonctionnalité**.

---

### 1.1 ⚠️ Corriger l'algorithme de calcul des pénalités

**Fichiers concernés :** `penalites/tasks.py`, `penalites/models.py`, `penalites/views.py`

**Problème :**  
L'ancien algorithme compare `aujourd_hui.day > locataire.jour_echeance` — ce qui fausse les calculs dès qu'on change de mois (ex : si le locataire est en retard depuis le mois précédent et que le jour courant est inférieur à l'échéance, aucune pénalité n'est générée).

**Ce qui a été corrigé (fichiers déjà générés) :**
- [x] Comparaison par **date absolue** : `date(annee, mois, jour_echeance) + delai_grace`
- [x] Gestion des mois courts (ex : jour 31 en février)
- [x] Délai de grâce **paramétrable par le bailleur** par locataire
- [x] Support pénalité **fixe** (FCFA/jour) ET **pourcentage** du loyer
- [x] Anti-doublon : pas deux pénalités le même jour pour la même période
- [x] Action de **remise / annulation** avec motif obligatoire
- [x] Endpoint `/api/penalites/resume/` pour le tableau de bord

**À faire encore :**
- [ ] Lancer `python manage.py makemigrations penalites && migrate`
- [ ] Initialiser les `ConfigPenalite` pour les locataires existants (voir `GUIDE_MIGRATION.py`)
- [ ] Mettre à jour `urls.py` avec les deux nouveaux ViewSets
- [ ] Planifier la tâche Celery dans `settings.py` (`crontab(hour=1, minute=0)`)
- [ ] Ajouter l'interface Flutter de configuration des pénalités par locataire

---

### 1.2 ⚠️ Refondre la logique des paiements

**Fichiers concernés :** `paiements/models.py`, `paiements/views.py`, `paiements/serializers.py`, `add_paiement_screen.dart`

**Problème :**  
Tout paiement enregistré, quelle que soit la somme, marque le locataire comme `Payé` et remet ses pénalités à zéro — sans vérifier si le montant couvre réellement le loyer dû.

**Ce qui doit être implémenté :**
- [ ] Ajouter les champs `periode_debut` et `periode_fin` (DateField) sur le modèle `Paiement`
- [ ] Ajouter le champ `statut` avec les valeurs : `complet` / `partiel` / `avance`
- [ ] Ajouter le champ `reste_du` calculé automatiquement (`loyer - montant_recu`)
- [ ] Logique de paiement partiel : si `montant < loyer`, statut = `partiel`, reste reporté en dette
- [ ] Logique de paiement en avance (3, 6, 12 mois) : créer les `N` périodes couvertes et décompter mensuellement
- [ ] Logique de fréquence personnalisée (tous les 2 mois, trimestriel, etc.)
- [ ] Génération automatique d'un **reçu PDF** à chaque paiement enregistré
- [ ] Le reçu doit intégrer : loyer dû, montant reçu, reste dû, pénalités incluses
- [ ] Mise à jour de `add_paiement_screen.dart` pour afficher le reste dû en temps réel

---

### 1.3 ⚠️ Persister la signature du locataire

**Fichiers concernés :** `locataires/models.py`, `locataire_service.dart`, `add_locataire_screen.dart`

**Problème :**  
Le tracé de signature est capturé dans Flutter via `SignatureController` mais n'est **jamais envoyé ni sauvegardé** côté backend.

**Ce qui doit être implémenté :**
- [ ] Ajouter le champ `signature_base64` (TextField) sur le modèle `Locataire`
- [ ] Dans `add_locataire_screen.dart`, convertir le tracé en base64 avant l'appel API
- [ ] Inclure `signature_base64` dans le payload envoyé à `createLocataire()`
- [ ] Afficher la signature dans la fiche détail du locataire

---

## 🟡 PRIORITÉ 2 — Structuration & documents

---

### 2.1 ❌ Module multi-biens (Propriete + UniteLogement)

**Fichiers concernés :** `locataires/models.py` (refactoring), nouveaux fichiers `biens/`

**Problème :**  
Le logement est stocké comme un simple champ texte libre `logement` sur le locataire — il est impossible de gérer un parc immobilier, des statistiques par bien ou des taux d'occupation.

**Ce qui doit être implémenté :**
- [ ] Créer le modèle `Propriete` : `titre`, `adresse`, `type` (appartement/villa/studio), `proprietaire`
- [ ] Créer le modèle `UniteLogement` : `numero`, `loyer_standard`, `statut` (occupé/vacant), `propriete` (FK)
- [ ] Migrer le champ `locataire.logement` (texte) vers `locataire.unite` (FK vers `UniteLogement`)
- [ ] Écrire le script de migration des données existantes
- [ ] Créer les endpoints API CRUD pour `Propriete` et `UniteLogement`
- [ ] Écran Flutter : liste des biens avec taux d'occupation et revenus par bien
- [ ] Dashboard consolidé : revenus totaux, impayés totaux, taux d'occupation global

---

### 2.2 ❌ Génération PDF — Contrat de bail & Quittances

**Fichiers concernés :** nouveau module `documents/`, `paiements/views.py`

**Ce qui doit être implémenté :**

**Contrat de bail :**
- [ ] Installer `weasyprint` ou `reportlab` dans `requirements.txt`
- [ ] Créer un template HTML/CSS du contrat de bail (paramétrable)
- [ ] Service Django `generate_bail_pdf(locataire_id)` injectant les données + signature
- [ ] Sauvegarde du PDF en cloud (Firebase Storage ou S3) ou local `/media/contrats/`
- [ ] Endpoint `GET /api/locataires/{id}/contrat/` pour télécharger le PDF
- [ ] Bouton de téléchargement dans `detail_screen.dart`

**Quittances de loyer :**
- [ ] Template HTML de quittance (loyer, pénalités, période, mode de paiement)
- [ ] Génération automatique à chaque création de paiement
- [ ] Endpoint `GET /api/paiements/{id}/quittance/`
- [ ] Bouton de téléchargement dans l'historique des paiements Flutter

---

### 2.3 ❌ Enregistrement locataire — Champs manquants & upload documents

**Fichiers concernés :** `locataires/models.py`, `locataires/serializers.py`, `add_locataire_screen.dart`

**Ce qui doit être implémenté :**
- [ ] Ajouter sur le modèle `Locataire` : `profession`, `revenus_mensuels`, `type_piece_identite`, `numero_piece_identite`
- [ ] Ajouter `FileField` pour upload CNI / Passeport (vers Firebase Storage ou S3)
- [ ] Ajouter `montant_caution` et `statut_caution` (voir point 3.2)
- [ ] Validation regex numéro de téléphone dans le serializer Django
- [ ] Validation `jour_echeance` entre 1 et 31
- [ ] Ajouter les champs manquants dans `add_locataire_screen.dart`
- [ ] Intégrer `image_picker` ou `file_picker` pour uploader la pièce d'identité

---

### 2.4 ❌ Migration des locataires existants

**Fichiers concernés :** nouveau fichier `locataires/management/commands/import_locataires.py`

**Ce qui doit être implémenté :**
- [ ] Créer un template Excel/CSV téléchargeable depuis l'app (colonnes prédéfinies)
- [ ] Endpoint `POST /api/locataires/import/` acceptant un fichier CSV ou Excel (`pandas` + `openpyxl`)
- [ ] Validation des données à l'import avec rapport d'erreurs ligne par ligne
- [ ] Ajouter les champs `solde_initial` (dette de départ) et `date_debut_facturation` sur `Locataire`
- [ ] Interface Flutter : écran d'import avec sélection de fichier et aperçu avant confirmation
- [ ] Commande Django `manage.py import_locataires` pour import en ligne de commande

---

### 2.5 ⚠️ Sécurité — Reset de mot de passe & backups

**Fichiers concernés :** `accounts/views.py`, `settings.py`, nouveau `scripts/backup.sh`

**Ce qui doit être implémenté :**
- [ ] Endpoint `POST /api/auth/forgot-password/` envoyant un lien à token temporaire par email
- [ ] Endpoint `POST /api/auth/reset-password/` validant le token et mettant à jour le mot de passe
- [ ] Script de backup automatique journalier de PostgreSQL vers stockage externe
- [ ] Planification du backup via cron ou tâche Celery Beat
- [ ] Chiffrement des documents sensibles stockés (CNI, contrats)

---

### 2.6 ⚠️ Communication — Webhooks Twilio & messagerie

**Fichiers concernés :** `locataires/services.py`, nouveau `locataires/webhooks.py`

**Ce qui doit être implémenté :**
- [ ] Créer un endpoint webhook `POST /api/webhooks/twilio/` pour recevoir les Status Callbacks
- [ ] Enregistrer les accusés de réception horodatés (livré, lu, échec) par message
- [ ] Afficher le statut de livraison dans l'historique des rappels Flutter
- [ ] (Optionnel) Messagerie interne bailleur ↔ locataire avec historique conservé

---

### 2.7 ❌ Fin de bail & résiliation

**Fichiers concernés :** `locataires/views.py`, `locataires/models.py`

**Problème :**  
La suppression d'un locataire est un simple `is_deleted=True` sans aucun workflow de clôture.

**Ce qui doit être implémenté :**
- [ ] Ajouter le statut `archivé` / `clôturé` sur le modèle `Locataire`
- [ ] Alerte automatique M-2 avant expiration du bail (tâche Celery)
- [ ] Workflow de résiliation : calcul du solde dû, date d'effet, état des lieux de sortie
- [ ] Gestion de la résiliation anticipée (bailleur ou locataire) avec préavis
- [ ] Archivage complet du dossier sans suppression des données

---

## 🟢 PRIORITÉ 3 — Enrichissement fonctionnel

---

### 3.1 ❌ État des lieux

**Ce qui doit être implémenté :**
- [ ] Modèle `EtatDesLieux` : `type` (entrée/sortie), `locataire`, `date`, `observations`
- [ ] Modèle `PhotoEtatDesLieux` : `pièce`, `description`, `photo` (FileField), `horodatage`
- [ ] Interface Flutter avec accès appareil photo pièce par pièce
- [ ] Rapport d'état des lieux en PDF généré automatiquement
- [ ] Comparaison entrée vs sortie pour décision de restitution de caution
- [ ] Signature numérique conjointe bailleur + locataire

---

### 3.2 ❌ Gestion de la caution

**Ce qui doit être implémenté :**
- [ ] Champs `montant_caution`, `date_versement_caution`, `statut_caution` sur `Locataire`
- [ ] Reçu de caution généré automatiquement à l'entrée
- [ ] Workflow de restitution : totale / partielle / nulle avec justificatifs
- [ ] Déductions documentées (impayés, dégradations constatées à l'état des lieux)
- [ ] Historique des mouvements de caution

---

### 3.3 ❌ Augmentation de loyer

**Ce qui doit être implémenté :**
- [ ] Modèle `HistoriqueLoyer` : `locataire`, `montant`, `date_debut`, `date_fin`
- [ ] Mécanisme de révision : fixe ou basé sur un indice paramétrable
- [ ] Alerte automatique au bailleur à date anniversaire
- [ ] Préavis automatique envoyé au locataire (SMS / WhatsApp via Twilio)
- [ ] Le nouveau montant s'applique automatiquement à la date prévue

---

### 3.4 ❌ Comptabilité & export fiscal

**Ce qui doit être implémenté :**
- [ ] Modèle `Depense` : `libelle`, `montant`, `date`, `categorie`, `bien` (FK)
- [ ] Relevé annuel des loyers perçus par bien et global
- [ ] Export Excel des revenus nets/bruts par année fiscale (`openpyxl`)
- [ ] Export PDF du récapitulatif annuel pour le comptable
- [ ] Calcul automatique de la rentabilité par bien (loyers - dépenses)

---

### 3.5 ❌ Portail locataire (accès limité)

**Ce qui doit être implémenté :**
- [ ] Générer un token unique sécurisé par locataire
- [ ] Page web légère (Django template ou React) accessible via lien sécurisé
- [ ] Ce que le locataire peut voir : ses reçus, son historique de paiements, son contrat
- [ ] Ce que le locataire peut faire : signaler un problème, envoyer un message au bailleur
- [ ] Envoi du lien d'accès par SMS (Twilio) à la création du locataire
- [ ] Expiration et renouvellement du token d'accès

---

## 📊 Tableau de suivi global

| # | Module | Statut | Priorité | Terminé |
|---|--------|--------|----------|---------|
| 1.1 | Algorithme pénalités | ⚠️ Partiel | 🔴 P1 | ☐ |
| 1.2 | Paiements partiels / avances | ⚠️ Partiel | 🔴 P1 | ☐ |
| 1.3 | Signature locataire | ⚠️ Partiel | 🔴 P1 | ☐ |
| 2.1 | Module multi-biens | ❌ Manquant | 🟡 P2 | ☐ |
| 2.2 | PDF contrat & quittances | ❌ Manquant | 🟡 P2 | ☐ |
| 2.3 | Champs locataire & upload docs | ⚠️ Partiel | 🟡 P2 | ☐ |
| 2.4 | Migration locataires existants | ❌ Manquant | 🟡 P2 | ☐ |
| 2.5 | Sécurité — reset mdp & backups | ⚠️ Partiel | 🟡 P2 | ☐ |
| 2.6 | Webhooks Twilio & messagerie | ⚠️ Partiel | 🟡 P2 | ☐ |
| 2.7 | Fin de bail & résiliation | ❌ Manquant | 🟡 P2 | ☐ |
| 3.1 | État des lieux | ❌ Manquant | 🟢 P3 | ☐ |
| 3.2 | Gestion de la caution | ❌ Manquant | 🟢 P3 | ☐ |
| 3.3 | Augmentation de loyer | ❌ Manquant | 🟢 P3 | ☐ |
| 3.4 | Comptabilité & export fiscal | ❌ Manquant | 🟢 P3 | ☐ |
| 3.5 | Portail locataire | ❌ Manquant | 🟢 P3 | ☐ |

---

## 🔧 Stack technique de référence

| Couche | Technologie |
|--------|-------------|
| Backend | Django 4.x + Django REST Framework |
| Tâches asynchrones | Celery + Redis |
| Base de données | PostgreSQL |
| Notifications | Firebase Cloud Messaging (FCM) |
| SMS / WhatsApp / Appels | Twilio |
| Génération PDF | WeasyPrint ou ReportLab |
| Import Excel | pandas + openpyxl |
| Stockage fichiers | Firebase Storage ou AWS S3 |
| Frontend mobile | Flutter (Dart) |
| Auth | JWT (SimpleJWT) + flutter_secure_storage |

---

*Document généré par analyse de code — Loyatrack v1 — Mise à jour au fil des implémentations.*

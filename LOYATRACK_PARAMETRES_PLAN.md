# ⚙️ Loyatrack — Plan d'intégration de l'écran Paramètres

> Document de référence pour l'implémentation complète de l'écran
> "Paramètres" du bailleur : profil, sécurité, notifications,
> valeurs financières par défaut, régional/affichage et données.

---

## 0. Corrections d'alignement avec le code réel (appliquées 2026-06-15)

Le plan initial divergeait du code existant sur plusieurs points ; corrigés ci-dessous :

1. **Modèle utilisateur** : c'est `accounts.Bailleur`, pas `accounts.User`. Tous les FK utilisent `settings.AUTH_USER_MODEL`.
2. **Préfixe d'URL** : tout est servi sous `/api/v1/…` (auth sous `/api/v1/auth/…`). Les tableaux d'endpoints ont été corrigés.
3. **L'écran existe déjà** : `frontend/.../lib/screens/reglages_screen.dart` (et non un nouveau `settings_screen.dart`). Il contient déjà les sections, mais les toggles Rappels (`_sms`, `_appel`, `_notif`) et le texte Pénalités sont **non persistés** → on les branche sur `ConfigBailleur`. La 2FA et le mode sombre y sont déjà fonctionnels.
4. **Pénalités — une seule source de vérité** : `Bailleur.penalite_defaut` (DecimalField) existe déjà et est utilisé par le moteur (`penalites/services.py`, `ConfigPenalite.montant_journalier`). On **ne duplique pas** le montant fixe. `ConfigBailleur` n'ajoute donc que les champs *nouveaux* (délai de grâce, type, pourcentage) ; le montant fixe par défaut reste `Bailleur.penalite_defaut`, exposé en écriture par l'endpoint `/api/v1/parametres/`. Le moteur de pénalités n'est pas modifié (zéro risque de régression).
5. **`change-password` (connecté)** : à créer (le module Auth n'a livré que le *reset* par OTP).
6. **Sessions actives** : `rest_framework_simplejwt.token_blacklist` est déjà actif → s'appuyer sur `OutstandingToken`/`BlacklistedToken`. `SessionAppareil` ne sert qu'à ajouter le nom d'appareil (palier optionnel, priorité 🟡).
7. **`fuseau_horaire`** : `settings.TIME_ZONE='UTC'` et les rappels partent d'un crontab global. Un fuseau par bailleur ne décalera pas l'envoi tant que les tâches Celery ne filtrent pas par fuseau → champ stocké en v1, prise en compte effective dans l'envoi = effort séparé (repoussé).

---

## 1. Vue d'ensemble des catégories

| # | Catégorie | Contenu principal |
|---|-----------|--------------------|
| 1 | Compte & Profil | Nom, téléphone, email, photo |
| 2 | Sécurité | 2FA, changement mot de passe, sessions actives |
| 3 | Notifications & Rappels | Canaux Twilio, fréquence des rappels |
| 4 | Paramètres financiers par défaut | Pénalités par défaut, devise |
| 5 | Gestion des biens | Raccourci vers Propriétés / Unités |
| 6 | Régional & Affichage | Langue, devise, fuseau horaire, thème |
| 7 | Données & Sauvegarde | Export, dernière sauvegarde |
| 8 | Aide & À propos | Version, CGU, support |

---

## 2. Compte & Profil

**Champs affichés / modifiables :**
- [ ] Nom, prénom
- [ ] Numéro de téléphone (modification = ré-vérification par OTP, voir plan Auth)
- [ ] Email (optionnel)
- [ ] Photo de profil (upload via `image_picker`)

**Endpoint :**
| Endpoint | Méthode | Description |
|----------|---------|-------------|
| `/api/v1/auth/profil/` | GET / PATCH | Lecture et mise à jour du profil utilisateur |
| `/api/v1/auth/profil/telephone/` | POST | Démarre le changement de téléphone (envoi OTP) |
| `/api/v1/auth/profil/telephone/confirm/` | POST | Confirme le nouveau numéro via OTP |

---

## 3. Sécurité

**Éléments de l'écran :**
- [ ] Toggle "Activer la double authentification" → `POST /api/v1/auth/2fa/toggle/` *(déjà défini dans `LOYATRACK_AUTH_PLAN.md`)*
- [ ] Bouton "Changer le mot de passe" (réutilise le flux OTP du reset password)
- [ ] Liste "Sessions actives" : appareil, date de dernière connexion, localisation approximative
- [ ] Bouton "Déconnecter cet appareil" par session

**Modèle de données — nouveau modèle `SessionAppareil`**
```python
class SessionAppareil(models.Model):
    user = models.ForeignKey(settings.AUTH_USER_MODEL, on_delete=models.CASCADE)
    refresh_token_jti = models.CharField(max_length=255)  # identifiant du refresh token
    nom_appareil = models.CharField(max_length=100, blank=True)
    derniere_connexion = models.DateTimeField(auto_now=True)
    created_at = models.DateTimeField(auto_now_add=True)
```

**Endpoints :**
| Endpoint | Méthode | Description |
|----------|---------|-------------|
| `/api/v1/auth/change-password/` | POST | Change le mot de passe (utilisateur déjà connecté) |
| `/api/v1/auth/sessions/` | GET | Liste les sessions actives |
| `/api/v1/auth/sessions/{id}/` | DELETE | Révoque une session (blackliste le refresh token) |

---

## 4. Notifications & Rappels

**Éléments de l'écran :**
- [ ] Choix du canal de rappel préféré : SMS / WhatsApp / Appel vocal (ou combinaison)
- [ ] Nombre de jours avant l'échéance pour déclencher le rappel automatique (ex : 3 jours avant)
- [ ] Toggle "Rappels automatiques activés"
- [ ] Toggle "Notifications push" (paiement reçu, pénalité appliquée, nouveau message...)

**Champs à ajouter sur `ConfigBailleur` (voir section 6) :**
```python
canal_rappel_prefere = models.CharField(
    max_length=20,
    choices=[('sms', 'SMS'), ('whatsapp', 'WhatsApp'), ('appel', 'Appel vocal')],
    default='sms',
)
jours_avant_rappel = models.PositiveSmallIntegerField(default=3)
rappels_automatiques_actifs = models.BooleanField(default=True)
notifications_push_actives = models.BooleanField(default=True)
```

---

## 5. Paramètres financiers par défaut

> Ces valeurs pré-remplissent le formulaire de création d'un nouveau locataire.
> Le bailleur peut toujours les ajuster cas par cas par la suite.

**Éléments de l'écran :**
- [ ] Délai de grâce par défaut (jours)
- [ ] Type de pénalité par défaut : Fixe / Pourcentage
- [ ] Montant fixe par défaut (FCFA/jour)
- [ ] Pourcentage par défaut (%/jour)
- [ ] Devise utilisée (voir section 6)

**Champs à ajouter sur `ConfigBailleur` :**
```python
delai_grace_defaut = models.PositiveIntegerField(default=0)
type_penalite_defaut = models.CharField(
    max_length=20,
    choices=[('fixe', 'Fixe'), ('pourcentage', 'Pourcentage')],
    default='fixe',
)
pourcentage_penalite_defaut = models.DecimalField(max_digits=5, decimal_places=2, default=0)
# Le MONTANT FIXE par défaut reste `Bailleur.penalite_defaut` (une seule source de vérité,
# déjà utilisé par le moteur). Il est exposé en écriture par l'endpoint /api/v1/parametres/.
```

> Voir la décision de la **section 12** : valeurs par défaut **globales** (Option A) pour la v1.

---

## 6. Régional & Affichage

**Éléments de l'écran :**
- [ ] Langue de l'interface : Français / Anglais
- [ ] Devise : FCFA (par défaut), extensible si expansion internationale
- [ ] Fuseau horaire (pour l'envoi correct des rappels automatiques)
- [ ] Format de date : JJ/MM/AAAA (par défaut)
- [ ] Thème : Clair / Sombre
- [ ] Sons & vibrations pour notifications

**Nouveau modèle `ConfigBailleur` (OneToOne avec `User`)**
```python
class ConfigBailleur(models.Model):
    user = models.OneToOneField(settings.AUTH_USER_MODEL, on_delete=models.CASCADE, related_name='config')

    # Régional & Affichage
    langue_interface = models.CharField(
        max_length=5, choices=[('fr', 'Français'), ('en', 'English')], default='fr'
    )
    devise = models.CharField(max_length=10, default='FCFA')
    fuseau_horaire = models.CharField(max_length=50, default='Africa/Douala')
    format_date = models.CharField(max_length=20, default='DD/MM/YYYY')
    theme = models.CharField(
        max_length=10, choices=[('clair', 'Clair'), ('sombre', 'Sombre')], default='clair'
    )
    sons_notifications = models.BooleanField(default=True)

    # Notifications & Rappels (section 4)
    canal_rappel_prefere = models.CharField(
        max_length=20,
        choices=[('sms', 'SMS'), ('whatsapp', 'WhatsApp'), ('appel', 'Appel vocal')],
        default='sms',
    )
    jours_avant_rappel = models.PositiveSmallIntegerField(default=3)
    rappels_automatiques_actifs = models.BooleanField(default=True)
    notifications_push_actives = models.BooleanField(default=True)

    # Paramètres financiers par défaut (section 5)
    delai_grace_defaut = models.PositiveIntegerField(default=0)
    type_penalite_defaut = models.CharField(
        max_length=20,
        choices=[('fixe', 'Fixe'), ('pourcentage', 'Pourcentage')],
        default='fixe',
    )
    pourcentage_penalite_defaut = models.DecimalField(max_digits=5, decimal_places=2, default=0)
    # montant fixe par défaut = Bailleur.penalite_defaut (pas de duplication, cf. §0.4)

    updated_at = models.DateTimeField(auto_now=True)
```

### 6.1 Langue préférée par locataire (point important)

> Pour que les rappels SMS/WhatsApp automatiques soient envoyés dans
> la langue du **locataire** (et non celle du bailleur), il faut un champ
> séparé sur le modèle `Locataire`.

**Champ à ajouter sur `locataires/models.py` → `Locataire` :**
```python
langue_preferee = models.CharField(
    max_length=5,
    choices=[('fr', 'Français'), ('en', 'English')],
    default='fr',
)
```

- [ ] Ajouter ce champ au formulaire `add_locataire_screen.dart`
- [ ] Dans `locataires/services.py`, sélectionner le template de SMS/WhatsApp selon `locataire.langue_preferee`
- [ ] Prévoir les templates de messages Twilio en français ET en anglais

---

## 7. Données & Sauvegarde

**Éléments de l'écran :**
- [ ] Bouton "Exporter mes données" (lié au module comptabilité — voir roadmap section 3.4)
- [ ] Indicateur "Dernière sauvegarde : JJ/MM/AAAA HH:mm" (si backups automatiques activés — voir roadmap section 2.5)
- [ ] Bouton "Demander une sauvegarde maintenant" (optionnel, pour rassurer l'utilisateur)

**Endpoint :**
| Endpoint | Méthode | Description |
|----------|---------|-------------|
| `/api/v1/parametres/export/` | GET | Génère un export Excel/PDF des données du bailleur |
| `/api/v1/parametres/derniere-sauvegarde/` | GET | Retourne la date de la dernière sauvegarde automatique |

---

## 8. Aide & À propos

**Éléments de l'écran :**
- [ ] Version de l'application (affichage automatique via `package_info_plus`)
- [ ] Lien "Conditions d'utilisation"
- [ ] Lien "Politique de confidentialité"
- [ ] Bouton "Contacter le support" (email ou WhatsApp pré-rempli)
- [ ] Bouton "Évaluer l'application" (lien store)

---

## 9. Endpoints API — Récapitulatif

| Endpoint | Méthode | Description |
|----------|---------|-------------|
| `/api/v1/auth/profil/` | GET / PATCH | Profil utilisateur |
| `/api/v1/auth/profil/telephone/` | POST | Changement de téléphone (étape 1) |
| `/api/v1/auth/profil/telephone/confirm/` | POST | Changement de téléphone (étape 2) |
| `/api/v1/auth/change-password/` | POST | Changement de mot de passe |
| `/api/v1/auth/sessions/` | GET | Liste des sessions actives |
| `/api/v1/auth/sessions/{id}/` | DELETE | Révocation d'une session |
| `/api/v1/auth/2fa/toggle/` | POST | Active/désactive la 2FA *(défini dans le plan Auth)* |
| `/api/v1/parametres/` | GET / PATCH | Lecture/écriture de `ConfigBailleur` |
| `/api/v1/parametres/export/` | GET | Export des données |
| `/api/v1/parametres/derniere-sauvegarde/` | GET | Date de dernière sauvegarde |

---

## 10. Écrans Flutter à créer

| Écran | Fichier suggéré |
|-------|------------------|
| Écran principal Paramètres (liste des catégories) | **`reglages_screen.dart` (existe déjà — à brancher, ne pas recréer)** |
| Édition du profil | `profile_edit_screen.dart` |
| Sécurité (2FA, mot de passe, sessions) | `security_settings_screen.dart` |
| Notifications & Rappels | `notifications_settings_screen.dart` |
| Paramètres financiers par défaut | `financial_defaults_screen.dart` |
| Régional & Affichage | `regional_settings_screen.dart` |
| Données & Sauvegarde | `data_backup_screen.dart` |
| Aide & À propos | `about_screen.dart` |

---

## 11. Ordre d'implémentation recommandé

| Étape | Tâche | Priorité |
|-------|-------|----------|
| 1 | ✅ Créer le modèle `ConfigBailleur` + migration `accounts/0004` | 🔴 |
| 2 | ✅ Endpoint `/api/v1/parametres/` (GET/PATCH, `penalite_defaut` miroir) | 🔴 |
| 3 | ✅ Écran principal `reglages_screen.dart` branché (rappels auto, notif push, pénalité dynamique) | 🔴 |
| 4 | ✅ Section Sécurité : `change-password/` + `change_password_screen.dart` + 2FA (déjà OK) | 🔴 |
| 5 | ✅ `langue_preferee` sur `Locataire` + templates SMS/appel bilingues (`construire_message`) + picker FR/EN dans le formulaire | 🟡 |
| 6 | ✅ Notifications & Rappels : `verifier_echeances` config-driven (canal préféré, jours avant rappel, master) + sélecteur canal/jours dans réglages | 🟡 |
| 7 | ✅ Pré-remplissage de la pénalité du formulaire locataire depuis `penalite_defaut` (Paramètres) | 🟡 |
| 8 | Modèle `SessionAppareil` + gestion des sessions actives | 🟡 |
| 9 | Section Régional & Affichage — ⏳ **langue interface FR/EN faite** (i18n gen-l10n, sélecteur dans Réglages → Apparence, sync `langue_interface`) ; reste devise/fuseau/format date | 🟢 |
| 10 | Section Données & Sauvegarde (export, dernière sauvegarde) | 🟢 |
| 11 | Section Aide & À propos | 🟢 |

---

## 12. Point tranché — défauts financiers : Option A (global)

**Décision (2026-06-15) : Option A — valeurs par défaut globales au bailleur pour la v1.**

- **Pourquoi A** : la cible (petits bailleurs) a rarement des politiques de pénalité différentes *par immeuble* → Option B = complexité inutile (YAGNI) et duplication de 4 champs sur 3 modèles.
- **Mais on garde la porte ouverte à B** sans refonte future :
  1. Centraliser TOUTE la résolution dans **une seule** fonction (`resoudre_config_penalite(locataire)`) sur laquelle le moteur s'appuie. Aujourd'hui la logique est éclatée entre `Locataire.get_penalite_journaliere` et `ConfigPenalite.montant_journalier` → à consolider d'abord. Ajouter le palier `Propriete` deviendra un changement à un seul endroit.
  2. Résolution **null-aware** : la priorité doit se baser sur « valeur *explicitement* définie », pas « la ligne existe » (un `ConfigPenalite` existe souvent avec `montant_fixe=NULL`).
  3. Si B un jour : ne **pas copier** les champs sur `Propriete` — les regrouper dans un mixin abstrait / petit modèle réutilisable partagé.

> Chaîne de priorité cible (le jour où B sera fait) :
> `Locataire` (spécifique) > `Propriete` (par bien) > `ConfigBailleur` (global) > `Bailleur.penalite_defaut` (repli ultime).

---

*Document généré dans le cadre de la planification du module Paramètres — Loyatrack v1.*

# 🔐 Loyatrack — Plan d'intégration du module Authentification

> Document de référence pour l'implémentation du système de connexion,
> de la double authentification (2FA), de la réinitialisation de mot de passe
> et de la gestion de session persistante.

---

## 1. Vue d'ensemble des décisions prises

| Sujet | Décision |
|-------|----------|
| Identifiant de connexion | **Numéro de téléphone** + mot de passe (email optionnel en complément) |
| Double authentification (2FA) | **Optionnelle**, activable par l'utilisateur dans ses paramètres, via code OTP SMS (Twilio) |
| Réinitialisation mot de passe | Code OTP envoyé par **SMS via Twilio** (pas par email) |
| Persistance de session | **JWT access token + refresh token**, stockés via `flutter_secure_storage` |
| Durée access token | 30 minutes |
| Durée refresh token | 14 jours, avec **rotation automatique** |
| Reconnexion forcée | Seulement après **2 semaines d'inactivité totale** |

---

## 2. Connexion (Login)

### 2.1 Flux

```
Utilisateur saisit :
  - Numéro de téléphone
  - Mot de passe
        ↓
Backend vérifie les identifiants
        ↓
   ┌────────────────┴────────────────┐
   │                                  │
2FA désactivée                   2FA activée
   │                                  │
Connexion directe          Génération + envoi OTP SMS (Twilio)
   │                                  │
   │                          Saisie du code OTP
   │                                  │
   └──────────────┬───────────────────┘
                   ↓
       Génération access_token + refresh_token
                   ↓
          Stockage sécurisé (flutter_secure_storage)
                   ↓
            Accès au tableau de bord
```

### 2.2 Modifications backend

**`accounts/models.py`**
- [ ] Vérifier que `User` utilise `numero_telephone` comme `USERNAME_FIELD`
- [ ] Ajouter le champ `email` comme optionnel (`blank=True, null=True`)
- [ ] Ajouter le champ `deux_fa_active` (BooleanField, défaut `False`)

**Nouveau modèle `CodeVerification`**
```python
class CodeVerification(models.Model):
    TYPE_CHOICES = [
        ('2fa', 'Double authentification'),
        ('reset_password', 'Réinitialisation mot de passe'),
    ]

    user = models.ForeignKey('accounts.User', on_delete=models.CASCADE)
    code_hash = models.CharField(max_length=128)  # code haché, jamais en clair
    type_code = models.CharField(max_length=20, choices=TYPE_CHOICES)
    expire_at = models.DateTimeField()
    tentatives = models.PositiveSmallIntegerField(default=0)
    utilise = models.BooleanField(default=False)
    created_at = models.DateTimeField(auto_now_add=True)
```

**Endpoints à créer (`accounts/views.py`)**

| Endpoint | Méthode | Description |
|----------|---------|-------------|
| `/api/auth/login/` | POST | Vérifie téléphone + mot de passe |
| `/api/auth/login/verify-otp/` | POST | Valide le code OTP si 2FA activée, retourne les tokens |
| `/api/auth/2fa/toggle/` | POST | Active / désactive la 2FA pour l'utilisateur connecté |

### 2.3 Logique de l'endpoint `/api/auth/login/`

- [ ] Vérifier `numero_telephone` + `mot_de_passe`
- [ ] Si invalide → erreur 401
- [ ] Si valide ET `deux_fa_active == False` → générer directement `access_token` + `refresh_token`
- [ ] Si valide ET `deux_fa_active == True` :
  - Générer un code à 6 chiffres
  - Le hacher et l'enregistrer dans `CodeVerification` (`type_code='2fa'`, `expire_at` = +5 min)
  - Envoyer le code via Twilio SMS
  - Retourner une réponse indiquant "OTP requis" (sans tokens)

### 2.4 Logique de l'endpoint `/api/auth/login/verify-otp/`

- [ ] Recevoir `user_id` (ou téléphone) + `code`
- [ ] Vérifier que le code correspond, n'est pas expiré, et `utilise == False`
- [ ] Limiter à **3 tentatives** — au-delà, invalider le code et exiger une nouvelle demande
- [ ] Si correct → marquer `utilise = True`, générer `access_token` + `refresh_token`

---

## 3. Réinitialisation du mot de passe

### 3.1 Flux

```
Utilisateur clique "Mot de passe oublié"
        ↓
Saisie du numéro de téléphone
        ↓
Backend génère un code OTP (6 chiffres)
        ↓
Envoi du code via Twilio SMS
        ↓
Utilisateur saisit le code reçu
        ↓
Code valide ? ──── Non ──→ Erreur / nouvelle demande possible après 60s
        │
       Oui
        ↓
Saisie du nouveau mot de passe (x2 pour confirmation)
        ↓
Mot de passe mis à jour
        ↓
Redirection vers la page de connexion
```

### 3.2 Endpoints à créer

| Endpoint | Méthode | Description |
|----------|---------|-------------|
| `/api/auth/password/forgot/` | POST | Reçoit le téléphone, envoie l'OTP par SMS |
| `/api/auth/password/verify-otp/` | POST | Vérifie le code OTP de réinitialisation |
| `/api/auth/password/reset/` | POST | Définit le nouveau mot de passe (après vérification OTP) |

### 3.3 Détails d'implémentation

- [ ] `/forgot/` : générer un code, l'enregistrer dans `CodeVerification` (`type_code='reset_password'`, `expire_at` = +5 min)
- [ ] Limiter l'envoi à **1 SMS par minute** par numéro (anti-spam / coût Twilio)
- [ ] `/verify-otp/` : retourne un **token temporaire de réinitialisation** (court, ex: 10 min) si le code est correct — ce token sera requis par `/reset/`
- [ ] `/reset/` : vérifie le token temporaire + applique le nouveau mot de passe (hashé via Django `set_password`)
- [ ] Invalider tous les `refresh_token` existants de l'utilisateur après un changement de mot de passe (sécurité)

---

## 4. Gestion de session — Access token & Refresh token

### 4.1 Configuration Django (SimpleJWT)

**`settings.py`**
```python
from datetime import timedelta

SIMPLE_JWT = {
    'ACCESS_TOKEN_LIFETIME': timedelta(minutes=30),
    'REFRESH_TOKEN_LIFETIME': timedelta(days=14),
    'ROTATE_REFRESH_TOKENS': True,
    'BLACKLIST_AFTER_ROTATION': True,
    'UPDATE_LAST_LOGIN': True,
}
```

- [ ] Vérifier que `rest_framework_simplejwt.token_blacklist` est dans `INSTALLED_APPS`
- [ ] Lancer la migration du blacklist : `python manage.py migrate token_blacklist`

### 4.2 Flux de restauration de session (côté Flutter)

```
Ouverture de l'app
        ↓
Lecture des tokens depuis flutter_secure_storage
        ↓
access_token présent et valide ? ──── Oui ──→ Accès direct au tableau de bord
        │
        Non
        ↓
refresh_token présent et valide (< 14 jours) ?
        │
   ┌────┴────┐
  Oui        Non
   │          │
Appel /api/token/refresh/    Suppression des tokens stockés
   │                                  │
Nouveaux tokens stockés         Redirection vers page de connexion
   │
Accès au tableau de bord
```

### 4.3 Tâches Flutter

**`auth_service.dart`**
- [ ] Méthode `restaurerSession()` appelée au démarrage de l'app
- [ ] Intercepteur Dio/HTTP : si une requête API retourne `401`, appeler automatiquement `/api/token/refresh/`
- [ ] Si le refresh échoue → effacer les tokens (`flutter_secure_storage`) → rediriger vers `LoginScreen`
- [ ] Stocker `access_token`, `refresh_token`, et `deux_fa_active` (préférence utilisateur) localement

**Écran de paramètres**
- [ ] Ajouter un toggle "Activer la double authentification" qui appelle `/api/auth/2fa/toggle/`

---

## 5. Sécurité — Règles transverses

- [ ] **Aucun code OTP stocké en clair** — toujours haché (ex: `hashlib.sha256`)
- [ ] **Expiration des codes OTP** : 5 minutes maximum
- [ ] **Limitation des tentatives** : 3 essais max par code, sinon invalidation
- [ ] **Limitation d'envoi SMS** : 1 envoi par minute par numéro (protection coût Twilio + anti-spam)
- [ ] **Rotation des refresh tokens** : chaque utilisation invalide l'ancien et émet un nouveau
- [ ] **Invalidation globale** : tout changement de mot de passe blackliste tous les refresh tokens actifs de l'utilisateur
- [ ] **Logs de sécurité** : enregistrer les tentatives de connexion échouées (pour détection de brute-force future)

---

## 6. Ordre d'implémentation recommandé

| Étape | Tâche | Priorité |
|-------|-------|----------|
| 1 | Modèle `CodeVerification` + migration | 🔴 |
| 2 | Endpoint `/api/auth/login/` (sans 2FA d'abord) | 🔴 |
| 3 | Configuration SimpleJWT (durées + rotation + blacklist) | 🔴 |
| 4 | Intercepteur Flutter (refresh automatique) | 🔴 |
| 5 | Endpoints reset password (`/forgot/`, `/verify-otp/`, `/reset/`) | 🟡 |
| 6 | Endpoint `/api/auth/2fa/toggle/` + champ `deux_fa_active` | 🟡 |
| 7 | Logique 2FA dans `/api/auth/login/` + `/verify-otp/` | 🟡 |
| 8 | Toggle 2FA dans l'écran paramètres Flutter | 🟢 |
| 9 | Logs de sécurité / détection brute-force | 🟢 |

---

## 7. Stack utilisée pour ce module

| Élément | Technologie |
|---------|-------------|
| Authentification | Django REST Framework + SimpleJWT |
| Envoi OTP | Twilio (déjà intégré dans le projet) |
| Stockage tokens (mobile) | `flutter_secure_storage` |
| Hachage des codes OTP | `hashlib` (SHA-256) |
| Hachage des mots de passe | Django `set_password` (PBKDF2 par défaut) |

---

*Document généré dans le cadre de la planification du module Authentification — Loyatrack v1.*

# LOYATRACK — Coûts de mise en production

> Hypothèses : app **Android d'abord** (public principal au Cameroun), backend sur **Render**, paiement **CinetPay**.
> Taux de change indicatif : **600 FCFA ≈ 1 USD**. Prix indicatifs (évoluent dans le temps).
> Légende : **Fixe** = mensuel garanti · **Usage** = proportionnel à l'activité · **1×** = une seule fois.

---

## 1. Hébergement backend (obligatoire)

| Outil | Rôle | Prix/mois | Type |
|---|---|---|---|
| Render — Web Service (Starter) | API Django (gunicorn), ne s'endort pas | 7 $ | Fixe |
| Render — PostgreSQL (payant) | Base de données persistante | 7 $ | Fixe |
| Render — Background Worker | Celery (rappels, pénalités, expirations) | 7 $ | Fixe |
| Render — Key Value (Redis) | Broker Celery | 0 $ (offre gratuite 25 Mo) → 10 $ | Fixe |
| **Sous-total** | | **≈ 21 $/mois** | |

💡 **Alternative économique — VPS unique** (Hetzner ~5 €, Contabo/DigitalOcean ~6 $) hébergeant tout (Django + Postgres + Redis + Celery) : **~6 $/mois** au lieu de 21 $, mais auto-géré (nginx, sauvegardes, mises à jour, certbot).

## 2. Domaine & sécurité

| Outil | Rôle | Prix | Type |
|---|---|---|---|
| Nom de domaine `.com` | ex. loyatrack.com | ~12 $/an (~1 $/mois) | Fixe |
| Certificat HTTPS / SSL | Chiffrement | 0 $ (auto Render / Let's Encrypt) | — |

*(Un `.cm` camerounais coûte plus cher : ~50–100 $/an.)*

## 3. Stockage des fichiers (pièces d'identité, photos état des lieux)

| Outil | Prix | Type |
|---|---|---|
| **Cloudflare R2** (10 Go gratuits) **ou** Render Disk | 0 $ au début (puis ~0,015 $/Go, **pas d'egress**) | Usage |

> ℹ️ **Précision** : les images (pièces d'identité = `FileField`, photos d'état des lieux = `ImageField`) sont gérées par le **système MEDIA de Django**, **pas par Firebase**. Firebase ne sert qu'aux **notifications push (FCM)** — gratuit, section 4.
> En dev, les fichiers vont sur le disque local ; en prod sur Render le disque est **éphémère** → on branche **Cloudflare R2** via `django-storages` (implémenté : activer en définissant `R2_BUCKET` & co dans l'environnement). Coût ≈ **0 $** au démarrage (10 Go gratuits).

## 4. Notifications

| Outil | Rôle | Prix | Type |
|---|---|---|---|
| Firebase Cloud Messaging (FCM) | Push mobile | 0 $ (gratuit) | — |
| Email transactionnel (Brevo / SendGrid) | Reset mot de passe, reçus | 0 $ (offre gratuite ~300/jour) | Fixe |

## 5. Rappels SMS / WhatsApp / Appels — Twilio (usage)

| Élément | Prix indicatif |
|---|---|
| Numéro Twilio | ~1–2 $/mois |
| SMS vers Cameroun | ~0,04–0,08 $/SMS |
| WhatsApp / Appel vocal | ~0,005–0,08 $ / ~0,15 $ par min |
| **Estimation petit volume** | **≈ 10–30 $/mois** |

⚠️ Coût **variable** selon l'activité — c'est ce que couvre l'abonnement **Pro**. Un agrégateur SMS **local camerounais** peut être moins cher que Twilio.

## 6. Paiement abonnement — CinetPay (commission)

| Élément | Prix |
|---|---|
| Frais d'installation / mensuels | 0 $ (généralement) |
| Commission par transaction | **~3,5 %** du montant encaissé |

## 7. Boutiques d'applications

| Outil | Prix | Type |
|---|---|---|
| **Google Play** (compte développeur) | **25 $** | 1× (à vie) |
| Apple App Store (optionnel, iOS) | 99 $/an + Mac ou CI (Codemagic gratuit possible) | Fixe |

## 8. Optionnels recommandés

| Outil | Rôle | Prix |
|---|---|---|
| Sentry | Suivi des erreurs en prod | 0 $ (offre gratuite) |
| GitHub Actions / Codemagic | CI/CD (builds automatisés) | 0 $ (offres gratuites) |

---

## 💰 Totaux (Android, lancement)

### Option A — Render (simple, géré)
- **Fixe mensuel** : hébergement 21 $ + domaine 1 $ = **~22 $/mois**
- **\+ Usage Twilio** : ~15 $/mois (estimé) → **~37 $/mois ≈ 22 000 FCFA/mois**
- **Une seule fois** : Google Play **25 $** (~15 000 FCFA)
- **\+ CinetPay** : 3,5 % sur chaque paiement encaissé

### Option B — VPS (économique)
- **Fixe mensuel** : VPS 6 $ + domaine 1 $ = **~7 $/mois**
- **\+ Usage Twilio** : ~15 $/mois → **~22 $/mois ≈ 13 000 FCFA/mois**
- **Une seule fois** : Google Play **25 $**
- **\+ CinetPay** : 3,5 %

### Ajout iOS (plus tard)
- Apple Developer : **99 $/an** (~8 $/mois) + build Mac/CI (gratuit possible via Codemagic).

---

## Synthèse

- **Coût de démarrage Android : ~13 000 à 22 000 FCFA / mois** + **25 $ une fois** (Google Play) + coûts proportionnels (Twilio, commission CinetPay 3,5 %).
- **Gratuit** : FCM (push), SSL, email de base, stockage initial (R2), Sentry, CI/CD.
- **Seuls coûts fixes incompressibles** : hébergement + domaine. Le reste (Twilio, CinetPay) est **proportionnel à l'activité** et financé par les abonnements Pro.
- Pour minimiser : démarrer en **Option B (VPS)** + Twilio remplacé par un **agrégateur SMS local** si volume important.

# LOYATRACK — Plan d'implémentation : Abonnements (essai + 2 plans)

> Statut : **plan validé pour rédaction**, pas encore implémenté.
> Décisions actées : distribution multi-stores (Play/App Store/UptoDown) ; **paiement sur le web via agrégateur (CinetPay), apps = lecture du statut** ; découpage **par fonctionnalité** ; essai **14 jours** puis **blocage total** ; prestataire branché **plus tard** (code agnostique).

---

## 1. Principes directeurs

1. **L'app ne contient aucun paiement.** Le bailleur s'abonne sur un **espace web** (paiement CinetPay/MoMo+carte). Les apps mobiles **lisent seulement le statut** via l'API → conforme Apple **et** Google, zéro commission de store, présence sur tous les stores.
2. **Le gating est serveur d'abord.** Toute restriction (essai expiré, fonction Pro) est imposée par l'**API et les tâches Celery**, jamais uniquement par l'UI Flutter (qui ne fait que refléter).
3. **Agnostique du prestataire.** Une interface de paiement abstraite ; CinetPay (ou autre) est une implémentation branchable. Un `FakeProvider` permet de tout développer/tester sans compte marchand.
4. **Multi-tenant déjà en place.** Tout est scopé par `Bailleur` ; l'abonnement est rattaché au bailleur.

---

## 2. Découpage Essentiel / Pro (matrice)

| Fonctionnalité | Essentiel | Pro |
|---|:---:|:---:|
| Locataires, paiements, statuts, **quittance PDF** | ✅ | ✅ |
| Pénalités **manuelles** (créer/remettre) | ✅ | ✅ |
| Notifications **in-app** | ✅ | ✅ |
| Rappels **manuels** (le bailleur déclenche) | ✅ | ✅ |
| 1 bien / 1 unité de base | ✅ | ✅ |
| **Rappels automatiques** SMS / WhatsApp / vocal (Twilio) | ❌ | ✅ |
| **Pénalités automatiques** (Celery) | ❌ | ✅ |
| **Multi-biens / unités illimités** | ❌ | ✅ |
| **Comptabilité & rapports** (relevé annuel, exports) | ❌ | ✅ |
| **Documents légaux** (contrat de bail, état des lieux) | ❌ | ✅ |
| **Portail locataire** | ❌ | ✅ |
| Import en masse de locataires | ❌ | ✅ |

> Rationale : tout ce qui **coûte en récurrent** (Twilio) ou apporte une **forte valeur** est en Pro. L'Essentiel n'engendre aucun coût opérateur.

**Tarifs (à valider, FCFA)** : Essentiel ~2 500–3 500/mois ; Pro ~7 500–10 000/mois ; **remise annuelle ≈ 2 mois offerts**.

---

## 3. Backend — modèle de données

Nouvelle app Django **`abonnements`** (ajoutée à `INSTALLED_APPS`).

### 3.1 `Abonnement` (OneToOne `Bailleur`)
- `bailleur` — OneToOneField(Bailleur, related_name='abonnement')
- `plan` — CharField choices `('essentiel','pro')` — niveau de droits courant
- `statut` — CharField choices `('essai','actif','expire','annule')` (default `essai`)
- `date_debut` — DateTimeField(auto_now_add)
- `date_fin_essai` — DateTimeField (= inscription + 14 j)
- `date_fin` — DateTimeField(null=True) — fin de période payée
- `periodicite` — CharField `('mensuel','annuel')` (null tant qu'essai)
- `date_derniere_relance` — DateField(null=True) — anti-spam des rappels d'expiration

**Propriétés calculées :**
- `est_actif` → `statut=='essai'` et `now <= date_fin_essai`, **ou** `statut=='actif'` et `now <= date_fin`.
- `droits` → `'pro'` pendant l'essai (on offre le Pro à l'essai), sinon `plan` si actif, sinon `None`.
- `jours_restants` → essai ou période payée.

### 3.2 `TransactionAbonnement`
- `bailleur` (FK), `plan`, `periodicite`, `montant` (Decimal), `devise` ('XAF')
- `statut` — `('en_attente','reussi','echoue','annule')`
- `prestataire` — CharField ('cinetpay','fake', …)
- `reference_externe` — id transaction côté prestataire (unique, indexé)
- `reference_interne` — UUID généré par nous (envoyé au prestataire)
- `payload` — JSONField (réponse/webhook brut, pour audit)
- `date_creation`, `date_paiement` (null)

### 3.3 Catalogue des plans
Constantes Python `PLANS` (pas de modèle) : prix mensuel/annuel par plan + liste des features incluses. Source unique de vérité côté backend, exposée en lecture à l'app.

```python
PLANS = {
  'essentiel': {'mensuel': 3000, 'annuel': 30000, 'features': [...]},
  'pro':       {'mensuel': 8000, 'annuel': 80000, 'features': [...]},
}
FEATURES_PRO = {'rappels_auto','penalites_auto','multi_biens','comptabilite',
                'documents_legaux','portail','import_masse'}
```

### 3.4 Création auto à l'inscription
Hook dans le flux `register` (accounts) : à la création d'un `Bailleur`, créer `Abonnement(statut='essai', plan='pro', date_fin_essai=now+14j)`. Signal `post_save` ou explicite dans la vue d'inscription.
**Migration de données (décidé)** : pour les **bailleurs existants** à la mise en prod → **Pro de courtoisie 1 mois** (`statut='actif'`, `plan='pro'`, `date_fin=now+1 mois`), pas un simple essai 14 j. Geste commercial pour les premiers utilisateurs avant bascule payante.

### 3.5 Période de grâce (décidé : 3 jours)
À l'expiration de `date_fin` (abo payé) : **3 jours de grâce** avant le blocage total, avec notifications **J0 / J+1 / J+2**. Absorbe les accidents Mobile Money (solde, réseau, maintenance opérateur) sans tolérer le vrai non-paiement.
- Statut intermédiaire `'grace'` ajouté à `Abonnement.statut` → `('essai','actif','grace','expire','annule')`.
- `est_actif` inclut `'grace'` tant que `now <= date_fin + 3 j`.
- Au-delà de `date_fin + 3 j` → `'expire'` (blocage total).
- ⚠️ L'**essai** n'a **pas** de grâce (14 j puis blocage direct, conforme à la décision « blocage total » de fin d'essai).

---

## 4. Backend — gating (le cœur)

### 4.1 Accès global (essai/abonnement)
Permission DRF **`AbonnementActifOuLecture`** :
- Si `abonnement.est_actif` → accès normal.
- Sinon (expiré) → **blocage total** : `403` avec corps `{"code":"abonnement_expire", ...}` sur **toutes** les routes, **sauf liste blanche** : auth (login/refresh/register), `GET/PUT abonnement` (statut + lancement renouvellement), logout, profil minimal.
- Appliquée comme `DEFAULT_PERMISSION_CLASSES` (après `IsAuthenticated`) ou via un mixin sur les viewsets métier.

### 4.2 Fonctions Pro
Helper `bailleur.peut(feature)` + permission **`RequierePro(feature)`** / décorateur sur les actions :
- `config rappels automatiques` (ConfigBailleur `rappels_automatiques_actifs`), `penalites auto`, création de bien/unité au-delà de 1, endpoints `comptabilite`, actions `contrat` / `etat_des_lieux`, `portail/generer`, `locataires/importer`.
- Réponse `403 {"code":"fonction_pro"}` → l'app affiche un **upsell**.

### 4.3 ⚠️ Gating dans Celery (indispensable)
Les tâches beat **contournent les permissions HTTP**. Donc :
- `verifier_echeances` / `calculer_penalites` / augmentations : **filtrer les bailleurs `est_actif` ET droits incluant la feature** (ex. ne pas envoyer de rappels auto à un bailleur Essentiel ou expiré). Sinon coûts Twilio non facturés.

---

## 5. Backend — API

| Méthode | Route | Rôle |
|---|---|---|
| `GET` | `/api/v1/abonnement/` | Statut courant : plan, statut, `jours_restants`, `droits`, liste features débloquées |
| `GET` | `/api/v1/abonnement/plans/` | Catalogue + prix (pour affichage app, **sans** bouton de paiement in-app) |
| `POST` | `/api/v1/abonnement/checkout/` | (Web) crée une `TransactionAbonnement` + renvoie l'URL de paiement prestataire |
| `GET` | `/api/v1/abonnement/transaction/<ref>/` | Polling du statut d'une transaction (page de retour web) |
| `POST` | `/api/v1/webhooks/<prestataire>/` | Webhook d'activation (signature vérifiée, idempotent) |

---

## 6. Backend — intégration paiement (abstraite)

Package `abonnements/providers/` :
- `base.py` — interface `PaiementProvider` : `creer_paiement(transaction) -> redirect_url`, `verifier(reference) -> statut`, `parse_webhook(request) -> (reference, statut, payload)`, `verifier_signature(request) -> bool`.
- `fake.py` — `FakeProvider` (dev/tests) : marque la transaction réussie immédiatement.
- `cinetpay.py` — **plus tard** : init paiement, page de retour, webhook signé.
- Sélection via `settings.PAIEMENT_PROVIDER` (env).

**Activation (idempotente)** — à la réception d'un webhook `reussi` :
1. retrouver la transaction par `reference_interne`/`externe` ; ignorer si déjà `reussi` ;
2. passer `Abonnement` → `statut='actif'`, `plan=<plan acheté>`, `periodicite`, `date_fin = max(now, date_fin) + (1 mois|1 an)` ;
3. créer une `Notification` + (option) reçu d'abonnement PDF.

---

## 7. Espace bailleur web (Django, comme le portail)

- App/section web : connexion par **magic-link (décidé)** depuis l'app (« Gérer mon abonnement » → ouvre le navigateur avec un token). **Garde-fous obligatoires** : token **à usage unique** (invalidé dès la 1ʳᵉ utilisation) **et** expiration **≤ 10 minutes**. Modèle `JetonAccesBailleur` (token, bailleur, date_creation, utilise:bool) — réutilise le motif de `portail.AccesPortail`.
- Pages : **choix du plan** (mensuel/annuel) → **lancement paiement** (redirect prestataire) → **retour succès/échec** → **gestion** (statut, date de fin, renouveler).
- Rendu serveur (templates), même style sobre que le portail locataire.

---

## 8. Frontend Flutter

- **`AbonnementService.getStatut()`** + modèle `Abonnement` (plan, statut, joursRestants, droits/features).
- **Intercepteur Dio** : sur `403 code=abonnement_expire` → router vers **`PaywallScreen`** (essai terminé, comparatif des plans, bouton **« Gérer mon abonnement »** → `url_launcher` vers le web avec magic-token). *Pas de paiement dans l'app.*
- **Bannière d'essai** : « Essai — J-N restants » (dashboard) ; à J-3 plus visible.
- **Verrous Pro** : sur les écrans/fonctions gated (compta, documents, rappels auto, multi-biens, portail), badge **« Pro »** ; au tap → feuille d'upsell renvoyant au web.
- **i18n** : toutes les chaînes en FR + EN (ARB) comme le reste de l'app.
- **Conformité iOS (anti-steering)** : sur la build iOS, pas de CTA de paiement direct ; formulation neutre (« gérez votre abonnement sur votre espace en ligne »).

---

## 9. Tâches Celery (beat — déjà en place)

- **`expirer_abonnements`** (quotidien) : essais/abos dont la date est passée → `statut='expire'`.
- **`rappels_expiration`** (quotidien) : J-3 / J-1 / J0 → Notification in-app + (option) e-mail/SMS au **bailleur** ; `date_derniere_relance` anti-doublon.
- **Garde-fous** ajoutés aux tâches métier existantes (cf. §4.3).

---

## 10. Sécurité & conformité

- Gating **serveur** systématique (API + Celery) ; l'UI n'est qu'un reflet.
- Webhooks : **vérification de signature** + activation **idempotente** (rejouer un webhook ne double pas la période).
- Aucune route de paiement dans les builds stores ; le paiement vit sur le web.
- `TransactionAbonnement.payload` conservé pour audit/litige.

---

## 11. Phases de livraison

- **Phase 1 — Fondation backend** : ✅ **FAITE** (2026-06-18). App `abonnements` (modèles `Abonnement` + `TransactionAbonnement`, migrations 0001 + 0002 courtoisie 1 mois), essai auto 14 j (signal post_save), statut `grace` (3 j), gating API (`AbonnementActif` + `requiere_pro(feature)` sur locataires/paiements/biens/penalites/comptabilite/portail/état des lieux/contrat/import/export), garde-fous Celery (rappels_auto, penalites_auto), API `GET /abonnement/`, `/abonnement/plans/`, `POST /abonnement/checkout/`, `POST /webhooks/paiement/`, `FakeProvider`. **14 tests** verts + suite globale 55/55 sans régression. Smoke test live OK.
- **Phase 2 — App Flutter** : ✅ **FAITE** (2026-06-18). Modèle `Abonnement` + `featureLabelL` (models.dart), `AbonnementService` (getStatut/getPlans), `AbonnementProvider` (core/), intercepteur Dio (403 `abonnement_expire`→`onSubscriptionExpired`, `fonction_pro`→`onProRequired`), `PaywallScreen` + `showProUpsell()` (paiement renvoyé vers le web via `ApiConfig.manageSubscriptionUrl`, **aucun paiement in-app**), bannière d'essai sur le dashboard, refresh au démarrage (MainShell), hooks branchés dans main.dart. i18n FR/EN (subTitleExpired, subManage, subTrialBanner{days}, subProTitle/Body, subUpgrade, feat* …). `flutter analyze lib` = 0 erreur. ⚠️ Reste possible (polish) : badges « Pro » proactifs par écran (le provider expose `aDroit()`), aujourd'hui couverts par l'upsell réactif au 403.
- **Phase 3 — Web + CinetPay** : ✅ **FAITE** (2026-06-18). Magic-link `JetonAccesBailleur` (usage unique, ≤10 min) + endpoint `POST /abonnement/lien-web/` ; espace web bailleur (Django sessions, templates `abonnements/templates/`) : `acces_web` (consomme le jeton + `login()`), `espace_abonnement` (choix plans), `payer` (→ provider), `checkout_fake` (simulation dev), `retour_paiement` ; `CinetPayProvider` (squelette API v2 : init + check + HMAC, branché par `PAIEMENT_PROVIDER=cinetpay` + `CINETPAY_*` en .env, défaut `fake`) ; tâche Celery `rappels_expiration` (J-3/J-1/J0 + grâce, throttle quotidien) + beat 8h30 ; Flutter : `getLienWeb()` + paywall ouvre le magic-link (repli URL statique). **18 tests** abonnements + suite globale 59/59. Smoke test live du flux web OK (magic-link→session→usage unique). **Reste pour la prod** : compte marchand CinetPay (clés .env) + URL web https réelle dans `ApiConfig.manageSubscriptionUrl` + `CINETPAY_RETURN/NOTIFY_URL`.
- **Phase 4 — Finitions** : ✅ **FAITE** (2026-06-18). Admin Django (`abonnements/admin.py` : Abonnement, TransactionAbonnement avec **total revenus** sur la changelist, JetonAccesBailleur) ; **reçu PDF d'abonnement** (`abonnements/pdf.py` + vue web `recu_web` + lien sur la page de retour) ; **badges Pro proactifs** Flutter (`widgets/pro_gate.dart` : `ProBadge`, `ProBadgeIfLocked`, `exigerFonction()`) câblés sur l'export Historique (comptabilite) et le contrat de bail (documents_legaux) — les autres fonctions restent couvertes par l'upsell réactif au 403. Remise annuelle déjà intégrée (2 mois offerts). 20 tests abonnements + suite globale 61/61. *Non retenu pour l'instant : dunning post-expiration (win-back) et analytics de conversion — à ajouter si besoin.*

---

## 12. Décisions (actées le 2026-06-18 — cf. `desision.txt`)

1. **Prix** — ✅ **FIGÉS** (choix user) : Essentiel **3 000 / 30 000 FCFA** (mois/an), Pro **8 000 / 80 000 FCFA**. Benchmark concurrentiel fait (§13) ; le user retient ses valeurs initiales (positionnement premium assumé).
2. **Période de grâce** — ✅ **3 jours** avec notifications J0/J+1/J+2 (statut `grace`). Cf. §3.5. *(L'essai, lui, n'a pas de grâce.)*
3. **Bailleurs existants** — ✅ **Pro de courtoisie 1 mois** à la mise en prod (pas un essai 14 j). Cf. §3.4.
4. **Limite « 1 bien » Essentiel** — ✅ **bloquer la création du 2ᵉ bien** (pas de « saisie autorisée mais masquée »). Cf. §4.2.
5. **Connexion web** — ✅ **magic-link**, token **à usage unique** + expiration **≤ 10 min**. Cf. §7.

## 13. Benchmark prix (recherche du 2026-06-18)

**Concurrent direct — Proprio Fiable** (Cameroun/Gabon/Congo ; portail locataire, rappels WhatsApp, signature électronique, IA rentabilité), prix **App Store** (donc gonflés ~30 % par la commission Apple) :
- Pro **3,99 $/mois** (~2 400 FCFA) · Premium **6,99 $/mois** (~4 200 FCFA) · Agence **11,99 $/mois** (~7 200 FCFA).

**Autres acteurs CM repérés** (tarifs non publiés) : Kinaru, Kamer Location, HOMECM. Rentila (FR) = gratuit + payant, hors marché.

**Lecture :** un concurrent local positionne 3 paliers ~2 400 / 4 200 / 7 200 FCFA, **commission store incluse**. Loyatrack en **checkout web (0 commission)** peut afficher **moins cher** et toucher **plus net**.

**Reco issue du benchmark** : 2 500 / 6 000 FCFA. **Choix retenu par le user : 3 000 / 8 000** (positionnement premium assumé, au-dessus du concurrent local sur le Pro).

**PRIX FIGÉS** :
- **Essentiel : 3 000 FCFA/mois · 30 000/an** (2 mois offerts).
- **Pro : 8 000 FCFA/mois · 80 000/an** (2 mois offerts).

À surveiller : le coût Twilio du Pro (~700 FCFA/mois pour 10 locataires) reste très couvert ; si gros volumes plus tard → palier « Agence » ou limite d'usage équitable.

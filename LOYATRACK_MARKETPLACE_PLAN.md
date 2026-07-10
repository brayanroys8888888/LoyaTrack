# LOYATRACK — Plan d'implémentation : Vitrine d'annonces + Messagerie (marketplace de location)

> Statut : **Paliers 1 & 2 IMPLÉMENTÉS** (branche `feat/marketplace-annonces`, 7 commits, recette e2e OK). Reste Palier 3 (messagerie + anti-arnaque) et Palier 4 (monétisation). Spéc détaillée du Palier 1 en §9.
> Objectif stratégique : rendre LoyaTrack **indispensable même au bailleur de 1–5 logements** en l'accrochant à une douleur plus grande et récurrente que la gestion — **re-louer un logement vacant**. Le CRM devient le back-office ; la vitrine devient l'acquisition.
> Avantage déloyal à exploiter à fond : **LoyaTrack connaît déjà les unités vacantes** (`biens.UniteLogement`) et **l'identité vérifiée du bailleur** (pièce d'identité). Publier une annonce doit être un geste à **1 tap, pré-rempli**, et afficher un badge **« Bailleur vérifié »** qu'aucun groupe Facebook n'a.
> **Décisions actées (2026-07-10)** : (1) **marque unique LoyaTrack**, vitrine grand public sous le libellé « Logements », servie en **sous-dossier `/logements/`** (pas un sous-domaine — on mutualise l'autorité SEO ; réversible plus tard) ; (2) **identité chercheur = numéro de téléphone vérifié une seule fois** (OTP **WhatsApp de préférence**, SMS en repli), de confiance ensuite pendant une période (pas de re-OTP par contact), table **`Chercheur` distincte** du modèle bailleur, **Google Sign-In optionnel** mais téléphone toujours capturé, **jamais de contact anonyme**.

---

## 0. Principes directeurs

1. **Supply-first, par paliers.** Un marketplace meurt du *cold start* (pas d'annonces → pas de chercheurs → pas d'annonces). Chaque palier doit livrer de la valeur **seul**, avant même d'avoir du trafic. Le Palier 1 (page publique partageable) sert d'abord d'**outil de diffusion** pour le bailleur sur SES canaux (WhatsApp, Facebook), et amorce mécaniquement le stock d'annonces + les pages SEO.
2. **Le web est le canal SEO, pas Flutter.** Google n'indexe pas l'app. Les pages publiques sont **rendues côté serveur (Django SSR, templates)**, hors `/api/v1/`. L'app mobile pilote la **création/gestion** des annonces et la **messagerie**.
3. **La confiance est le produit.** Le vrai concurrent (Facebook/WhatsApp/agences) a déjà la liquidité et la gratuité. On gagne sur **la confiance** (bailleur vérifié, zéro arnaque) et le **zéro-effort de publication**. Tout le design anti-arnaque (§4) est un pilier, pas une option.
4. **Multi-tenant conservé.** Toute annonce est scopée `bailleur=request.user` côté gestion. Le côté public est en lecture seule, filtré sur `statut='publiee'`.
5. **Réutiliser l'existant.** Media/photos (`image_picker`, `MEDIA_ROOT`), notifications (`Notification` + FCM), OTP SMS (infra `auth`), taxonomie de types (`Propriete.TYPE_CHOICES`), plans d'abonnement (`Essentiel`/`Pro`).

---

## 1. Nouvelle app Django `annonces`

Ajoutée à `INSTALLED_APPS`. Contient : modèles marketplace, vues **API** (app Flutter) **et** vues **SSR publiques** (SEO), sitemap, modération. La messagerie peut vivre dans la même app (§3) ou une sous-app `messagerie` — regroupée ici pour le MVP.

---

## 2. VOLET A — Modèle de données

### 2.1 Taxonomie de localisation (socle du SEO) — `Ville`, `Quartier`

Le SEO longue traîne (« appartement 2 chambres Bonamoussadi Douala ») repose sur des **pages structurées par localisation**. On modélise la hiérarchie **ville → quartier** plutôt qu'un texte libre.

**`Ville`**
- `nom` — CharField (ex. « Douala »)
- `slug` — SlugField unique (ex. `douala`)
- `region` — CharField (ex. « Littoral »)
- `latitude`, `longitude` — pour un tri/affichage éventuel
- `population` / `ordre` — pour prioriser les grandes villes en SEO

**`Quartier`**
- `ville` — FK(Ville, related_name='quartiers')
- `nom` — CharField (ex. « Bonamoussadi »)
- `slug` — SlugField (ex. `bonamoussadi`)
- `unique_together = (ville, slug)`

> **Seed initial** : commande `python manage.py seed_localisations` avec Douala + Yaoundé et leurs quartiers connus (Bonamoussadi, Bonapriso, Akwa, Bonabéri, Makepe, Bepanda… / Bastos, Biyem-Assi, Mvan…). On étend au fil de l'eau. À la création d'annonce, un quartier absent est **proposé à la modération** (évite le champ libre non-indexable).

### 2.2 `Annonce` (le cœur)

Rattachée au **bailleur** (scoping + badge vérifié) et, quand elle en vient, à une **`UniteLogement`** (pré-remplissage + dépublication auto quand l'unité se re-loue). `unite` est **nullable** : on autorise aussi une annonce autonome (un bailleur peut vouloir diffuser un logement pas encore saisi comme unité) — mais le flux vedette part d'une unité vacante.

Champs :
- `bailleur` — FK(AUTH_USER_MODEL, related_name='annonces')
- `unite` — FK(UniteLogement, null=True, blank=True, on_delete=SET_NULL) — **source & synchro d'occupation**
- `reference` — CharField court public (ex. `LT-4F2A`), pour partage/SAV
- `slug` — SlugField unique (SEO) — ex. `appartement-2-chambres-bonamoussadi-douala-lt4f2a`
- **Caractéristiques**
  - `type_bien` — choices (reprend `Propriete.TYPE_CHOICES` + `chambre`, `bureau`) : appartement / villa / studio / chambre / immeuble / bureau / autre
  - `nb_chambres`, `nb_salons`, `nb_cuisines`, `nb_douches` — PositiveSmallInteger
  - `superficie_m2` — PositiveInteger (null=True)
  - `meuble` — Boolean
  - `standing` — choices (`economique`, `moyen`, `haut`) (facultatif, filtre SEO)
- **Localisation**
  - `ville` — FK(Ville), `quartier` — FK(Quartier, null=True)
  - `adresse_indicative` — CharField (repère public : « près du carrefour Bonamoussadi ») — **jamais l'adresse exacte** (sécurité, §4)
- **Prix**
  - `loyer` — Decimal (pré-rempli depuis `unite.loyer_standard`)
  - `charges` — Decimal (default 0)
  - `caution_mois` — PositiveSmallInteger (default 1) — nb de mois de caution
- **Contenu**
  - `titre` — CharField (auto-généré, éditable) : « Appartement 2 chambres à Bonamoussadi »
  - `description` — TextField (numéros de téléphone **strippés** à la sauvegarde, §4)
  - `disponible_le` — DateField (null=True → « disponible immédiatement »)
- **Cycle de vie / publication**
  - `statut` — choices :
    - `brouillon` — en cours de création
    - `en_moderation` — soumise, en attente de validation
    - `publiee` — visible publiquement + SEO
    - `suspendue` — retirée par modération (avec motif)
    - `pourvue` — le bailleur a trouvé (ou l'unité s'est re-louée) → dépubliée mais conservée
    - `expiree` — délai dépassé sans renouvellement
  - `refus_motif` — TextField (modération)
  - `date_publication` — DateTimeField(null=True)
  - `date_expiration` — DateTimeField(null=True) — = publication + **45 j** (renouvelable en 1 tap)
- **Signaux / SEO**
  - `nb_vues` — PositiveInteger (compteur public, incrément throttlé par IP/session)
  - `nb_contacts` — PositiveInteger (nb de conversations ouvertes)
  - `boost_jusqu_a` — DateTimeField(null=True) — mise en avant payante (§5)
- `date_creation`, `date_maj` — auto

**Méthodes / logique :**
- `save()` → génère `slug` (type + nb_chambres + quartier + ville + reference) et strippe les numéros de téléphone de `description`.
- `est_visible` → `statut == 'publiee'` et `date_expiration > now`.
- **Synchro occupation** (l'atout clé) : dans `UniteLogement.synchroniser_statut()`, si l'unité repasse `occupe` et qu'une annonce liée est `publiee` → la passer `pourvue` automatiquement (plus jamais d'annonce fantôme d'un logement déjà loué → **confiance**). Inversement, à la résiliation/départ (`biens`/`locataires` lifecycle), proposer au bailleur « Republier l'annonce ? ».

### 2.3 `PhotoAnnonce`
- `annonce` — FK(related_name='photos')
- `image` — ImageField(upload_to='annonces/%Y/%m/')
- `ordre` — PositiveSmallInteger (default 0)
- `est_couverture` — Boolean
- Contrainte applicative : **1 photo minimum** pour publier (une annonce sans photo ne se vend pas et sent l'arnaque). Max ~10.

### 2.4 Indexes & requêtes
- Index composite `(ville, quartier, type_bien, nb_chambres, statut)` → sert les pages SEO et la recherche.
- Index `(statut, date_expiration)` → tâche d'expiration + listings publics.
- Filtrage public **toujours** `statut='publiee', date_expiration__gt=now`.

---

## 3. VOLET B — Architecture SEO (Django SSR)

### 3.1 Où ça vit
- Namespace d'URL **public**, séparé de l'API et de l'app, servi en **sous-dossier `/logements/`** sur le domaine principal (**décision actée** : pas de sous-domaine — un site neuf mutualise mieux son autorité SEO en sous-dossier ; le passage en sous-domaine/marque distincte reste possible plus tard via redirections). Un domaine **`.cm`** local (si dispo/abordable) renforcerait le SEO Cameroun — orthogonal au choix sous-dossier.
- **Templates Django** (SSR complet, pas de JS requis pour voir le contenu → indexable et rapide sur réseau mobile camerounais).

### 3.2 Arborescence d'URL (canoniques, *clean*, indexables)

```
/logements/                                   → accueil : villes + annonces à la une + recherche
/logements/louer/<ville>/                     → toutes les annonces d'une ville
/logements/louer/<ville>/<quartier>/          → par quartier
/logements/louer/<ville>/<quartier>/<type>/   → par quartier + type          (ex. .../bonamoussadi/appartement/)
/logements/louer/<ville>/<quartier>/<type>-<n>-chambres/   → combo à forte intention (INDEXÉE)
/logements/annonce/<slug>/                     → page détail d'une annonce
/logements/recherche/?...                      → recherche libre à facettes (query params = NON indexée / canonical vers la page propre)
```

- **La combinaison qui gagne la requête cible** « appartement 2 chambres Bonamoussadi Douala » = une **page canonique propre** :
  `/logements/louer/douala/bonamoussadi/appartement-2-chambres/`
  générée pour les combos à fort volume (type × nb_chambres × quartier). Les filtres fins (prix, meublé, superficie) restent en **query params** sur `/recherche/`, avec `<link rel="canonical">` pointant la page propre et `noindex` sur les combinaisons infinies (évite le *duplicate/thin content*).

### 3.3 On-page SEO (par template)
- `<title>` templaté : « Appartement 2 chambres à louer à Bonamoussadi, Douala — 120 000 FCFA/mois | LoyaTrack ».
- `<meta name="description">` : résumé dynamique (type, pièces, quartier, prix, dispo).
- `<h1>` aligné sur l'intention de recherche.
- **`<link rel="canonical">`** systématique.
- **Fil d'Ariane** (breadcrumb) visible **+ JSON-LD `BreadcrumbList`**.
- `hreflang` FR (marché FR ; EN plus tard).
- **Open Graph / Twitter Card** (photo de couverture) → beau partage WhatsApp/Facebook (le canal réel de diffusion).
- **Images** : `loading="lazy"`, `width/height`, `alt` descriptif, formats compressés (Pillow, déjà présent).

### 3.4 Données structurées (schema.org JSON-LD)
- Page **détail** → `RealEstateListing` (ou `Product`/`Offer`) : `name`, `image[]`, `price`+`priceCurrency: XAF`, `address` (`addressLocality`=quartier, `addressRegion`=ville, **pas** de rue exacte), `numberOfRooms`, `floorSize`, `availabilityStarts`.
- Page **liste** (ville/quartier/type) → `ItemList` des annonces.
- → éligibilité aux **rich results** Google (prix, photo, dispo directement dans les SERP).

### 3.5 Indexation & fraîcheur
- **`sitemap.xml`** dynamique (`django.contrib.sitemaps`) : pages ville/quartier/type + toutes les annonces `publiee`, avec `lastmod` = `date_maj`, `changefreq`, `priority`. Sitemap séparé pour les annonces (volatiles) vs pages de localisation (stables).
- **`robots.txt`** : autorise le public, **bloque** `/api/`, `/logements/recherche/?*`, l'admin.
- Ping Google/Bing du sitemap à chaque publication (léger, tâche Celery).
- **Performance** = signal SEO majeur : cache des pages de liste (Redis, déjà là), pagination SSR, pas de JS bloquant.

### 3.6 Contenu programmatique (la vraie arme longue traîne)
- Génération **programmatique** des pages ville/quartier/type même à faible stock : une page « Appartements à louer à Makepe » avec 2 annonces + texte contextuel (prix moyen du quartier, description) capte déjà du trafic et **grossit** avec le stock.
- Bloc éditorial par quartier (généré/curaté) pour l'épaisseur de contenu (anti « thin content »).

---

## 4. VOLET C — Parcours chercheur ↔ bailleur + garde-fous anti-arnaque

### 4.1 Le chercheur (seeker) — identité légère

On ne veut pas d'un compte lourd (friction = mort du funnel), mais pas non plus d'anonymat total (spam/arnaque). **Décision actée** : identité = **téléphone vérifié une seule fois**, table **`Chercheur` dédiée et distincte** du modèle bailleur (ne pas polluer le `User` métier).

**`Chercheur`** :
- `telephone` — unique, **vérifié une fois par OTP** — **WhatsApp de préférence** (Twilio WhatsApp déjà en place pour les rappels → moins cher que le SMS), **SMS en repli** (infra `auth` OTP existante)
- `telephone_verifie_le` — DateTimeField → **de confiance pendant N jours** (ex. 30) : **pas de re-OTP à chaque contact** (maîtrise du coût SMS)
- `nom` — CharField
- `google_sub` — CharField(blank) → **Google Sign-In optionnel** comme démarrage rapide, mais **on capture toujours le téléphone** (canal réel de rappel du bailleur)
- `date_creation`
- Créé **au premier contact** : le chercheur navigue librement (SEO), et ne vérifie son numéro **qu'au moment de contacter** un bailleur. Friction minimale, placée au bon endroit. **Contact anonyme refusé.**

### 4.2 Messagerie

**`Conversation`**
- `annonce` — FK(Annonce)
- `chercheur` — FK(Chercheur)
- `bailleur` — FK(AUTH_USER_MODEL) (dénormalisé depuis `annonce.bailleur` pour le scoping)
- `statut` — `ouverte` / `archivee` / `bloquee`
- `unique_together = (annonce, chercheur)` (une conversation par annonce/chercheur)
- `date_creation`, `date_dernier_message`

**`Message`**
- `conversation` — FK(related_name='messages')
- `expediteur_type` — `chercheur` / `bailleur`
- `corps` — TextField (numéros de téléphone **strippés** au début, révélation contrôlée — voir 4.4)
- `lu` — Boolean
- `date_envoi`

**Flux :**
1. Chercheur sur la page annonce → **« Contacter le bailleur »**.
2. S'il n'est pas vérifié → OTP SMS (nom + téléphone). *(déjà codé côté auth).*
3. Premier message **structuré / pré-rempli** (réduit friction + spam) : « Bonjour, ce logement est-il toujours disponible ? Quand puis-je visiter ? »
4. Le bailleur reçoit une **`Notification` in-app + push FCM** (infra existante). Il répond **dans l'app** (nouvel onglet « Messages »).
5. Échange asynchrone in-app. **Le téléphone n'est pas exposé** tant que le bailleur ne le partage pas explicitement (bouton « Partager mon numéro »).

### 4.3 Garde-fous anti-arnaque (pilier, pas option)

| Risque | Parade |
|---|---|
| **Fausse annonce / arnaqueur** | **Badge « Bailleur vérifié »** (identité déjà capturée). Filtrer/mettre en avant les annonces de bailleurs à identité validée. |
| **Paiement avant visite (arnaque n°1)** | **Bandeau permanent** sur chaque annonce et 1er message : *« Ne payez jamais de caution/avance avant d'avoir visité. LoyaTrack ne collecte aucun paiement pour une location trouvée ici. »* |
| **Contournement / collecte de numéros** | Numéros de téléphone **strippés** de la description ET des premiers messages (regex FR/`+237`), forçant le contact in-app traçable (et modérable). |
| **Spam de contacts** | **Rate-limit** par chercheur (ex. N contacts/jour), OTP obligatoire, throttling par IP. |
| **Adresse exacte exposée** | Public = **quartier + repère indicatif** uniquement ; l'adresse précise ne se donne qu'en conversation. |
| **Annonce fantôme (déjà louée)** | **Dépublication auto** quand l'unité redevient `occupe` (§2.2) + **relance « toujours disponible ? »** avant expiration (45 j) → stock frais = confiance. |
| **Contenu douteux / doublons photos** | **File de modération** : validation manuelle des **premières** annonces d'un bailleur, auto-validation ensuite si historique sain. Reverse-image / hash de photos en V2. |
| **Abus signalés** | **Signaler l'annonce / le contact** (public + in-app) → file modération ; **bloquer** un chercheur (conversation `bloquee`). |
| **Bailleur harcelé** | Il peut archiver/bloquer une conversation ; jamais de numéro exposé sans son action. |

### 4.4 Modération
- `StatutAnnonce.en_moderation` → `AnnonceModeration` (file) avec actions valider / refuser (motif) / suspendre.
- Auto-checks à la soumission : ≥1 photo, prix cohérent (> 0, borne haute anti-typo), quartier connu, description non vide, pas de numéro.
- **Signalements** : modèle `Signalement(annonce|conversation, motif, chercheur|null, date)`.

---

## 5. Monétisation (branchée sur l'abonnement existant)

- **Annonces gratuites = funnel d'acquisition.** On ne facture pas la publication (il faut du stock).
- **Découpage plans** (extension de la matrice `Essentiel`/`Pro`) :
  - Essentiel : **N annonces actives** (ex. 1–2), badge vérifié, messagerie de base.
  - Pro : **annonces illimitées**, **statistiques** (vues/contacts), **réponses rapides**.
- **Revenu additionnel** : **Boost / à la une** (`boost_jusqu_a`) — mise en avant payante d'une annonce (paiement web CinetPay, comme l'abonnement). Optionnel « leads débloqués » plus tard.
- Le marketplace devient aussi un **canal d'acquisition d'abonnés** : pour publier/recevoir des leads → créer un compte bailleur → funnel vers le SaaS.

---

## 6. Séquençage (paliers livrables indépendamment)

### Palier 1 — « Publier depuis une unité vacante » + page publique partageable  ✅ FAIT
Livrable : le bailleur publie une annonce en 1 tap (pré-remplie depuis `UniteLogement` vacante), obtient une **URL publique SEO** partageable (WhatsApp/Facebook). Valeur **jour 1 sans trafic marketplace** (outil de diffusion) + amorce du stock et des pages SEO.
- Modèles `Ville`, `Quartier`, `Annonce`, `PhotoAnnonce` + migrations + seed localisations.
- API (app) : CRUD annonce scopé bailleur, upload photos (multipart, comme l'existant), « publier depuis unité ».
- SSR : page **détail** (`/logements/annonce/<slug>/`) avec meta/OG/JSON-LD.
- Flutter : section « Mes annonces » (liste, créer/éditer, publier, partager le lien), entrée depuis une unité vacante dans `biens`.
- Dépublication auto à la re-location.

### Palier 2 — Moteur de recherche + pages de localisation (SEO)  ✅ FAIT
- Pages liste ville/quartier/type + combos à forte intention, `ItemList` JSON-LD, breadcrumb.
- `sitemap.xml`, `robots.txt`, ping moteurs, cache Redis.
- Recherche à facettes (`/recherche/`) : localisation, type, chambres, prix, meublé.
- Contenu programmatique par quartier.

### Palier 3 — Messagerie + anti-arnaque
- `Chercheur` (OTP), `Conversation`, `Message`, notifications/FCM.
- Bandeaux sécurité, strip téléphone, rate-limit, signalement/blocage.
- File de modération + auto-checks.
- Flutter : onglet « Messages » (bailleur) ; UI publique « Contacter ».

### Palier 4 — Monétisation & croissance
- Boost/à la une (paiement CinetPay), limites par plan, stats d'annonce.
- Reverse-image, badges avancés, alertes email chercheur (« nouveaux logements à Makepe »).

---

## 7. Où se branche le code existant

| Existant | Réutilisé pour |
|---|---|
| `biens.UniteLogement` (occupation) | Source d'annonce + dépublication auto |
| `accounts.Bailleur` (pièce d'identité) | Badge « Bailleur vérifié » |
| Infra OTP SMS (`auth`) | Vérification du chercheur |
| `Notification` + FCM (`firebase.py`) | Alertes de nouveaux messages |
| Media/photos (`MEDIA_ROOT`, Pillow) | Photos d'annonces + compression |
| `Propriete.TYPE_CHOICES` | Types de biens (étendus) |
| Abonnements CinetPay (web) | Boost/à la une |
| Redis (Celery) | Cache des pages de liste, expiration, ping sitemap |

---

## 8. Risques & décisions

### 8.1 Décisions actées (2026-07-10)
- **Branding** — **marque unique LoyaTrack**, vitrine grand public sous le libellé « Logements », servie en **sous-dossier `/logements/`** (pas de sous-domaine : mutualise l'autorité SEO d'un site neuf ; réversible plus tard). *(voir §3.1)*
- **Identité chercheur** — **téléphone vérifié une seule fois** (OTP **WhatsApp de préférence**, SMS repli), de confiance pendant N jours (pas de re-OTP par contact), **table `Chercheur` distincte**, **Google optionnel** mais téléphone toujours capturé, **contact anonyme refusé**. *(voir §4.1)*

### 8.2 Décisions ouvertes (à trancher plus tard, n'empêchent pas le Palier 1)
1. **Cold start** — accepter que le Palier 1 serve surtout d'**outil de diffusion** au début (valeur réelle) ; ne pas attendre de trafic SEO avant 6–18 mois.
2. **Modération** — 100 % manuelle au début (peu de volume) ; définir le seuil d'auto-validation. *(Palier 1 : auto-publication après auto-checks, cf. §9 ; file de modération au Palier 3 quand les annonces deviennent publiquement découvrables.)*
3. **Juridique** — on **ne collecte pas** de paiement de location ici (contrairement au module MoMo loyers) → on reste un **support de mise en relation** ; garder ce cloisonnement pour éviter la qualification d'intermédiaire financier.
4. **Domaine `.cm`** — à acquérir (si dispo/abordable) pour le SEO local — orthogonal au choix sous-dossier.
5. **OTP WhatsApp vs SMS** — confirmer la faisabilité template WhatsApp (Twilio) au Palier 3 ; SMS reste le repli garanti.

---

---

## 9. Palier 1 — spécification détaillée (prêt à implémenter)

> **Thème** : « Publier depuis une unité vacante » + **page publique partageable**. Aucune dépendance au trafic SEO : la valeur immédiate est un **lien beau à partager sur WhatsApp/Facebook** (aperçu Open Graph). La recherche/les pages de localisation (Palier 2) et la messagerie (Palier 3) viennent après.

### 9.0 « Definition of done »
Depuis l'app, un bailleur : (1) part d'une **unité vacante** de `biens`, (2) obtient une annonce **pré-remplie** (loyer, type, quartier), (3) ajoute des **photos**, (4) **publie** en un tap (auto-checks OK), (5) reçoit une **URL publique** `…/logements/annonce/<slug>/` qui s'affiche avec un **bel aperçu WhatsApp** et des **données structurées**. Quand l'unité se **re-loue**, l'annonce passe **`pourvue` automatiquement**.

### 9.1 Périmètre
**Dans** : app `annonces` + modèles `Ville`/`Quartier`/`Annonce`/`PhotoAnnonce` ; API CRUD scopée bailleur + publier/dépublier/renouveler + upload photos + « depuis-unité » ; **page SSR détail** (OG/JSON-LD/canonical) + sitemap minimal ; synchro occupation ; écrans Flutter « Mes annonces » + point d'entrée depuis unité vacante + partage.
**Hors (paliers suivants)** : pages de liste ville/quartier/type & moteur de recherche (P2) ; `Chercheur`, `Conversation`, `Message`, modération manuelle, signalement (P3) ; boost/limites par plan/stats (P4).

### 9.2 Backend — app Django `annonces`

**Modèles de ce palier** (sous-ensemble de §2 ; on n'ajoute pas encore les champs des paliers suivants pour éviter la dette) :

`Ville` — `nom`, `slug` (unique), `region`, `latitude`/`longitude` (null), `ordre`.
`Quartier` — `ville` (FK), `nom`, `slug` ; `unique_together=(ville, slug)`.

`Annonce` — champs Palier 1 :

| Groupe | Champs |
|---|---|
| Rattachement | `bailleur` FK, `unite` FK(UniteLogement, null, `on_delete=SET_NULL`), `reference` (court unique, ex. `LT-4F2A`), `slug` (unique) |
| Caractéristiques | `type_bien` (choices §2.2), `nb_chambres`, `nb_salons`, `nb_cuisines`, `nb_douches` (PositiveSmallInt), `superficie_m2` (null), `meuble` (bool), `standing` (choices, blank) |
| Localisation | `ville` FK, `quartier` FK(null), `adresse_indicative` (repère public, **jamais l'adresse exacte**) |
| Prix | `loyer`, `charges` (default 0), `caution_mois` (default 1) |
| Contenu | `titre`, `description` (**numéros strippés**), `disponible_le` (null → « immédiatement ») |
| Cycle de vie | `statut` (`brouillon`/`publiee`/`pourvue`/`suspendue`/`expiree` — `en_moderation` réservé P3), `date_publication` (null), `date_expiration` (null) |
| Signaux | `nb_vues` (default 0), `nb_contacts` (default 0, alimenté P3) |
| Horodatage | `date_creation`, `date_maj` |

`PhotoAnnonce` — `annonce` FK(`related_name='photos'`), `image` (ImageField `upload_to='annonces/%Y/%m/'`), `ordre`, `est_couverture`. **≥1 photo obligatoire pour publier**, max 10 ; compression Pillow à l'upload.

**Logique (services/`models.save`)**
- `_generer_slug(annonce)` → `f"{type}-{nb_chambres}-chambres-{quartier.slug}-{ville.slug}-{reference}"` slugifié, unique.
- `_generer_reference()` → `LT-` + 4 hex (collision-safe).
- `nettoyer_telephones(texte)` → regex FR/`+237` qui retire les numéros de `description` (force le contact tracé, anti-bypass). Réutilisable en P3 pour les messages.
- `publier(annonce)` — **auto-checks** : `statut in {brouillon,expiree,pourvue}` ; **≥1 photo** ; `loyer>0` et `loyer < plafond` (anti-typo) ; `ville` (et `quartier` recommandé) ; `description` non vide **et sans numéro** ; `nb_chambres≥0`. Si OK → `statut='publiee'`, `date_publication=now`, `date_expiration=now+45j`. Sinon → `ValidationError` listant les manques. **Palier 1 = auto-publication** (pas de file de modération : à ce stade l'annonce n'est pas encore découvrable publiquement en recherche, elle est diffusée par le bailleur lui-même ; la modération arrive au P3 avec la découvrabilité).
- `renouveler(annonce)` → `date_expiration=now+45j` (1 tap).
- **Synchro occupation** — brancher dans `biens.UniteLogement.synchroniser_statut()` : si l'unité repasse `occupe` et qu'une `Annonce` liée est `publiee` → `statut='pourvue'`, `date_publication=None` (dépublication auto = **zéro annonce fantôme**). À la libération d'une unité, l'app proposera « Republier » (UI P1, logique triviale).
- Tâche Celery **`expirer_annonces`** (beat quotidien) : `publiee` + `date_expiration<now` → `expiree`.

**Seed** — `python manage.py seed_localisations` : Douala + Yaoundé et leurs quartiers connus (Bonamoussadi, Bonapriso, Akwa, Bonabéri, Makepe, Bépanda, Deido… / Bastos, Biyem-Assi, Mvan, Nsam…). Idempotent (`get_or_create`).

### 9.3 API (DRF — app Flutter)

Permissions : `IsAuthenticated` (le marketplace est le **funnel d'acquisition** → on ne le bloque pas derrière l'abonnement au P1 ; les **limites par plan** viennent au P4). Tout est scopé `bailleur=request.user`.

| Méthode & route (`/api/v1/`) | Rôle |
|---|---|
| `GET/POST annonces/` | Liste (mes annonces) / créer un brouillon |
| `GET/PATCH/DELETE annonces/{id}/` | Détail / éditer / supprimer |
| `POST annonces/depuis-unite/` | body `{unite}` → brouillon **pré-rempli** (loyer=`unite.loyer_standard`, type/quartier depuis `Propriete`) |
| `POST annonces/{id}/publier/` | Auto-checks → `publiee` (renvoie l'URL publique) |
| `POST annonces/{id}/depublier/` | → `brouillon` (ou `pourvue`) |
| `POST annonces/{id}/renouveler/` | Prolonge l'expiration |
| `POST annonces/{id}/photos/` | Upload multipart (comme l'existant) |
| `DELETE annonces/{id}/photos/{pid}/` | Retirer une photo |
| `GET localisations/villes/` | Villes + quartiers (pickers du formulaire) |

Serializers : `AnnonceSerializer` (imbrique `photos`, `ville`/`quartier`, expose `url_publique` calculée + `statut`), `AnnonceEcritureSerializer`, `VilleSerializer`. La suppression d'une annonce supprime ses fichiers photos.

### 9.4 SSR public — page détail (le livrable qui donne la valeur)
- Route : `path('logements/annonce/<slug:slug>/', AnnoncePubliqueView.as_view())` (namespace public, hors `/api/`).
- Vue : `get_object_or_404(Annonce, slug=…, statut='publiee', date_expiration__gt=now)` ; sinon **404** (une annonce `pourvue`/expirée n'est plus servie). Incrémente `nb_vues` **throttlé par session** (pas à chaque F5).
- Template `annonces/detail.html` : galerie photos (lazy, `alt`), titre `<h1>` aligné intention, prix FCFA, caractéristiques, quartier/ville (**pas d'adresse exacte**), dispo, **bandeau sécurité** (« ne payez jamais avant visite »), badge **« Bailleur vérifié »**, CTA « Contacter » (désactivé en P1 → activé P3).
- SEO on-page : `<title>`/`<meta description>` templatés, **`<link rel="canonical">`**, **Open Graph + Twitter Card** (photo de couverture → **bel aperçu WhatsApp**, la vraie valeur P1), **JSON-LD `RealEstateListing`** (prix XAF, `numberOfRooms`, `addressLocality`=quartier).
- **Sitemap minimal** `logements/sitemap.xml` (`django.contrib.sitemaps`) des annonces `publiee` (l'usine SEO complète = P2). `robots.txt` : autorise `/logements/annonce/`, bloque `/api/`.

### 9.5 Frontend Flutter
- `services/annonce_service.dart` (Dio) : CRUD + publier/dépublier/renouveler + upload photo (multipart) + `depuisUnite(uniteId)` + `getVilles()`.
- Écrans : **`MesAnnoncesScreen`** (liste avec statut/vues, entrée depuis un onglet ou Réglages) ; **`AddEditAnnonceScreen`** (formulaire : picker unité→pré-remplissage, ville/quartier, caractéristiques, photos `image_picker`, prix, description) ; bouton **Publier** (affiche les manques renvoyés par l'API) ; **partage** du lien en réutilisant le pattern existant du dashboard (`Clipboard` + `wa.me` WhatsApp + `launchUrl`).
- **Point d'entrée clé** : dans `biens_screen.dart`, sur une **unité vacante** → action « **Publier une annonce** » (→ `depuisUnite`). C'est le geste 1-tap qui matérialise l'avantage déloyal.
- i18n : ajouter les clés dans **`app_fr.arb` + `app_en.arb`**, `flutter gen-l10n` (valeurs métier FR conservées).

### 9.6 Câblage & migrations
- `annonces` dans `INSTALLED_APPS` ; `annonces.urls` (API sous `/api/v1/`, public sous `/logements/`) inclus dans `Loyatrack/urls.py`.
- Migrations `annonces` (modèles) + petite migration/hook côté `biens` pour la synchro (pas de champ ajouté — appel dans `synchroniser_statut`).
- Beat : `expirer-annonces` (quotidien).

### 9.7 Tests (`annonces/tests.py`)
- slug/reference générés & uniques ; `nettoyer_telephones` retire bien les numéros (FR/`+237`).
- `publier` : refuse sans photo / loyer=0 / description avec numéro ; accepte sinon → `publiee` + expiration à 45 j.
- **Synchro** : rattacher un locataire à l'unité → `synchroniser_statut` → annonce `pourvue`.
- Public : annonce `publiee` → 200 + JSON-LD présent ; `brouillon`/`pourvue`/expirée → **404**.
- `depuis-unite` : pré-remplit loyer & localisation ; scoping (un bailleur ne voit/agit que sur ses annonces).

### 9.8 Séquence d'implémentation
1. App `annonces` + modèles `Ville`/`Quartier`/`Annonce`/`PhotoAnnonce` + migrations + `seed_localisations`.
2. Services (slug/reference/strip/publier/renouveler) + synchro occupation dans `biens` + tâche `expirer_annonces` + **tests backend**.
3. API DRF (viewset + actions + `depuis-unite` + `localisations/villes/`) + serializers.
4. SSR : route + vue + template détail + OG/JSON-LD/canonical + sitemap minimal + robots.
5. Flutter : service + `MesAnnoncesScreen` + `AddEditAnnonceScreen` + partage + entrée « unité vacante » + ARB FR/EN.
6. Recette bout-en-bout sur l'émulateur (publier depuis une unité → ouvrir l'URL → vérifier l'aperçu WhatsApp).

---

> ⚠️ Ce document est une **conception** : les vrais ennemis sont le **cold start** et la **confiance**, pas la technique. L'ordre des paliers est choisi pour livrer de la valeur à chaque étape et construire le stock *avant* de dépendre du SEO.

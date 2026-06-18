# Guide de test — Abonnement (émulateur)

Tester de bout en bout : **essai → bannière → expiration → paywall → paiement web (simulé) → activation → reçu**, plus le **gating Pro** (Essentiel → upsell).

> Compte de test : **`appdemo@loya.com`** (non-staff → le gating s'applique).
> ⚠️ N'utilise PAS `brayanroys888@gmail.com` ni `admin@loyatrack.com` : ils sont **staff** et **contournent** tout le gating.

---

## 0. Prérequis (une fois)

**Serveur** — depuis `backend/Loyatrack/`, avec le **venv** et lié à `0.0.0.0` :
```bash
../env/Scripts/python.exe manage.py runserver 0.0.0.0:8000
```
(Si la génération de docs renvoie 501 « reportlab », c'est que le serveur a été lancé hors venv → tuer et relancer ainsi.)

**App** — rebuild complet (nouveaux fichiers + provider) depuis `frontend/papillongestion/` :
```bash
flutter run -d emulator-5554
```

**Connexion** dans l'app : `appdemo@loya.com` / `Demo1234!`
(si le mot de passe ne marche pas, le réinitialiser :)
```bash
../env/Scripts/python.exe manage.py shell -c "from accounts.models import Bailleur; b=Bailleur.objects.get(email='appdemo@loya.com'); b.set_password('Demo1234!'); b.save(); print('mdp ok')"
```

**Astuce** : après chaque changement d'état ci-dessous, fais un **hot restart** de l'app (touche `R` dans le terminal `flutter run`) pour forcer le rechargement du statut d'abonnement.

---

## 1. Bannière d'essai

Mettre le compte en **essai, 3 jours restants** :
```bash
../env/Scripts/python.exe manage.py shell -c "from accounts.models import Bailleur; from abonnements.services import assurer_abonnement; from django.utils import timezone; from datetime import timedelta; b=Bailleur.objects.get(email='appdemo@loya.com'); a=assurer_abonnement(b); a.statut='essai'; a.date_fin_essai=timezone.now()+timedelta(days=3); a.date_fin=None; a.save(); print('essai 3j')"
```
**Dans l'app** (hot restart) → onglet **Tableau de bord** :
- ✅ Bannière orange **« Essai gratuit : 3 jour(s) restant(s) »** + bouton **Passer au Pro**.
- ✅ Toutes les fonctions Pro marchent (l'essai débloque le Pro) : Historique → Export, fiche locataire → Contrat de bail, Comptabilité, etc.

---

## 2. Expiration → paywall (blocage total)

```bash
../env/Scripts/python.exe manage.py shell -c "from accounts.models import Bailleur; from abonnements.services import assurer_abonnement; from django.utils import timezone; from datetime import timedelta; b=Bailleur.objects.get(email='appdemo@loya.com'); a=assurer_abonnement(b); a.statut='expire'; a.date_fin_essai=timezone.now()-timedelta(days=1); a.date_fin=None; a.save(); print('expire')"
```
**Dans l'app** (hot restart) → navigue vers un onglet qui charge des données (Tableau de bord / Locataires) :
- ✅ L'écran **Paywall** s'affiche automatiquement (« Votre accès a expiré ») avec les 2 formules et leurs prix.
- ✅ Tout appel API métier renvoie 403 → l'app bascule sur le paywall (blocage total).

---

## 3. Paiement web simulé → activation → déblocage

Toujours sur l'écran Paywall :
1. Touche **« Gérer mon abonnement »** → le navigateur de l'émulateur ouvre l'**espace web** (magic-link à usage unique).
   - ✅ Page « Mon abonnement » avec les 2 formules.
2. Sous **Pro** (ou Essentiel), touche **« Payer au mois »**.
   - ✅ Page **« Paiement (simulation) »** avec le montant.
3. Touche **« Simuler un paiement réussi »**.
   - ✅ Page **« Abonnement activé »** + lien **« Télécharger le reçu (PDF) »** (teste-le).
4. Reviens dans l'app, touche **« J'ai payé, actualiser »** sur le paywall.
   - ✅ Le paywall se ferme, l'app est de nouveau utilisable (statut **actif / Pro**).

> Le magic-link est **à usage unique (≤ 10 min)** : si tu rouvres le même lien, tu obtiens « Lien invalide ». Il faut repasser par « Gérer mon abonnement ».

---

## 4. Plan Essentiel → upsell Pro

Mettre le compte en **Essentiel actif** :
```bash
../env/Scripts/python.exe manage.py shell -c "from accounts.models import Bailleur; from abonnements.services import activer_abonnement; activer_abonnement(Bailleur.objects.get(email='appdemo@loya.com'),'essentiel','mensuel'); print('essentiel actif')"
```
**Dans l'app** (hot restart) :
- ✅ **Pas** de bannière d'essai (le compte paie).
- ✅ Les fonctions de base marchent (locataires, paiements, **quittance**, pénalités manuelles).
- ✅ Fiche locataire → **Contrat de bail** affiche un badge **PRO** ; au tap → feuille **« Fonctionnalité Pro »** (upsell).
- ✅ Historique → **Export** → upsell Pro.
- ✅ Comptabilité (si accessible) → 403 → upsell.
- ✅ Création d'un **2ᵉ bien** → refus (limite Essentiel = 1 bien) → upsell.

---

## 5. Remettre à zéro (Pro essai 14 j)

```bash
../env/Scripts/python.exe manage.py shell -c "from accounts.models import Bailleur; from abonnements.services import assurer_abonnement; from django.utils import timezone; from datetime import timedelta; b=Bailleur.objects.get(email='appdemo@loya.com'); a=assurer_abonnement(b); a.statut='essai'; a.plan='pro'; a.date_fin_essai=timezone.now()+timedelta(days=14); a.date_fin=None; a.save(); print('reset essai 14j pro')"
```

---

## Vérifier l'état courant à tout moment
```bash
../env/Scripts/python.exe manage.py shell -c "from accounts.models import Bailleur; from abonnements.services import assurer_abonnement; a=assurer_abonnement(Bailleur.objects.get(email='appdemo@loya.com')); print('statut=',a.statut,'plan=',a.plan,'actif=',a.est_actif,'droits=',a.droits,'jours=',a.jours_restants)"
```

## Côté opérateur (admin Django)
- `http://127.0.0.1:8000/admin/` → **Abonnements** et **Transactions d'abonnement** (la liste des transactions affiche le **total des revenus encaissés** selon le filtre).

## Notes
- Le **paiement réel** (CinetPay) n'est pas branché : on est en `PAIEMENT_PROVIDER=fake` (page de simulation). En prod : clés `CINETPAY_*` dans `.env` + `PAIEMENT_PROVIDER=cinetpay`.
- L'URL web de prod devra remplacer `http://10.0.2.2:8000/...` (émulateur) par le domaine **https** réel dans `ApiConfig.manageSubscriptionUrl` et les URLs CinetPay.

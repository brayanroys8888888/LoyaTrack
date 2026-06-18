"""Test end-to-end HTTP de la Priorité 1 (à lancer pendant que runserver tourne).
Utilise uniquement la librairie standard (urllib)."""
import json
import time
import urllib.request
import urllib.error

BASE = "http://127.0.0.1:8000/api/v1"


def req(method, path, token=None, data=None, raw=False):
    url = BASE + path
    headers = {"Content-Type": "application/json"}
    if token:
        headers["Authorization"] = f"Bearer {token}"
    body = json.dumps(data).encode() if data is not None else None
    r = urllib.request.Request(url, data=body, headers=headers, method=method)
    try:
        with urllib.request.urlopen(r) as resp:
            content = resp.read()
            if raw:
                return resp.status, content
            return resp.status, (json.loads(content) if content else None)
    except urllib.error.HTTPError as e:
        return e.code, e.read().decode(errors="replace")


def wait_server():
    for _ in range(30):
        try:
            urllib.request.urlopen(BASE + "/auth/token/", timeout=1)
        except urllib.error.HTTPError:
            return True  # serveur répond (405/400)
        except Exception:
            time.sleep(1)
    return False


def main():
    assert wait_server(), "Serveur injoignable"
    suffix = str(int(time.time()))
    email = f"test{suffix}@loya.com"
    pwd = "MotDePasse123!"

    print("1) Inscription bailleur…")
    st, d = req("POST", "/auth/register/", data={
        "email": email, "password": pwd, "password_confirm": pwd,
        "first_name": "Test", "last_name": "Bailleur",
    })
    print("   ->", st)
    token = d["access"]

    print("2) Création locataire en retard (échéance le 1er)…")
    st, loc = req("POST", "/locataires/", token, {
        "nom": "Mbarga", "prenom": "Alice", "telephone": "690112233",
        "logement": "Studio A1", "montant_loyer": 50000, "jour_echeance": 1,
        "statut": "En retard", "date_entree": "2024-01-01",
        "signature_base64": "iVBORw0KGgoAAAANSUhEUgAA",  # signature factice
    })
    print("   ->", st, "| signature stockée:", bool(loc.get("signature_base64")))
    loc_id = loc["id"]

    print("3) Config pénalité (5% du loyer/jour, 2 j de grâce)…")
    st, cfg = req("POST", "/config-penalites/", token, {
        "locataire": loc_id, "actif": True, "delai_grace": 2,
        "type_penalite": "pourcentage", "pourcentage": 5,
    })
    print("   ->", st, "| montant/jour calculé:", cfg.get("montant_journalier_calcule"))

    print("4) Déclenchement des automatisations (calcul pénalités)…")
    st, d = req("POST", "/locataires/forcer_automatisations/", token)
    print("   ->", st, d)

    print("5) Résumé des pénalités…")
    st, resume = req("GET", "/penalites/resume/", token)
    print("   ->", st, resume)

    print("6) Liste des pénalités du locataire…")
    st, pens = req("GET", f"/penalites/?locataire={loc_id}", token)
    results = pens["results"] if isinstance(pens, dict) else pens
    pen_id = results[0]["id"] if results else None
    if results:
        p = results[0]
        print(f"   -> pénalité #{pen_id}: total={p['total']} net={p['montant_net']} statut={p['statut']}")

    print("7) Paiement PARTIEL de 20 000 (loyer 50 000)…")
    st, pay = req("POST", "/paiements/", token, {
        "locataire": loc_id, "montant": 20000,
        "mode_paiement": "Espèces", "date_paiement": "2026-06-05",
    })
    print(f"   -> statut={pay['statut']} reste_du={pay['reste_du']}")

    print("8) Paiement COMPLET de 50 000 (solde + clôture pénalités)…")
    st, pay2 = req("POST", "/paiements/", token, {
        "locataire": loc_id, "montant": 50000,
        "mode_paiement": "Mobile Money", "date_paiement": "2026-06-10",
    })
    print(f"   -> statut={pay2['statut']} reste_du={pay2['reste_du']}")
    pay2_id = pay2["id"]

    print("9) Vérif statut locataire après paiement complet…")
    st, loc2 = req("GET", f"/locataires/{loc_id}/", token)
    print(f"   -> statut={loc2['statut']} total_penalites={loc2['total_penalites']}")

    print("10) Téléchargement quittance PDF…")
    st, content = req("GET", f"/paiements/{pay2_id}/quittance/", token, raw=True)
    ok_pdf = isinstance(content, bytes) and content[:4] == b"%PDF"
    print(f"   -> {st} | PDF valide: {ok_pdf} | taille: {len(content)} octets")

    print("\n[OK] TEST E2E P1 TERMINE")


if __name__ == "__main__":
    main()

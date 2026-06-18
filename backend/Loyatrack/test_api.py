import requests
import json
from datetime import date

BASE_URL = 'http://127.0.0.1:8000/api/v1'

def print_response(title, response):
    print(f"\n--- {title} ---")
    print(f"Status Code: {response.status_code}")
    try:
        print(json.dumps(response.json(), indent=2))
    except:
        print(response.text)

def test_api():
    # 1. Obtenir le token
    auth_data = {
        'email': 'admin@loyatrack.com',
        'password': 'admin1234'
    }
    r_auth = requests.post(f"{BASE_URL}/auth/token/", data=auth_data)
    print_response("Authentification (Obtenir JWT)", r_auth)
    
    if r_auth.status_code != 200:
        print("Ãchec de l'authentification.")
        return

    token = r_auth.json()['access']
    headers = {'Authorization': f'Bearer {token}'}

    # 2. Créer un locataire
    locataire_data = {
        "nom": "Dupont",
        "prenom": "Jean",
        "telephone": "+33600000000",
        "montant_loyer": "500.00",
        "jour_echeance": 5,
        "date_entree": str(date.today()),
        "penalite_journaliere": "10.00"
    }
    r_loc = requests.post(f"{BASE_URL}/locataires/", json=locataire_data, headers=headers)
    print_response("Créer un Locataire", r_loc)
    
    locataire_id = r_loc.json().get('id')

    # 3. Récupérer les locataires
    r_locs = requests.get(f"{BASE_URL}/locataires/", headers=headers)
    print_response("Lister les Locataires", r_locs)

    # 4. Changer le statut d'un locataire
    if locataire_id:
        r_patch = requests.patch(f"{BASE_URL}/locataires/{locataire_id}/statut/", json={"statut": "En discussion"}, headers=headers)
        print_response("Changer le statut du locataire (PATCH)", r_patch)

    # 5. Dashboard avant paiement
    r_dash = requests.get(f"{BASE_URL}/dashboard/", headers=headers)
    print_response("Dashboard (Avant paiement)", r_dash)

    # 6. Créer un paiement
    if locataire_id:
        paiement_data = {
            "locataire": locataire_id,
            "montant": "500.00",
            "date_paiement": str(date.today()),
            "mode_paiement": "Virement",
            "reference": "VIR-001"
        }
        r_paie = requests.post(f"{BASE_URL}/paiements/", json=paiement_data, headers=headers)
        print_response("Enregistrer un Paiement", r_paie)

    # 7. Dashboard après paiement
    r_dash_after = requests.get(f"{BASE_URL}/dashboard/", headers=headers)
    print_response("Dashboard (Après paiement)", r_dash_after)

    # 8. Vérifier si le statut du locataire a bien été mis à jour après paiement
    r_loc_after = requests.get(f"{BASE_URL}/locataires/{locataire_id}/", headers=headers)
    print_response("Vérification Locataire après paiement", r_loc_after)

if __name__ == '__main__':
    test_api()

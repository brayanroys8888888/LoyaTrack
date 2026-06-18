"""Catalogue des plans et règles d'abonnement Loyatrack.

Source unique de vérité côté backend. Décisions actées (voir
LOYATRACK_ABONNEMENT_PLAN.md) : essai 14 j, grâce 3 j, Pro de courtoisie 1 mois
pour les bailleurs existants. Prix figés : Essentiel 3 000/30 000, Pro 8 000/80 000.
Les valeurs métier (statuts, devise) restent en français/FCFA.
"""
from decimal import Decimal

PLAN_ESSENTIEL = 'essentiel'
PLAN_PRO = 'pro'

DUREE_ESSAI_JOURS = 14
DUREE_GRACE_JOURS = 3
DUREE_COURTOISIE_JOURS = 30  # Pro offert aux bailleurs existants à la bascule

# Fonctions réservées au plan Pro (clé technique → vérifiée par a_droit()/exiger_pro())
FEATURES_PRO = {
    'rappels_auto',       # rappels automatiques SMS/WhatsApp/vocal (Twilio)
    'penalites_auto',     # calcul automatique des pénalités (Celery)
    'multi_biens',        # plus d'un bien
    'comptabilite',       # relevés/rapports/exports comptables
    'documents_legaux',   # contrat de bail, état des lieux
    'portail',            # portail locataire
    'import_masse',       # import CSV/Excel des locataires
}

PLANS = {
    PLAN_ESSENTIEL: {
        'nom': 'Essentiel',
        'mensuel': Decimal('3000'),
        'annuel': Decimal('30000'),
        'max_biens': 1,
        'features': [],
    },
    PLAN_PRO: {
        'nom': 'Pro',
        'mensuel': Decimal('8000'),
        'annuel': Decimal('80000'),
        'max_biens': None,  # illimité
        'features': sorted(FEATURES_PRO),
    },
}

PERIODICITES = ('mensuel', 'annuel')


def prix(plan, periodicite):
    return PLANS[plan][periodicite]

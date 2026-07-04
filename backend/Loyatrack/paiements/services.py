import calendar
import io
from datetime import date
from decimal import Decimal

from django.utils import timezone


def ajouter_mois(d, mois):
    """Ajoute `mois` mois à la date d, en restant valide (gestion des mois courts)."""
    total = d.month - 1 + mois
    annee = d.year + total // 12
    m = total % 12 + 1
    jour = min(d.day, calendar.monthrange(annee, m)[1])
    return date(annee, m, jour)


def appliquer_paiement(paiement):
    """
    Applique la logique métier d'un paiement enregistré :
    - paiement partiel (montant < loyer) -> statut 'partiel', reste reporté, locataire non soldé
    - paiement complet (montant == loyer) -> 'complet', locataire payé, pénalités clôturées
    - paiement en avance (montant >= 2 x loyer) -> 'avance', N périodes couvertes

    La fonction renseigne periode_debut/periode_fin/nb_mois/statut/reste_du puis met à jour
    le statut du locataire et clôture les pénalités actives si le loyer du mois est soldé.
    """
    locataire = paiement.locataire
    loyer = locataire.montant_loyer
    montant = paiement.montant

    if not paiement.periode_debut:
        dp = paiement.date_paiement
        paiement.periode_debut = date(dp.year, dp.month, 1)

    if loyer and montant < loyer:
        # Paiement partiel : on ne solde pas le locataire
        paiement.statut = 'partiel'
        paiement.nb_mois = 1
        paiement.periode_fin = paiement.periode_debut
        paiement.reste_du = (loyer - montant).quantize(Decimal('0.01'))
        paiement.save()
        return paiement

    # Paiement complet ou en avance
    nb_mois = int(montant // loyer) if loyer else 1
    nb_mois = max(nb_mois, 1)
    paiement.nb_mois = nb_mois
    paiement.statut = 'avance' if nb_mois > 1 else 'complet'
    paiement.reste_du = Decimal('0')
    # Dernier jour couvert : fin du dernier mois payé
    dernier_mois = ajouter_mois(paiement.periode_debut, nb_mois - 1)
    paiement.periode_fin = date(
        dernier_mois.year, dernier_mois.month,
        calendar.monthrange(dernier_mois.year, dernier_mois.month)[1],
    )
    paiement.save()

    # Clôture des pénalités actives et remise à zéro
    locataire.penalites.filter(statut='Active').update(
        statut='Clôturée', date_fin=timezone.now().date()
    )
    locataire.total_penalites = Decimal('0')
    if locataire.statut != 'Payé':
        locataire.statut = 'Payé'
    locataire.save()
    return paiement


def creer_demande_paiement(locataire):
    """Crée une demande d'encaissement Mobile Money et renvoie l'objet + l'URL.

    Montant = loyer + charges + frais (frais répercutés au locataire). La collecte
    se fait sur le compte PLATEFORME LoyaTrack (settings.CINETPAY_*) ; le bailleur
    doit avoir configuré son numéro de reversement. Lève ValueError sinon (hors
    provider fake, utilisé en test).
    """
    from django.conf import settings
    from abonnements.providers import get_provider
    from .models import DemandePaiement

    provider = get_provider()
    compte = getattr(locataire.bailleur, 'compte_marchand', None)
    if provider.nom != 'fake' and not (compte and compte.est_configure()):
        raise ValueError("compte_marchand_non_configure")

    base = (locataire.montant_loyer or Decimal('0')) + (locataire.charges_mensuelles or Decimal('0'))
    taux_frais = compte.frais_pourcentage if compte else Decimal('2.00')
    frais = (base * taux_frais / Decimal('100')).quantize(Decimal('1'))
    total = base + frais

    demande = DemandePaiement.objects.create(
        locataire=locataire, montant=total, montant_loyer=base, frais=frais,
        periode=date.today().replace(day=1), prestataire=provider.nom,
    )
    try:
        url = provider.creer_paiement_generique(
            reference=demande.reference_interne, montant=total, devise='XAF',
            description=f"Loyer {locataire.prenom} {locataire.nom}".strip(),
            return_url=getattr(settings, 'CINETPAY_RETURN_URL', '') or '',
            notify_url=getattr(settings, 'CINETPAY_NOTIFY_URL_LOYER', '') or '',
            credentials={},  # collecte sur le compte plateforme (fallback settings)
        )
    except Exception as e:
        demande.statut = 'echouee'
        demande.payload = {'erreur': str(e)}
        demande.save(update_fields=['statut', 'payload'])
        raise
    demande.url_paiement = url
    demande.save(update_fields=['url_paiement'])
    return demande


def confirmer_demande_paiement(demande):
    """Transforme une demande réussie en `Paiement` réel (idempotent).

    Le montant enregistré est le loyer (hors frais : les frais couvrent la
    collecte + le reversement). Réutilise `appliquer_paiement` → statut Payé,
    pénalités clôturées, quittance disponible. Déclenche ensuite le reversement
    immédiat du loyer net vers le Mobile Money du bailleur.
    """
    from django.db import transaction
    from .models import DemandePaiement, Paiement

    with transaction.atomic():
        demande = DemandePaiement.objects.select_for_update().get(pk=demande.pk)
        if demande.statut == 'payee' and demande.paiement_id:
            return demande.paiement  # déjà traité → idempotent (pas de double reversement)

        paiement = Paiement.objects.create(
            locataire=demande.locataire,
            montant=demande.montant_loyer,
            date_paiement=date.today(),
            mode_paiement='Mobile Money',
            reference=str(demande.reference_interne),
        )
        appliquer_paiement(paiement)
        demande.paiement = paiement
        demande.statut = 'payee'
        demande.date_paiement = timezone.now()
        demande.save(update_fields=['paiement', 'statut', 'date_paiement'])

    # Reversement HORS transaction (appel réseau) : un échec ici n'annule pas le
    # paiement déjà encaissé — il est tracé pour relance manuelle.
    _reverser_loyer(demande)
    return paiement


def _reverser_loyer(demande):
    """Reverse le loyer net (montant_loyer) sur le Mobile Money du bailleur.

    Le paiement reste valide même si le reversement échoue : on enregistre alors
    `reversement_statut='echoue'` + le motif pour permettre une relance.
    """
    from abonnements.providers import get_provider
    from .models import DemandePaiement

    compte = getattr(demande.locataire.bailleur, 'compte_marchand', None)
    if not (compte and compte.est_configure()):
        return  # pas de destination de reversement → reste 'non_requis'

    demande.reversement_statut = 'en_attente'
    demande.save(update_fields=['reversement_statut'])

    dest = compte.destination_reversement()
    try:
        ok, ref, erreur = get_provider().effectuer_transfert(
            reference=str(demande.reference_interne), montant=demande.montant_loyer,
            devise='XAF', numero=dest['numero'], operateur=dest['operateur'],
        )
    except Exception as e:  # garde-fou : ne jamais faire remonter l'erreur
        ok, ref, erreur = False, '', str(e)

    demande.reversement_statut = 'effectue' if ok else 'echoue'
    demande.reversement_ref = ref or ''
    demande.reversement_erreur = '' if ok else (erreur or 'échec inconnu')
    demande.save(update_fields=['reversement_statut', 'reversement_ref', 'reversement_erreur'])


def generer_quittance_pdf(paiement):
    """Génère une quittance de loyer au format PDF (bytes) avec ReportLab."""
    from reportlab.lib.pagesizes import A4
    from reportlab.lib.units import mm
    from reportlab.lib import colors
    from reportlab.pdfgen import canvas

    locataire = paiement.locataire
    bailleur = locataire.bailleur

    buffer = io.BytesIO()
    c = canvas.Canvas(buffer, pagesize=A4)
    width, height = A4
    y = height - 30 * mm

    c.setFont("Helvetica-Bold", 20)
    c.drawString(20 * mm, y, "QUITTANCE DE LOYER")
    c.setFont("Helvetica", 9)
    c.setFillColor(colors.grey)
    c.drawString(20 * mm, y - 6 * mm, "Loyatrack — Gestion locative")
    c.setFillColor(colors.black)

    y -= 22 * mm
    c.setFont("Helvetica", 11)

    def ligne(label, valeur):
        nonlocal y
        c.setFont("Helvetica-Bold", 10)
        c.drawString(20 * mm, y, label)
        c.setFont("Helvetica", 10)
        c.drawString(80 * mm, y, str(valeur))
        y -= 8 * mm

    def fcfa(v):
        return f"{v:,.0f} FCFA".replace(",", " ")

    bailleur_nom = f"{bailleur.first_name} {bailleur.last_name}".strip() or bailleur.email or "________"
    logement = locataire.adresse_logement or locataire.logement or "________"
    charges = locataire.charges_mensuelles or 0

    ligne("Bailleur :", bailleur_nom)
    ligne("Adresse du bailleur :", (bailleur.adresse or '').strip() or "________")
    ligne("Locataire :", f"{locataire.prenom} {locataire.nom}")
    ligne("Adresse du logement :", logement)
    y -= 4 * mm
    ligne("N° quittance :", f"Q-{paiement.id:06d}")
    ligne("Date de paiement :", paiement.date_paiement.strftime("%d/%m/%Y"))
    if paiement.periode_debut and paiement.periode_fin:
        ligne("Période couverte :",
              f"{paiement.periode_debut.strftime('%d/%m/%Y')} au {paiement.periode_fin.strftime('%d/%m/%Y')}")
    ligne("Mode de paiement :", paiement.mode_paiement)
    if paiement.reference:
        ligne("Référence :", paiement.reference)

    y -= 6 * mm
    c.setStrokeColor(colors.lightgrey)
    c.line(20 * mm, y, width - 20 * mm, y)
    y -= 10 * mm

    # Décomposition légale : loyer + charges = total
    ligne("Loyer :", fcfa(locataire.montant_loyer))
    ligne("Charges :", fcfa(charges))
    c.setFont("Helvetica-Bold", 11)
    c.drawString(20 * mm, y, "Montant total reçu :")
    c.drawString(80 * mm, y, fcfa(paiement.montant))
    y -= 8 * mm
    if paiement.reste_du and paiement.reste_du > 0:
        c.setFillColor(colors.red)
        ligne("Reste dû :", fcfa(paiement.reste_du))
        c.setFillColor(colors.black)

    y -= 12 * mm
    c.setFont("Helvetica-Oblique", 9)
    c.drawString(20 * mm, y,
                 "Je soussigné(e), bailleur, reconnais avoir reçu du locataire la somme ci-dessus")
    y -= 5 * mm
    c.drawString(20 * mm, y,
                 "au titre du loyer et des charges pour la période mentionnée, et lui en donne quittance.")
    y -= 5 * mm
    c.setFont("Helvetica-Oblique", 8)
    c.setFillColor(colors.grey)
    c.drawString(20 * mm, y, "La délivrance de la présente quittance est gratuite.")
    c.setFillColor(colors.black)

    # Signature du bailleur
    c.setFont("Helvetica", 9)
    c.drawString(125 * mm, 48 * mm, "Le bailleur")
    c.line(120 * mm, 38 * mm, 175 * mm, 38 * mm)

    c.setFont("Helvetica", 8)
    c.setFillColor(colors.grey)
    c.drawString(20 * mm, 15 * mm,
                 f"Document généré par Loyatrack le {timezone.now().strftime('%d/%m/%Y %H:%M')}")

    c.showPage()
    c.save()
    buffer.seek(0)
    return buffer.read()


# ─── Export de la liste des paiements (filtrée) ──────────────────────────────
def _fmt_montant(v):
    return f"{v:,.0f}".replace(",", " ")


def exporter_paiements_excel(paiements):
    """Classeur Excel de la liste des paiements fournie (déjà filtrée)."""
    from openpyxl import Workbook
    wb = Workbook()
    ws = wb.active
    ws.title = "Paiements"
    ws.append(['Date', 'Locataire', 'Logement', 'Montant (FCFA)', 'Mode', 'Référence'])
    total = Decimal('0')
    for p in paiements:
        ws.append([
            p.date_paiement.strftime('%d/%m/%Y') if p.date_paiement else '',
            f"{p.locataire.prenom} {p.locataire.nom}".strip(),
            p.locataire.logement or '',
            float(p.montant),
            p.mode_paiement,
            p.reference or '',
        ])
        total += p.montant
    ws.append([])
    ws.append(['', '', 'Total', float(total)])
    buf = io.BytesIO()
    wb.save(buf)
    buf.seek(0)
    return buf.read()


def exporter_paiements_pdf(paiements):
    """PDF tabulaire de la liste des paiements fournie (déjà filtrée)."""
    from reportlab.lib.pagesizes import A4
    from reportlab.lib.units import mm
    from reportlab.pdfgen import canvas

    buf = io.BytesIO()
    c = canvas.Canvas(buf, pagesize=A4)
    width, height = A4
    marge = 15 * mm
    y = height - 20 * mm

    c.setFont("Helvetica-Bold", 16)
    c.drawString(marge, y, "Liste des paiements")
    y -= 6 * mm
    c.setFont("Helvetica", 9)
    c.setFillGray(0.4)
    c.drawString(marge, y, timezone.now().strftime('Généré le %d/%m/%Y'))
    c.setFillGray(0)
    y -= 10 * mm

    # En-têtes de colonnes : Date | Locataire | Logement | Montant | Mode
    cols = [marge, marge + 28 * mm, marge + 78 * mm, marge + 120 * mm, marge + 150 * mm]
    def ligne(vals, bold=False):
        c.setFont("Helvetica-Bold" if bold else "Helvetica", 9)
        for x, v in zip(cols, vals):
            c.drawString(x, y, str(v))

    ligne(['Date', 'Locataire', 'Logement', 'Montant', 'Mode'], bold=True)
    y -= 2 * mm
    c.line(marge, y, width - marge, y)
    y -= 6 * mm

    total = Decimal('0')
    for p in paiements:
        if y < 20 * mm:  # nouvelle page
            c.showPage(); y = height - 20 * mm
        nom = f"{p.locataire.prenom} {p.locataire.nom}".strip()
        ligne([
            p.date_paiement.strftime('%d/%m/%Y') if p.date_paiement else '',
            (nom[:24]),
            (p.locataire.logement or '')[:18],
            _fmt_montant(p.montant),
            p.mode_paiement,
        ])
        total += p.montant
        y -= 6 * mm

    y -= 2 * mm
    c.line(marge, y, width - marge, y)
    y -= 7 * mm
    c.setFont("Helvetica-Bold", 11)
    c.drawString(marge, y, f"Total : {_fmt_montant(total)} FCFA")
    c.showPage()
    c.save()
    buf.seek(0)
    return buf.read()

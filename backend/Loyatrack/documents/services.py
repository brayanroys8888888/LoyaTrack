"""Génération de documents PDF conformes à la loi camerounaise n°2014/023
du 24 décembre 2014 régissant les baux à usage d'habitation (contrat de bail,
état des lieux). Module 2.2 — ReportLab."""
import base64
import calendar
import io
from datetime import date

from django.utils import timezone
from reportlab.lib import colors
from reportlab.lib.enums import TA_CENTER, TA_JUSTIFY
from reportlab.lib.pagesizes import A4
from reportlab.lib.styles import getSampleStyleSheet, ParagraphStyle
from reportlab.lib.units import mm
from reportlab.pdfgen import canvas
from reportlab.platypus import (
    SimpleDocTemplate, Paragraph, Spacer, Table, TableStyle, Image as RLImage,
)

BLANC = "________________"


def champs_manquants_contrat(locataire):
    """Informations *légalement indispensables* manquantes pour générer le
    contrat de bail (loi camerounaise n°2014/023). Renvoie une liste de dicts
    ``{'champ', 'libelle', 'cible'}`` où ``cible`` vaut ``'bailleur'`` ou
    ``'locataire'`` afin de rediriger l'utilisateur vers le bon écran.

    Tant que cette liste n'est pas vide, AUCUN document ne doit être généré.
    """
    bailleur = locataire.bailleur
    manquants = []

    def exiger(vide, champ, libelle, cible):
        if vide:
            manquants.append({'champ': champ, 'libelle': libelle, 'cible': cible})

    # ── Bailleur (mentions obligatoires : identité + adresse) ──
    nom_bailleur = f"{bailleur.first_name} {bailleur.last_name}".strip()
    exiger(not nom_bailleur, 'nom_bailleur', "Nom complet du bailleur", 'bailleur')
    exiger(not (bailleur.adresse or '').strip(), 'adresse_bailleur', "Adresse du bailleur", 'bailleur')
    exiger(not (bailleur.telephone or '').strip(), 'telephone_bailleur', "Téléphone du bailleur", 'bailleur')

    # ── Locataire (identité + désignation du logement + conditions) ──
    exiger(not (locataire.prenom or '').strip(), 'prenom', "Prénom du locataire", 'locataire')
    exiger(not (locataire.nom or '').strip(), 'nom', "Nom du locataire", 'locataire')
    exiger(not (locataire.telephone or '').strip(), 'telephone', "Téléphone du locataire", 'locataire')

    logement = (locataire.adresse_logement or locataire.logement
                or (str(locataire.unite) if locataire.unite else ''))
    exiger(not str(logement).strip(), 'adresse_logement', "Adresse du logement loué", 'locataire')

    exiger(not locataire.montant_loyer or locataire.montant_loyer <= 0,
           'montant_loyer', "Montant du loyer", 'locataire')
    exiger(not locataire.jour_echeance, 'jour_echeance', "Jour d'échéance du loyer", 'locataire')
    exiger(not locataire.date_entree, 'date_entree', "Date d'entrée dans le logement", 'locataire')
    exiger(not locataire.duree_bail_mois or locataire.duree_bail_mois <= 0,
           'duree_bail_mois', "Durée du bail (en mois)", 'locataire')
    exiger(not (locataire.frequence_paiement or '').strip(),
           'frequence_paiement', "Périodicité de paiement", 'locataire')
    exiger(not (locataire.type_piece_identite or '').strip(),
           'type_piece_identite', "Type de pièce d'identité du locataire", 'locataire')
    exiger(not (locataire.numero_piece_identite or '').strip(),
           'numero_piece_identite', "Numéro de pièce d'identité du locataire", 'locataire')

    return manquants


def _fmt(v):
    try:
        return f"{v:,.0f}".replace(",", " ")
    except Exception:
        return str(v)


def _ajouter_mois(d, mois):
    total = d.month - 1 + (mois or 0)
    annee = d.year + total // 12
    m = total % 12 + 1
    jour = min(d.day, calendar.monthrange(annee, m)[1])
    return date(annee, m, jour)


def _img_signature(b64, largeur=45 * mm, hauteur=18 * mm):
    """Renvoie un flowable image depuis une signature base64, sinon une ligne vide."""
    if b64:
        try:
            data = b64.split(',')[-1]
            return RLImage(io.BytesIO(base64.b64decode(data)),
                           width=largeur, height=hauteur, kind='proportional')
        except Exception:
            pass
    return Paragraph(BLANC, ParagraphStyle('sig', fontSize=10))


# ─────────────────────────────────────────────────────────────────────────────
# CONTRAT DE BAIL À USAGE D'HABITATION
# ─────────────────────────────────────────────────────────────────────────────
def generer_contrat_pdf(locataire):
    bailleur = locataire.bailleur
    buf = io.BytesIO()
    doc = SimpleDocTemplate(
        buf, pagesize=A4,
        leftMargin=20 * mm, rightMargin=20 * mm, topMargin=18 * mm, bottomMargin=18 * mm,
        title="Contrat de bail à usage d'habitation",
    )
    styles = getSampleStyleSheet()
    h1 = ParagraphStyle('h1', parent=styles['Title'], fontSize=16, spaceAfter=2)
    sub = ParagraphStyle('sub', parent=styles['Normal'], fontSize=8, textColor=colors.grey, alignment=TA_CENTER, spaceAfter=10)
    art = ParagraphStyle('art', parent=styles['Heading2'], fontSize=11, spaceBefore=8, spaceAfter=3)
    body = ParagraphStyle('body', parent=styles['Normal'], fontSize=10, alignment=TA_JUSTIFY, leading=14)

    bailleur_nom = f"{bailleur.first_name} {bailleur.last_name}".strip() or bailleur.email or BLANC
    bailleur_adr = (bailleur.adresse or '').strip() or BLANC
    bailleur_tel = bailleur.telephone or BLANC
    loc_nom = f"{locataire.prenom} {locataire.nom}".strip()
    logement = locataire.adresse_logement or locataire.logement or (str(locataire.unite) if locataire.unite else BLANC)
    piece = f"{locataire.type_piece_identite or ''} {locataire.numero_piece_identite or ''}".strip() or BLANC

    date_effet = locataire.date_entree
    date_fin = _ajouter_mois(date_effet, locataire.duree_bail_mois)
    freq = dict(locataire.FREQUENCE_CHOICES).get(locataire.frequence_paiement, locataire.frequence_paiement)
    charges = locataire.charges_mensuelles or 0

    el = []
    el.append(Paragraph("CONTRAT DE BAIL À USAGE D'HABITATION", h1))
    el.append(Paragraph("Régi par la loi n°2014/023 du 24 décembre 2014 (République du Cameroun)", sub))

    el.append(Paragraph("ENTRE LES SOUSSIGNÉS", art))
    el.append(Paragraph(
        f"<b>{bailleur_nom}</b>, demeurant à {bailleur_adr}, téléphone {bailleur_tel}, "
        f"ci-après dénommé(e) « <b>le Bailleur</b> », d'une part ;", body))
    el.append(Spacer(1, 4))
    el.append(Paragraph(
        f"<b>{loc_nom}</b>, demeurant à {logement}, téléphone {locataire.telephone}, "
        f"pièce d'identité : {piece}, profession : {locataire.profession or BLANC}, "
        f"ci-après dénommé(e) « <b>le Locataire</b> », d'autre part.", body))

    el.append(Paragraph("Article 1 — Objet et destination", art))
    el.append(Paragraph(
        f"Le Bailleur donne en location au Locataire, qui accepte, le logement situé à "
        f"<b>{logement}</b>. Le local est exclusivement destiné à l'<b>usage d'habitation</b> "
        f"et ne pourra recevoir une autre affectation sans l'accord écrit du Bailleur.", body))

    el.append(Paragraph("Article 2 — Durée et prise d'effet", art))
    el.append(Paragraph(
        f"Le présent bail est consenti pour une durée de <b>{locataire.duree_bail_mois} mois</b>, "
        f"à compter du <b>{date_effet.strftime('%d/%m/%Y')}</b> jusqu'au "
        f"<b>{date_fin.strftime('%d/%m/%Y')}</b>, renouvelable par tacite reconduction.", body))

    charges_txt = (
        f"Les charges récupérables s'élèvent à {_fmt(charges)} FCFA."
        if charges else "Les charges sont incluses ou nulles."
    )
    el.append(Paragraph("Article 3 — Loyer et charges", art))
    el.append(Paragraph(
        f"Le loyer est fixé à <b>{_fmt(locataire.montant_loyer)} FCFA</b>, payable d'avance "
        f"selon une périodicité <b>{freq.lower()}</b>, au plus tard le <b>{locataire.jour_echeance}</b> "
        f"de chaque échéance. {charges_txt} "
        f"Tout retard de paiement pourra donner lieu à l'application de pénalités convenues entre les parties.", body))

    el.append(Paragraph("Article 4 — Dépôt de garantie (caution)", art))
    el.append(Paragraph(
        f"Le Locataire verse au Bailleur un dépôt de garantie de "
        f"<b>{_fmt(locataire.montant_caution)} FCFA</b>, restitué en fin de bail déduction faite, "
        f"le cas échéant, des sommes dues et des réparations locatives constatées à l'état des lieux de sortie.", body))

    el.append(Paragraph("Article 5 — Obligations du Bailleur", art))
    el.append(Paragraph(
        "Le Bailleur s'oblige à délivrer un logement décent en bon état d'usage, à en assurer la "
        "jouissance paisible, à effectuer les grosses réparations et à remettre au Locataire une "
        "quittance de loyer à chaque paiement.", body))

    el.append(Paragraph("Article 6 — Obligations du Locataire", art))
    el.append(Paragraph(
        "Le Locataire s'oblige à payer le loyer et les charges aux termes convenus, à user "
        "paisiblement des lieux, à les entretenir, à s'acquitter des réparations locatives et à "
        "restituer le logement en bon état à son départ.", body))

    el.append(Paragraph("Article 7 — État des lieux", art))
    el.append(Paragraph(
        "Un état des lieux <b>contradictoire</b> est dressé et signé par les deux parties à l'entrée "
        "et à la sortie du Locataire ; il est annexé au présent contrat.", body))

    el.append(Paragraph("Article 8 — Résiliation", art))
    el.append(Paragraph(
        "À défaut de paiement ou en cas de manquement, le bail pourra être résilié après mise en "
        "demeure restée infructueuse et observation du préavis légal, conformément à la loi n°2014/023.", body))

    el.append(Spacer(1, 10))
    el.append(Paragraph(
        f"Fait à {BLANC}, le {timezone.now().strftime('%d/%m/%Y')}, "
        f"en autant d'exemplaires originaux que de parties.", body))
    el.append(Spacer(1, 16))

    sig_label = ParagraphStyle('sl', parent=body, alignment=TA_CENTER, fontSize=10)
    sig_table = Table(
        [[Paragraph("<b>Le Bailleur</b>", sig_label), Paragraph("<b>Le Locataire</b>", sig_label)],
         [_img_signature(None), _img_signature(locataire.signature_base64)]],
        colWidths=[doc.width / 2.0] * 2,
    )
    sig_table.setStyle(TableStyle([
        ('ALIGN', (0, 0), (-1, -1), 'CENTER'),
        ('VALIGN', (0, 0), (-1, -1), 'MIDDLE'),
        ('TOPPADDING', (0, 1), (-1, 1), 10),
    ]))
    el.append(sig_table)

    def _pied(c, _doc):
        c.setFont("Helvetica", 7)
        c.setFillColor(colors.grey)
        c.drawString(20 * mm, 12 * mm,
                     f"Généré par Loyatrack le {timezone.now().strftime('%d/%m/%Y %H:%M')} "
                     f"— conforme loi n°2014/023 (Cameroun)")

    doc.build(el, onFirstPage=_pied, onLaterPages=_pied)
    buf.seek(0)
    return buf.read()


# ─────────────────────────────────────────────────────────────────────────────
# ÉTAT DES LIEUX (contradictoire)
# ─────────────────────────────────────────────────────────────────────────────
def _entete(c, titre, height):
    c.setFont("Helvetica-Bold", 18)
    c.drawString(20 * mm, height - 22 * mm, titre)
    c.setFont("Helvetica", 8)
    c.setFillColor(colors.grey)
    c.drawString(20 * mm, height - 28 * mm,
                 "État des lieux contradictoire — loi n°2014/023 (Cameroun)")
    c.setFillColor(colors.black)


def _dessiner_signature(c, b64, x, y, label):
    c.setFont("Helvetica", 9)
    c.drawString(x, y + 22 * mm, label)
    if b64:
        try:
            data = b64.split(',')[-1]
            img = io.BytesIO(base64.b64decode(data))
            from reportlab.lib.utils import ImageReader
            c.drawImage(ImageReader(img), x, y, width=50 * mm, height=20 * mm,
                        preserveAspectRatio=True, mask='auto')
        except Exception:
            c.line(x, y, x + 50 * mm, y)
    else:
        c.line(x, y, x + 50 * mm, y)


def generer_etat_des_lieux_pdf(etat):
    locataire = etat.locataire
    bailleur = locataire.bailleur
    buffer = io.BytesIO()
    c = canvas.Canvas(buffer, pagesize=A4)
    width, height = A4
    libelle = dict(etat.TYPE_CHOICES).get(etat.type_etat, etat.type_etat)
    _entete(c, f"ÉTAT DES LIEUX ({libelle})", height)

    logement = locataire.adresse_logement or locataire.logement or (str(locataire.unite) if locataire.unite else "—")
    bailleur_nom = f"{bailleur.first_name} {bailleur.last_name}".strip() or bailleur.email or "—"

    y = height - 42 * mm
    c.setFont("Helvetica", 10)
    for ligne in [
        f"Bailleur : {bailleur_nom}",
        f"Locataire : {locataire.prenom} {locataire.nom}",
        f"Logement : {logement}",
        f"Date : {etat.date.strftime('%d/%m/%Y')}",
        "",
        "Le présent état des lieux est établi contradictoirement entre les parties.",
        "",
        "Observations :",
    ]:
        c.drawString(20 * mm, y, ligne)
        y -= 7 * mm

    c.setFont("Helvetica", 9)
    for line in (etat.observations or "—").splitlines() or ["—"]:
        c.drawString(24 * mm, y, line[:95])
        y -= 6 * mm

    y -= 4 * mm
    c.setFont("Helvetica-Bold", 10)
    c.drawString(20 * mm, y, "Pièces / éléments constatés :")
    y -= 8 * mm
    c.setFont("Helvetica", 9)
    photos = list(etat.photos.all())
    if photos:
        for photo in photos:
            c.drawString(24 * mm, y, f"• {photo.piece} : {photo.description or ''}"[:95])
            y -= 6 * mm
            if y < 60 * mm:
                c.showPage(); y = height - 30 * mm
    else:
        c.drawString(24 * mm, y, "—")
        y -= 6 * mm

    _dessiner_signature(c, etat.signature_bailleur_base64, 20 * mm, 35 * mm, "Le bailleur")
    _dessiner_signature(c, etat.signature_locataire_base64, 120 * mm, 35 * mm, "Le locataire")

    c.setFont("Helvetica", 7)
    c.setFillColor(colors.grey)
    c.drawString(20 * mm, 12 * mm,
                 f"Généré par Loyatrack le {timezone.now().strftime('%d/%m/%Y %H:%M')}")
    c.showPage()
    c.save()
    buffer.seek(0)
    return buffer.read()

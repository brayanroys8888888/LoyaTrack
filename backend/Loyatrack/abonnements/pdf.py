"""Reçu d'abonnement (PDF, ReportLab). Renvoie des bytes."""
import io

from django.utils import timezone

from . import constants


def generer_recu_abonnement_pdf(transaction):
    from reportlab.lib.pagesizes import A4
    from reportlab.lib.units import mm
    from reportlab.lib import colors
    from reportlab.pdfgen import canvas

    bailleur = transaction.bailleur
    buffer = io.BytesIO()
    c = canvas.Canvas(buffer, pagesize=A4)
    width, height = A4
    y = height - 30 * mm

    c.setFont("Helvetica-Bold", 20)
    c.drawString(20 * mm, y, "REÇU D'ABONNEMENT")
    c.setFont("Helvetica", 9)
    c.setFillColor(colors.grey)
    c.drawString(20 * mm, y - 6 * mm, "Loyatrack — Gestion locative")
    c.setFillColor(colors.black)

    y -= 22 * mm

    def ligne(label, valeur):
        nonlocal y
        c.setFont("Helvetica-Bold", 10)
        c.drawString(20 * mm, y, label)
        c.setFont("Helvetica", 10)
        c.drawString(80 * mm, y, str(valeur))
        y -= 8 * mm

    def fcfa(v):
        return f"{v:,.0f} FCFA".replace(",", " ")

    nom = f"{bailleur.first_name} {bailleur.last_name}".strip() or bailleur.email or "________"
    plan_nom = constants.PLANS.get(transaction.plan, {}).get('nom', transaction.plan)
    date_p = transaction.date_paiement or transaction.date_creation

    ligne("Bailleur :", nom)
    if bailleur.email:
        ligne("Email :", bailleur.email)
    ligne("N° reçu :", f"AB-{transaction.id:06d}")
    ligne("Date :", date_p.strftime("%d/%m/%Y %H:%M"))
    ligne("Formule :", f"{plan_nom} ({transaction.get_periodicite_display()})")
    ligne("Référence :", str(transaction.reference_interne))
    ligne("Moyen de paiement :", transaction.prestataire)

    y -= 4 * mm
    c.setStrokeColor(colors.lightgrey)
    c.line(20 * mm, y, width - 20 * mm, y)
    y -= 10 * mm

    c.setFont("Helvetica-Bold", 13)
    c.drawString(20 * mm, y, "Montant payé :")
    c.drawString(80 * mm, y, fcfa(transaction.montant))
    y -= 14 * mm

    c.setFont("Helvetica-Oblique", 9)
    c.setFillColor(colors.grey)
    c.drawString(20 * mm, y, "Paiement reçu. Merci de votre confiance.")
    c.setFillColor(colors.black)

    c.setFont("Helvetica", 8)
    c.setFillColor(colors.grey)
    c.drawString(20 * mm, 15 * mm,
                 f"Document généré par Loyatrack le {timezone.now().strftime('%d/%m/%Y %H:%M')}")

    c.showPage()
    c.save()
    buffer.seek(0)
    return buffer.read()

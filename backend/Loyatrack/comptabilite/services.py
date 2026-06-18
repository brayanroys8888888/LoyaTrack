"""Relevé annuel et exports comptables (Excel/PDF) — module 3.4."""
import io
from decimal import Decimal

from django.db.models import Sum

from .models import Depense


def releve_annuel(bailleur, annee):
    from paiements.models import Paiement
    from biens.models import Propriete

    loyers = Paiement.objects.filter(
        locataire__bailleur=bailleur, date_paiement__year=annee
    ).aggregate(t=Sum('montant'))['t'] or Decimal('0')

    depenses_qs = Depense.objects.filter(bailleur=bailleur, date__year=annee)
    depenses_total = depenses_qs.aggregate(t=Sum('montant'))['t'] or Decimal('0')

    par_categorie = {
        d['categorie']: d['t']
        for d in depenses_qs.values('categorie').annotate(t=Sum('montant'))
    }

    par_bien = []
    for prop in Propriete.objects.filter(bailleur=bailleur):
        revenus_bien = Paiement.objects.filter(
            locataire__unite__propriete=prop, date_paiement__year=annee
        ).aggregate(t=Sum('montant'))['t'] or Decimal('0')
        depenses_bien = depenses_qs.filter(bien=prop).aggregate(t=Sum('montant'))['t'] or Decimal('0')
        par_bien.append({
            'bien': prop.titre,
            'revenus': revenus_bien,
            'depenses': depenses_bien,
            'rentabilite': revenus_bien - depenses_bien,
        })

    return {
        'annee': annee,
        'loyers_percus': loyers,
        'depenses_total': depenses_total,
        'revenu_net': loyers - depenses_total,
        'depenses_par_categorie': par_categorie,
        'par_bien': par_bien,
    }


def export_excel(releve):
    from openpyxl import Workbook
    wb = Workbook()
    ws = wb.active
    ws.title = f"Relevé {releve['annee']}"
    ws.append(['Relevé annuel', releve['annee']])
    ws.append([])
    ws.append(['Loyers perçus', float(releve['loyers_percus'])])
    ws.append(['Dépenses totales', float(releve['depenses_total'])])
    ws.append(['Revenu net', float(releve['revenu_net'])])
    ws.append([])
    ws.append(['Rentabilité par bien'])
    ws.append(['Bien', 'Revenus', 'Dépenses', 'Rentabilité'])
    for b in releve['par_bien']:
        ws.append([b['bien'], float(b['revenus']), float(b['depenses']), float(b['rentabilite'])])
    buf = io.BytesIO()
    wb.save(buf)
    buf.seek(0)
    return buf.read()


def export_pdf(releve):
    from reportlab.lib.pagesizes import A4
    from reportlab.lib.units import mm
    from reportlab.pdfgen import canvas

    buf = io.BytesIO()
    c = canvas.Canvas(buf, pagesize=A4)
    width, height = A4
    y = height - 25 * mm
    c.setFont("Helvetica-Bold", 18)
    c.drawString(20 * mm, y, f"Relevé annuel {releve['annee']}")
    y -= 14 * mm
    c.setFont("Helvetica", 11)
    for label, val in [
        ("Loyers perçus", releve['loyers_percus']),
        ("Dépenses totales", releve['depenses_total']),
        ("Revenu net", releve['revenu_net']),
    ]:
        c.drawString(20 * mm, y, f"{label} : {val:,.0f} FCFA".replace(",", " "))
        y -= 8 * mm
    y -= 6 * mm
    c.setFont("Helvetica-Bold", 12)
    c.drawString(20 * mm, y, "Rentabilité par bien")
    y -= 8 * mm
    c.setFont("Helvetica", 10)
    for b in releve['par_bien']:
        c.drawString(24 * mm, y, f"{b['bien']} : net {b['rentabilite']:,.0f} FCFA".replace(",", " "))
        y -= 7 * mm
    c.showPage()
    c.save()
    buf.seek(0)
    return buf.read()

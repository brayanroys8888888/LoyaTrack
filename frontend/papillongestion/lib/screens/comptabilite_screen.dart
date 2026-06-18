import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import '../theme/app_theme.dart';
import '../models/models.dart';
import '../widgets/shared_widgets.dart';
import '../services/comptabilite_service.dart';
import '../core/pdf_helper.dart';

/// Libellé localisé d'une catégorie de dépense (valeur stockée = clé FR).
String catDepenseLabelL(String? cat, AppLocalizations t) => switch (cat) {
  'entretien' => t.catMaintenance,
  'taxe' => t.catTax,
  'charge' => t.catCharge,
  'assurance' => t.catInsurance,
  _ => t.catOther,
};

class ComptabiliteScreen extends StatefulWidget {
  const ComptabiliteScreen({super.key});
  @override
  State<ComptabiliteScreen> createState() => _ComptabiliteScreenState();
}

class _ComptabiliteScreenState extends State<ComptabiliteScreen> {
  final _service = ComptabiliteService();
  final int _annee = DateTime.now().year;
  Map<String, dynamic>? _releve;
  List<dynamic> _depenses = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _fetch();
  }

  Future<void> _fetch() async {
    setState(() => _loading = true);
    final results = await Future.wait([
      _service.getReleve(_annee),
      _service.getDepenses(annee: _annee),
    ]);
    if (!mounted) return;
    setState(() {
      _releve = results[0] as Map<String, dynamic>?;
      _depenses = results[1] as List<dynamic>;
      _loading = false;
    });
  }

  Future<void> _ajouterDepense() async {
    final ok = await showFormSheet<bool>(context, builder: (_) => const _AjoutDepenseDialog());
    if (ok == true) _fetch();
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final r = _releve;
    return Scaffold(
      backgroundColor: context.bg,
      appBar: AppBar(
        backgroundColor: context.bg, elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_ios_new_rounded, color: context.cText, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(t.accounting(_annee), style: TextStyle(color: context.cText, fontSize: 18, fontWeight: FontWeight.w800)),
        actions: [
          IconButton(
            tooltip: t.exportExcel,
            icon: Icon(Icons.table_chart_outlined, color: context.cText),
            onPressed: () async {
              final b = await _service.exportReleve(_annee, pdf: false);
              if (mounted) await ouvrirPdf(context, b, 'releve_$_annee.xlsx');
            },
          ),
          IconButton(
            tooltip: t.exportPdf,
            icon: Icon(Icons.picture_as_pdf_outlined, color: context.cText),
            onPressed: () async {
              final b = await _service.exportReleve(_annee, pdf: true);
              if (mounted) await ouvrirPdf(context, b, 'releve_$_annee.pdf');
            },
          ),
          IconButton(
            tooltip: t.expenseShort,
            icon: const Icon(Icons.add_rounded, color: AppColors.blue),
            onPressed: _ajouterDepense,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _fetch,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
                children: [
                  if (r != null) Row(children: [
                    _stat(t.rentCollected, r['loyers_percus'], context.cSuccessBg, AppColors.success),
                    const SizedBox(width: 10),
                    _stat(t.expenses, r['depenses_total'], context.cDangerBg, AppColors.danger),
                    const SizedBox(width: 10),
                    _stat(t.netIncome, r['revenu_net'], context.cBlue3, AppColors.blue),
                  ]),
                  const SizedBox(height: 20),
                  Text(t.expenses, style: TextStyle(fontWeight: FontWeight.w700, color: context.cText)),
                  const SizedBox(height: 8),
                  if (_depenses.isEmpty)
                    Padding(padding: const EdgeInsets.all(16),
                        child: Text(t.noExpenses, style: TextStyle(color: context.cTextSub)))
                  else
                    ..._depenses.map((d) => Container(
                          margin: const EdgeInsets.only(bottom: 8),
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(color: context.cCard, borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: context.cBorder)),
                          child: Row(children: [
                            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Text(d['libelle'] ?? '', style: TextStyle(fontWeight: FontWeight.w600, color: context.cText)),
                              Text('${catDepenseLabelL(d['categorie'], t)} · ${d['date']}', style: TextStyle(fontSize: 11, color: context.cTextSub)),
                            ])),
                            Text('-${formatMontant(double.tryParse(d['montant'].toString()) ?? 0)} F',
                                style: const TextStyle(fontWeight: FontWeight.w700, color: AppColors.danger)),
                          ]),
                        )),
                ],
              ),
            ),
    );
  }

  Widget _stat(String label, dynamic value, Color bg, Color fg) {
    final v = double.tryParse(value?.toString() ?? '0') ?? 0;
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(12)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label, style: TextStyle(fontSize: 10, color: fg, fontWeight: FontWeight.w600)),
          const SizedBox(height: 4),
          Text(formatMontant(v), style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15, color: fg)),
          Text('FCFA', style: TextStyle(fontSize: 9, color: fg.withOpacity(0.7))),
        ]),
      ),
    );
  }
}

class _AjoutDepenseDialog extends StatefulWidget {
  const _AjoutDepenseDialog();
  @override
  State<_AjoutDepenseDialog> createState() => _AjoutDepenseDialogState();
}

class _AjoutDepenseDialogState extends State<_AjoutDepenseDialog> {
  final _libelle = TextEditingController();
  final _montant = TextEditingController();
  String _categorie = 'entretien';
  DateTime _date = DateTime.now();
  bool _saving = false;

  static const _categories = ['entretien', 'taxe', 'charge', 'assurance', 'autre'];

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    return Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      sheetHeader(context, t.newExpense),
      TextField(controller: _libelle, style: TextStyle(color: context.cText),
          decoration: InputDecoration(labelText: t.expenseLabel)),
      const SizedBox(height: 12),
      TextField(controller: _montant, keyboardType: TextInputType.number, style: TextStyle(color: context.cText),
          decoration: InputDecoration(labelText: t.amountFcfaLabel)),
      const SizedBox(height: 12),
      DropdownButtonFormField<String>(
        value: _categorie,
        dropdownColor: context.cCard,
        decoration: InputDecoration(labelText: t.category),
        items: _categories.map((c) => DropdownMenuItem(value: c, child: Text(catDepenseLabelL(c, t), style: TextStyle(color: context.cText)))).toList(),
        onChanged: (v) => setState(() => _categorie = v ?? 'entretien'),
      ),
      const SizedBox(height: 8),
      Row(children: [
        Expanded(child: Text('${_date.day}/${_date.month}/${_date.year}', style: TextStyle(color: context.cText))),
        TextButton.icon(
          icon: const Icon(Icons.calendar_month_outlined, size: 18),
          onPressed: () async {
            final d = await showDatePicker(context: context, initialDate: _date,
                firstDate: DateTime(2020), lastDate: DateTime(2100));
            if (d != null) setState(() => _date = d);
          },
          label: Text(t.date),
        ),
      ]),
      const SizedBox(height: 16),
      Row(children: [
        Expanded(child: OutlinedButton(onPressed: () => Navigator.pop(context), child: Text(t.cancel))),
        const SizedBox(width: 12),
        Expanded(child: ElevatedButton(
          style: ElevatedButton.styleFrom(backgroundColor: AppColors.blue, foregroundColor: Colors.white),
          onPressed: _saving ? null : () async {
            if (_libelle.text.trim().isEmpty) return;
            setState(() => _saving = true);
            final ok = await ComptabiliteService().createDepense(
              libelle: _libelle.text.trim(),
              montant: double.tryParse(_montant.text) ?? 0,
              date: _date, categorie: _categorie,
            );
            if (context.mounted) Navigator.pop(context, ok);
          },
          child: Text(t.add),
        )),
      ]),
    ]);
  }
}

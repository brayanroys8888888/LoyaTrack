import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import '../theme/app_theme.dart';
import '../models/bien.dart';
import '../models/models.dart';
import '../widgets/shared_widgets.dart';
import '../services/bien_service.dart';

/// Libellé localisé d'un type de bien (la valeur stockée reste la clé FR).
String typeBienLabelL(String type, AppLocalizations t) => switch (type) {
  'appartement' => t.typeApartment,
  'villa' => t.typeVilla,
  'studio' => t.typeStudio,
  'immeuble' => t.typeBuilding,
  _ => t.typeOther,
};

class BiensScreen extends StatefulWidget {
  const BiensScreen({super.key});
  @override
  State<BiensScreen> createState() => _BiensScreenState();
}

class _BiensScreenState extends State<BiensScreen> {
  final _service = BienService();
  List<Propriete> _biens = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _fetch();
  }

  Future<void> _fetch() async {
    setState(() => _loading = true);
    final biens = await _service.getProprietes();
    if (mounted) setState(() { _biens = biens; _loading = false; });
  }

  Future<void> _ajouterBien() async {
    final cree = await showCreerBien(context);
    if (cree != null) _fetch();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.bg,
      appBar: AppBar(
        backgroundColor: context.bg,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_ios_new_rounded, color: context.cText, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(AppLocalizations.of(context).myProperties, style: TextStyle(color: context.cText, fontSize: 18, fontWeight: FontWeight.w800)),
        actions: [
          IconButton(
            tooltip: AppLocalizations.of(context).propertyShort,
            icon: const Icon(Icons.add_rounded, color: AppColors.blue),
            onPressed: _ajouterBien,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _fetch,
              child: _biens.isEmpty
                  ? ListView(children: [
                      const SizedBox(height: 120),
                      Icon(Icons.apartment_rounded, size: 56, color: context.cHint),
                      const SizedBox(height: 12),
                      Center(child: Text(AppLocalizations.of(context).noProperties, style: TextStyle(color: context.cTextSub))),
                    ])
                  : ListView.builder(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
                      itemCount: _biens.length,
                      itemBuilder: (_, i) => _BienCard(
                        bien: _biens[i],
                        onTap: () async {
                          await Navigator.push(context, slideRoute(BienDetailScreen(bien: _biens[i])));
                          _fetch();
                        },
                      ),
                    ),
            ),
    );
  }
}

class _BienCard extends StatelessWidget {
  final Propriete bien;
  final VoidCallback onTap;
  const _BienCard({required this.bien, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final taux = bien.tauxOccupation;
    final couleur = taux >= 80 ? AppColors.success : (taux >= 40 ? AppColors.warning : AppColors.danger);
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: context.cCard,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: context.cBorder),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Container(
                width: 44, height: 44,
                decoration: BoxDecoration(color: context.cBlue3, borderRadius: BorderRadius.circular(12)),
                child: const Icon(Icons.apartment_rounded, color: AppColors.blue),
              ),
              const SizedBox(width: 12),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(bien.titre, style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15, color: context.cText)),
                Text(bien.adresse.isEmpty ? bien.type : bien.adresse,
                    style: TextStyle(fontSize: 12, color: context.cTextSub)),
              ])),
              const Icon(Icons.chevron_right_rounded, color: AppColors.blue),
            ]),
            const SizedBox(height: 14),
            // Barre de taux d'occupation
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: LinearProgressIndicator(
                value: taux / 100,
                minHeight: 8,
                backgroundColor: context.cBorder,
                valueColor: AlwaysStoppedAnimation(couleur),
              ),
            ),
            const SizedBox(height: 8),
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              Text(AppLocalizations.of(context).occupancySummary(bien.nbOccupees, bien.nbUnites, taux.toStringAsFixed(0)),
                  style: TextStyle(fontSize: 12, color: context.cTextSub)),
              Text('${formatMontant(bien.revenusAttendus)} FCFA',
                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.success)),
            ]),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────── Détail d'un bien (unités) ───────────────────
class BienDetailScreen extends StatefulWidget {
  final Propriete bien;
  const BienDetailScreen({required this.bien, super.key});
  @override
  State<BienDetailScreen> createState() => _BienDetailScreenState();
}

class _BienDetailScreenState extends State<BienDetailScreen> {
  final _service = BienService();
  List<UniteLogement> _unites = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _fetch();
  }

  Future<void> _fetch() async {
    setState(() => _loading = true);
    final u = await _service.getUnites(proprieteId: widget.bien.id);
    if (mounted) setState(() { _unites = u; _loading = false; });
  }

  Future<void> _ajouterUnite() async {
    final cree = await showCreerUnite(context, widget.bien.id);
    if (cree != null) _fetch();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.bg,
      appBar: AppBar(
        backgroundColor: context.bg,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_ios_new_rounded, color: context.cText, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(widget.bien.titre, style: TextStyle(color: context.cText, fontSize: 18, fontWeight: FontWeight.w800)),
        actions: [
          IconButton(
            tooltip: AppLocalizations.of(context).unitShort,
            icon: const Icon(Icons.add_rounded, color: AppColors.blue),
            onPressed: _ajouterUnite,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _fetch,
              child: _unites.isEmpty
                  ? ListView(children: [
                      const SizedBox(height: 120),
                      Center(child: Text(AppLocalizations.of(context).noUnits, style: TextStyle(color: context.cTextSub))),
                    ])
                  : ListView.builder(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
                      itemCount: _unites.length,
                      itemBuilder: (_, i) {
                        final u = _unites[i];
                        final occ = u.estOccupee;
                        return Container(
                          margin: const EdgeInsets.only(bottom: 10),
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: context.cCard,
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(color: context.cBorder),
                          ),
                          child: Row(children: [
                            Icon(occ ? Icons.person_rounded : Icons.meeting_room_outlined,
                                color: occ ? AppColors.success : context.cHint),
                            const SizedBox(width: 12),
                            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Text(u.numero, style: TextStyle(fontWeight: FontWeight.w700, color: context.cText)),
                              Text(u.locataireNom ?? AppLocalizations.of(context).vacant, style: TextStyle(fontSize: 12, color: context.cTextSub)),
                            ])),
                            Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                              Text('${formatMontant(u.loyerStandard)} F',
                                  style: const TextStyle(fontWeight: FontWeight.w700, color: AppColors.blue)),
                              Container(
                                margin: const EdgeInsets.only(top: 4),
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                decoration: BoxDecoration(
                                  color: occ ? context.cSuccessBg : context.cBorder,
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Text(occ ? AppLocalizations.of(context).occupied : AppLocalizations.of(context).vacant,
                                    style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600,
                                        color: occ ? AppColors.success : context.cTextSub)),
                              ),
                            ]),
                          ]),
                        );
                      },
                    ),
            ),
    );
  }
}

// ─── Helpers publics : créer un bien / une unité depuis n'importe quel écran ──
/// Ouvre le bottom sheet de création de bien ; renvoie le bien créé ou null.
Future<Propriete?> showCreerBien(BuildContext context) =>
    showFormSheet<Propriete>(context, builder: (_) => const _AjoutBienDialog());

/// Ouvre le bottom sheet de création d'unité pour un bien ; renvoie l'unité créée ou null.
Future<UniteLogement?> showCreerUnite(BuildContext context, int proprieteId) =>
    showFormSheet<UniteLogement>(context, builder: (_) => _AjoutUniteDialog(proprieteId: proprieteId));

// ─────────────────────────────── Dialogs ─────────────────────────────────────
class _AjoutBienDialog extends StatefulWidget {
  const _AjoutBienDialog();
  @override
  State<_AjoutBienDialog> createState() => _AjoutBienDialogState();
}

class _AjoutBienDialogState extends State<_AjoutBienDialog> {
  final _titre = TextEditingController();
  final _adresse = TextEditingController();
  String _type = 'immeuble';
  bool _saving = false;

  static const _types = ['appartement', 'villa', 'studio', 'immeuble', 'autre'];

  @override
  Widget build(BuildContext context) {
    final tr = AppLocalizations.of(context);
    return Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      sheetHeader(context, tr.newProperty),
      TextField(controller: _titre, style: TextStyle(color: context.cText),
          decoration: InputDecoration(labelText: tr.propertyTitleHint)),
      const SizedBox(height: 12),
      TextField(controller: _adresse, style: TextStyle(color: context.cText),
          decoration: InputDecoration(labelText: tr.addressOptional)),
      const SizedBox(height: 12),
      DropdownButtonFormField<String>(
        value: _type,
        dropdownColor: context.cCard,
        decoration: InputDecoration(labelText: tr.typeLabel),
        items: _types.map((t) => DropdownMenuItem(value: t, child: Text(typeBienLabelL(t, tr), style: TextStyle(color: context.cText)))).toList(),
        onChanged: (v) => setState(() => _type = v ?? 'immeuble'),
      ),
      const SizedBox(height: 16),
      Row(children: [
        Expanded(child: OutlinedButton(onPressed: () => Navigator.pop(context), child: Text(tr.cancel))),
        const SizedBox(width: 12),
        Expanded(child: ElevatedButton(
          style: ElevatedButton.styleFrom(backgroundColor: AppColors.blue, foregroundColor: Colors.white),
          onPressed: _saving ? null : () async {
            if (_titre.text.trim().isEmpty) return;
            setState(() => _saving = true);
            final res = await BienService().createPropriete(
              titre: _titre.text.trim(), type: _type, adresse: _adresse.text.trim());
            if (context.mounted) Navigator.pop(context, res);
          },
          child: Text(tr.create),
        )),
      ]),
    ]);
  }
}

class _AjoutUniteDialog extends StatefulWidget {
  final int proprieteId;
  const _AjoutUniteDialog({required this.proprieteId});
  @override
  State<_AjoutUniteDialog> createState() => _AjoutUniteDialogState();
}

class _AjoutUniteDialogState extends State<_AjoutUniteDialog> {
  final _numero = TextEditingController();
  final _loyer = TextEditingController();
  bool _saving = false;

  @override
  Widget build(BuildContext context) {
    final tr = AppLocalizations.of(context);
    return Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      sheetHeader(context, tr.newUnit),
      TextField(controller: _numero, style: TextStyle(color: context.cText),
          decoration: InputDecoration(labelText: tr.unitNumberHint)),
      const SizedBox(height: 12),
      TextField(controller: _loyer, keyboardType: TextInputType.number, style: TextStyle(color: context.cText),
          decoration: InputDecoration(labelText: tr.standardRent)),
      const SizedBox(height: 16),
      Row(children: [
        Expanded(child: OutlinedButton(onPressed: () => Navigator.pop(context), child: Text(tr.cancel))),
        const SizedBox(width: 12),
        Expanded(child: ElevatedButton(
          style: ElevatedButton.styleFrom(backgroundColor: AppColors.blue, foregroundColor: Colors.white),
          onPressed: _saving ? null : () async {
            if (_numero.text.trim().isEmpty) return;
            setState(() => _saving = true);
            final res = await BienService().createUnite(
              proprieteId: widget.proprieteId,
              numero: _numero.text.trim(),
              loyerStandard: double.tryParse(_loyer.text) ?? 0,
            );
            if (context.mounted) Navigator.pop(context, res);
          },
          child: Text(tr.create),
        )),
      ]),
    ]);
  }
}

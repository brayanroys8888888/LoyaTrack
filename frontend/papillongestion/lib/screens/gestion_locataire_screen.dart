import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import '../theme/app_theme.dart';
import '../models/models.dart';
import '../widgets/shared_widgets.dart';
import '../services/locataire_service.dart';
import 'etat_des_lieux_screen.dart';

/// Écran de gestion avancée d'un locataire : caution, augmentation de loyer,
/// résiliation du bail (modules 3.2 / 3.3 / 2.7).
class GestionLocataireScreen extends StatefulWidget {
  final Locataire locataire;
  const GestionLocataireScreen({required this.locataire, super.key});
  @override
  State<GestionLocataireScreen> createState() => _GestionLocataireScreenState();
}

class _GestionLocataireScreenState extends State<GestionLocataireScreen> {
  final _service = LocataireService();

  void _snack(String m, Color c) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m), backgroundColor: c));
  }

  Future<DateTime?> _pickDate() => showDatePicker(
        context: context,
        initialDate: DateTime.now(),
        firstDate: DateTime(2020),
        lastDate: DateTime(2100),
      );

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final loc = widget.locataire;
    return Scaffold(
      backgroundColor: context.bg,
      appBar: AppBar(
        backgroundColor: context.bg,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_ios_new_rounded, color: context.cText, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(t.manageTitle(loc.nom),
            style: TextStyle(color: context.cText, fontSize: 17, fontWeight: FontWeight.w800)),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _Section(
            icon: Icons.savings_outlined,
            color: AppColors.blue,
            titre: t.deposit,
            children: [
              ElevatedButton.icon(
                onPressed: _dialogVerserCaution,
                icon: const Icon(Icons.add),
                label: Text(t.recordDeposit),
                style: _btn(AppColors.blue),
              ),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: _dialogRestituerCaution,
                icon: const Icon(Icons.undo_rounded),
                label: Text(t.refundDeposit),
              ),
            ],
          ),
          _Section(
            icon: Icons.trending_up_rounded,
            color: AppColors.success,
            titre: t.rentIncrease,
            children: [
              ElevatedButton.icon(
                onPressed: _dialogAugmenter,
                icon: const Icon(Icons.edit_rounded),
                label: Text(t.scheduleIncrease),
                style: _btn(AppColors.success),
              ),
            ],
          ),
          _Section(
            icon: Icons.checklist_rounded,
            color: AppColors.warning,
            titre: t.inventory,
            children: [
              OutlinedButton.icon(
                onPressed: () => Navigator.push(context, slideRoute(EtatDesLieuxScreen(locataire: widget.locataire))),
                icon: const Icon(Icons.checklist_rounded),
                label: Text(t.manageInventory),
              ),
            ],
          ),
          _Section(
            icon: Icons.exit_to_app_rounded,
            color: AppColors.danger,
            titre: t.endOfLease,
            children: [
              OutlinedButton.icon(
                onPressed: _dialogResilier,
                icon: const Icon(Icons.gavel_rounded, color: AppColors.danger),
                label: Text(t.terminateLease, style: const TextStyle(color: AppColors.danger)),
                style: OutlinedButton.styleFrom(side: const BorderSide(color: AppColors.danger)),
              ),
            ],
          ),
        ],
      ),
    );
  }

  ButtonStyle _btn(Color c) => ElevatedButton.styleFrom(
        backgroundColor: c, foregroundColor: Colors.white,
        minimumSize: const Size.fromHeight(46),
      );

  // ---- Dialogs ----
  Future<void> _dialogVerserCaution() async {
    final t = AppLocalizations.of(context);
    final ctrl = TextEditingController(
        text: widget.locataire.montantLoyer > 0 ? widget.locataire.montantLoyer.toInt().toString() : '');
    final ok = await _montantDialog(t.depositPayment, ctrl);
    if (ok != true) return;
    final date = await _pickDate();
    if (date == null) return;
    final res = await _service.verserCaution(widget.locataire.id,
        montant: double.tryParse(ctrl.text) ?? 0, date: date);
    _snack(res ? t.depositRecorded : t.error, res ? AppColors.success : AppColors.danger);
  }

  Future<void> _dialogRestituerCaution() async {
    final t = AppLocalizations.of(context);
    final ctrl = TextEditingController();
    final ok = await _montantDialog(t.amountRefunded, ctrl);
    if (ok != true) return;
    final date = await _pickDate();
    if (date == null) return;
    final res = await _service.restituerCaution(widget.locataire.id,
        montant: double.tryParse(ctrl.text) ?? 0, date: date);
    _snack(res ? t.refundRecorded : t.error, res ? AppColors.success : AppColors.danger);
  }

  Future<void> _dialogAugmenter() async {
    final t = AppLocalizations.of(context);
    final ctrl = TextEditingController();
    final ok = await _montantDialog(t.newRentFcfa, ctrl);
    if (ok != true) return;
    final date = await _pickDate();
    if (date == null) return;
    final res = await _service.augmenterLoyer(widget.locataire.id,
        montant: double.tryParse(ctrl.text) ?? 0, dateDebut: date, motif: 'Révision');
    _snack(res ? t.increaseScheduled : t.error, res ? AppColors.success : AppColors.danger);
  }

  Future<void> _dialogResilier() async {
    final t = AppLocalizations.of(context);
    final motif = TextEditingController();
    final confirm = await showFormSheet<bool>(
      context,
      builder: (_) => Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        sheetHeader(context, t.terminateLease),
        TextField(controller: motif, style: TextStyle(color: context.cText),
            decoration: InputDecoration(labelText: t.reasonOptional)),
        const SizedBox(height: 16),
        Row(children: [
          Expanded(child: OutlinedButton(onPressed: () => Navigator.pop(context, false), child: Text(t.cancel))),
          const SizedBox(width: 12),
          Expanded(child: ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.danger, foregroundColor: Colors.white),
            child: Text(t.confirm),
          )),
        ]),
      ]),
    );
    if (confirm != true) return;
    final date = await _pickDate();
    if (date == null) return;
    final res = await _service.resilier(widget.locataire.id, dateSortie: date, motif: motif.text);
    _snack(res ? t.leaseTerminated : t.error, res ? AppColors.success : AppColors.danger);
    if (res && mounted) Navigator.pop(context, true);
  }

  Future<bool?> _montantDialog(String titre, TextEditingController ctrl) {
    final t = AppLocalizations.of(context);
    return showFormSheet<bool>(
        context,
        builder: (_) => Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          sheetHeader(context, titre),
          TextField(
            controller: ctrl,
            keyboardType: TextInputType.number,
            autofocus: true,
            style: TextStyle(color: context.cText),
            decoration: InputDecoration(labelText: t.amountFcfaLabel),
          ),
          const SizedBox(height: 16),
          Row(children: [
            Expanded(child: OutlinedButton(onPressed: () => Navigator.pop(context, false), child: Text(t.cancel))),
            const SizedBox(width: 12),
            Expanded(child: ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: AppColors.blue, foregroundColor: Colors.white),
              onPressed: () => Navigator.pop(context, true), child: Text(t.next))),
          ]),
        ]),
      );
  }
}

class _Section extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String titre;
  final List<Widget> children;
  const _Section({required this.icon, required this.color, required this.titre, required this.children});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: context.cCard,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: context.cBorder),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(width: 8),
          Text(titre, style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15, color: context.cText)),
        ]),
        const SizedBox(height: 12),
        ...children,
      ]),
    );
  }
}

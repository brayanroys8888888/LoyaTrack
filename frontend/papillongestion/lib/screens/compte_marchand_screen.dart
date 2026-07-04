import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import '../theme/app_theme.dart';
import '../services/paiement_service.dart';

/// Compte d'encaissement du bailleur (mode « encaissement centralisé ») :
/// LoyaTrack encaisse les loyers sur son compte plateforme puis reverse
/// automatiquement sur le numéro Mobile Money renseigné ici. Le bailleur
/// ne fournit donc aucune clé d'API — seulement où recevoir son argent.
class CompteMarchandScreen extends StatefulWidget {
  const CompteMarchandScreen({super.key});
  @override
  State<CompteMarchandScreen> createState() => _CompteMarchandScreenState();
}

class _CompteMarchandScreenState extends State<CompteMarchandScreen> {
  final _svc = PaiementService();
  final _numero = TextEditingController();
  final _frais = TextEditingController(text: '2');
  String _operateur = 'mtn';
  bool _actif = false;
  bool _loading = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _svc.getCompteMarchand().then((c) {
      if (!mounted) return;
      setState(() {
        if (c != null) {
          _numero.text = c['numero_momo']?.toString() ?? '';
          _operateur = c['operateur']?.toString() ?? 'mtn';
          _frais.text =
              (c['frais_pourcentage']?.toString() ?? '2').replaceAll('.00', '');
          _actif = c['actif'] == true;
        }
        _loading = false;
      });
    });
  }

  @override
  void dispose() {
    _numero.dispose();
    _frais.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final t = AppLocalizations.of(context);
    setState(() => _saving = true);
    final data = <String, dynamic>{
      'numero_momo': _numero.text.trim(),
      'operateur': _operateur,
      'frais_pourcentage': double.tryParse(_frais.text.trim()) ?? 2.0,
      'actif': _actif,
    };
    final ok = await _svc.updateCompteMarchand(data);
    if (!mounted) return;
    setState(() => _saving = false);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(ok ? t.merchantSaved : t.networkError),
      backgroundColor: ok ? AppColors.success : AppColors.danger,
    ));
    if (ok) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    return Scaffold(
      backgroundColor: context.bg,
      appBar: AppBar(
        backgroundColor: context.bg,
        elevation: 0,
        title: Text(t.merchantAccount,
            style: TextStyle(color: context.cText, fontWeight: FontWeight.w700)),
        iconTheme: IconThemeData(color: context.cText),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(20),
              children: [
                Text(t.merchantIntro,
                    style:
                        TextStyle(fontSize: 13, color: context.cTextSub, height: 1.4)),
                const SizedBox(height: 20),
                // Opérateur (MTN / Orange).
                Text(t.merchantOperator,
                    style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: context.cText)),
                const SizedBox(height: 8),
                Row(children: [
                  _OperateurChip(
                    label: t.merchantMtn,
                    selected: _operateur == 'mtn',
                    color: const Color(0xFFFFCC00),
                    onTap: () => setState(() => _operateur = 'mtn'),
                  ),
                  const SizedBox(width: 10),
                  _OperateurChip(
                    label: t.merchantOrange,
                    selected: _operateur == 'orange',
                    color: const Color(0xFFFF6600),
                    onTap: () => setState(() => _operateur = 'orange'),
                  ),
                ]),
                const SizedBox(height: 18),
                _field(_numero, t.merchantMomoNumber, Icons.smartphone_rounded,
                    number: true, hint: t.merchantMomoHint),
                _field(_frais, t.merchantFees, Icons.percent_rounded,
                    number: true),
                const SizedBox(height: 4),
                SwitchListTile(
                  value: _actif,
                  onChanged: (v) => setState(() => _actif = v),
                  activeColor: AppColors.blue,
                  contentPadding: EdgeInsets.zero,
                  title: Text(t.merchantActive,
                      style: TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 14,
                          color: context.cText)),
                ),
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: ElevatedButton(
                    onPressed: _saving ? null : _save,
                    style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.blue,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14))),
                    child: _saving
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Colors.white))
                        : Text(t.save,
                            style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w700,
                                fontSize: 15)),
                  ),
                ),
              ],
            ),
    );
  }

  Widget _field(TextEditingController c, String label, IconData icon,
      {bool number = false, String? hint}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: TextField(
        controller: c,
        keyboardType: number ? TextInputType.phone : TextInputType.text,
        style: TextStyle(color: context.cText),
        decoration: InputDecoration(
          labelText: label,
          hintText: hint,
          prefixIcon: Icon(icon, size: 18, color: context.cHint),
          border:
              OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        ),
      ),
    );
  }
}

class _OperateurChip extends StatelessWidget {
  final String label;
  final bool selected;
  final Color color;
  final VoidCallback onTap;
  const _OperateurChip({
    required this.label,
    required this.selected,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 12),
          decoration: BoxDecoration(
            color: selected ? color.withOpacity(0.15) : context.cCard,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
                color: selected ? color : context.cBorder,
                width: selected ? 1.6 : 1),
          ),
          child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            ),
            const SizedBox(width: 8),
            Flexible(
              child: Text(label,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      fontSize: 12.5,
                      fontWeight:
                          selected ? FontWeight.w700 : FontWeight.w500,
                      color: context.cText)),
            ),
          ]),
        ),
      ),
    );
  }
}

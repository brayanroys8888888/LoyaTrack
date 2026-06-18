import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import '../theme/app_theme.dart';
import '../services/parametres_service.dart';

/// Changement de mot de passe pour l'utilisateur connecté.
class ChangePasswordScreen extends StatefulWidget {
  const ChangePasswordScreen({super.key});
  @override
  State<ChangePasswordScreen> createState() => _ChangePasswordScreenState();
}

class _ChangePasswordScreenState extends State<ChangePasswordScreen> {
  final _svc = ParametresService();
  final _ancien = TextEditingController();
  final _nouveau = TextEditingController();
  final _confirm = TextEditingController();
  bool _loading = false;

  void _snack(String m, Color c) => ScaffoldMessenger.of(context)
      .showSnackBar(SnackBar(content: Text(m), backgroundColor: c));

  Future<void> _valider() async {
    final t = AppLocalizations.of(context);
    if (_ancien.text.isEmpty) return _snack(t.enterCurrentPassword, AppColors.danger);
    if (_nouveau.text.length < 8) return _snack(t.minPassword8, AppColors.danger);
    if (_nouveau.text != _confirm.text) return _snack(t.confirmationMismatch, AppColors.danger);
    setState(() => _loading = true);
    final err = await _svc.changePassword(_ancien.text, _nouveau.text);
    if (!mounted) return;
    setState(() => _loading = false);
    if (err == null) {
      _snack(t.passwordChanged, AppColors.success);
      Navigator.pop(context);
    } else {
      _snack(err, AppColors.danger);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    return Scaffold(
      backgroundColor: context.bg,
      appBar: AppBar(
        backgroundColor: context.bg, elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_ios_new_rounded, color: context.cText, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(t.changePassword,
            style: TextStyle(color: context.cText, fontSize: 17, fontWeight: FontWeight.w800)),
      ),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          _field(_ancien, t.currentPassword),
          _field(_nouveau, t.newPassword),
          _field(_confirm, t.confirmNewPassword),
          Text(t.passwordRulesHint,
              style: TextStyle(fontSize: 11, color: context.cTextSub)),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity, height: 52,
            child: ElevatedButton(
              onPressed: _loading ? null : _valider,
              style: ElevatedButton.styleFrom(backgroundColor: AppColors.blue,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))),
              child: _loading
                  ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                  : Text(t.save, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 15)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _field(TextEditingController c, String label) => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: TextField(
          controller: c, obscureText: true,
          style: TextStyle(color: context.cText),
          decoration: InputDecoration(labelText: label,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12))),
        ),
      );
}

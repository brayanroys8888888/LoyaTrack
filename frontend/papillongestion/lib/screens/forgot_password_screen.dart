import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import '../theme/app_theme.dart';
import '../services/auth_service.dart';

/// Réinitialisation du mot de passe par OTP SMS (3 étapes) :
/// 1) téléphone → 2) code reçu → 3) nouveau mot de passe.
class ForgotPasswordScreen extends StatefulWidget {
  const ForgotPasswordScreen({super.key});
  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen> {
  final _auth = AuthService();
  final _ident = TextEditingController();
  final _code = TextEditingController();
  final _newPwd = TextEditingController();
  int _etape = 1; // 1 = téléphone, 2 = code, 3 = nouveau mdp
  String? _resetToken;
  bool _loading = false;

  void _snack(String m, Color c) => ScaffoldMessenger.of(context)
      .showSnackBar(SnackBar(content: Text(m), backgroundColor: c));

  Future<void> _demanderCode() async {
    if (_ident.text.trim().isEmpty) return;
    setState(() => _loading = true);
    final dev = await _auth.passwordForgot(_ident.text.trim());
    if (!mounted) return;
    setState(() => _loading = false);
    if (dev != null) {
      if (dev.isNotEmpty) _code.text = dev; // pré-rempli en DEBUG
      setState(() => _etape = 2);
      _snack(AppLocalizations.of(context).codeSentBySms, AppColors.success);
    } else {
      _snack(AppLocalizations.of(context).networkError, AppColors.danger);
    }
  }

  Future<void> _verifierCode() async {
    if (_code.text.trim().length < 4) return;
    setState(() => _loading = true);
    final token = await _auth.passwordVerifyOtp(_ident.text.trim(), _code.text.trim());
    if (!mounted) return;
    setState(() => _loading = false);
    if (token != null) {
      setState(() { _resetToken = token; _etape = 3; });
    } else {
      _snack(AppLocalizations.of(context).codeInvalidOrExpired, AppColors.danger);
    }
  }

  Future<void> _reinitialiser() async {
    if (_newPwd.text.length < 8) {
      _snack(AppLocalizations.of(context).forgotPwdMin, AppColors.danger);
      return;
    }
    setState(() => _loading = true);
    final err = await _auth.passwordReset(_resetToken!, _newPwd.text);
    if (!mounted) return;
    setState(() => _loading = false);
    if (err == null) {
      _snack(AppLocalizations.of(context).passwordResetDone, AppColors.success);
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
        title: Text(t.forgotPasswordTitle, style: TextStyle(color: context.cText, fontSize: 17, fontWeight: FontWeight.w800)),
      ),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          Text(switch (_etape) {
            1 => t.forgotStep1,
            2 => t.forgotStep2,
            _ => t.forgotStep3,
          }, style: TextStyle(color: context.cTextSub, fontSize: 13)),
          const SizedBox(height: 20),
          if (_etape == 1) ...[
            _field(_ident, t.phone, TextInputType.phone),
            const SizedBox(height: 16),
            _bouton(t.sendCode, _demanderCode),
          ] else if (_etape == 2) ...[
            _field(_code, t.codeReceived, TextInputType.number),
            const SizedBox(height: 16),
            _bouton(t.verify, _verifierCode),
          ] else ...[
            _field(_newPwd, t.newPassword, TextInputType.visiblePassword, true),
            Text(t.passwordRulesHint,
                style: TextStyle(fontSize: 11, color: context.cTextSub)),
            const SizedBox(height: 16),
            _bouton(t.reset, _reinitialiser),
          ],
        ],
      ),
    );
  }

  Widget _field(TextEditingController c, String label, [TextInputType? type, bool obscure = false]) => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: TextField(
          controller: c, keyboardType: type, obscureText: obscure,
          style: TextStyle(color: context.cText),
          decoration: InputDecoration(labelText: label,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12))),
        ),
      );

  Widget _bouton(String label, VoidCallback onTap) => SizedBox(
        width: double.infinity, height: 52,
        child: ElevatedButton(
          onPressed: _loading ? null : onTap,
          style: ElevatedButton.styleFrom(backgroundColor: AppColors.blue,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))),
          child: _loading
              ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
              : Text(label, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 15)),
        ),
      );
}

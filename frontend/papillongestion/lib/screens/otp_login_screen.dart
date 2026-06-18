import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import '../theme/app_theme.dart';
import '../main_shell.dart';
import '../services/auth_service.dart';

/// Saisie du code OTP de connexion (2FA activée).
class OtpLoginScreen extends StatefulWidget {
  final int userId;
  final String? devCode; // pré-rempli en mode DEBUG pour faciliter les tests
  const OtpLoginScreen({required this.userId, this.devCode, super.key});
  @override
  State<OtpLoginScreen> createState() => _OtpLoginScreenState();
}

class _OtpLoginScreenState extends State<OtpLoginScreen> {
  late final TextEditingController _code = TextEditingController(text: widget.devCode ?? '');
  bool _loading = false;

  Future<void> _verifier() async {
    if (_code.text.trim().length < 4) return;
    setState(() => _loading = true);
    final ok = await AuthService().verifyLoginOtp(widget.userId, _code.text.trim());
    if (!mounted) return;
    setState(() => _loading = false);
    if (ok) {
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const MainShell()), (r) => false);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppLocalizations.of(context).codeInvalidOrExpired), backgroundColor: AppColors.danger),
      );
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
        title: Text(t.verification, style: TextStyle(color: context.cText, fontSize: 17, fontWeight: FontWeight.w800)),
      ),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          Icon(Icons.sms_outlined, size: 48, color: AppColors.blue),
          const SizedBox(height: 16),
          Text(t.otpEnterCode,
              style: TextStyle(color: context.cTextSub, fontSize: 14)),
          const SizedBox(height: 24),
          TextField(
            controller: _code,
            keyboardType: TextInputType.number,
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 24, letterSpacing: 8, fontWeight: FontWeight.w700, color: context.cText),
            decoration: InputDecoration(
              hintText: '••••••',
              counterText: '',
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
            ),
            maxLength: 6,
          ),
          const SizedBox(height: 24),
          SizedBox(
            height: 52,
            child: ElevatedButton(
              onPressed: _loading ? null : _verifier,
              style: ElevatedButton.styleFrom(backgroundColor: AppColors.blue,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))),
              child: _loading
                  ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                  : Text(t.validate, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 15)),
            ),
          ),
        ],
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../theme/app_theme.dart';
import '../widgets/shared_widgets.dart';
import 'login_screen.dart';

/// Écran d'accueil affiché UNE SEULE FOIS, au tout premier lancement de l'app
/// (avant toute connexion). L'utilisateur choisit de se connecter ou de créer
/// un compte. Le drapeau `seen_welcome` est posé dès qu'il quitte cet écran.
class WelcomeScreen extends StatelessWidget {
  const WelcomeScreen({super.key});

  static const _prefKey = 'seen_welcome';

  static Future<bool> dejaVu() async {
    final p = await SharedPreferences.getInstance();
    return p.getBool(_prefKey) ?? false;
  }

  Future<void> _continuer(BuildContext context, {required bool register}) async {
    final p = await SharedPreferences.getInstance();
    await p.setBool(_prefKey, true);
    if (!context.mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) =>
            register ? const RegisterScreen() : const LoginScreen(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(gradient: kGradient),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(28, 24, 28, 28),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Spacer(flex: 3),
                // ── Logo + nom ───────────────────────────────────────
                Center(
                  child: Container(
                    width: 104,
                    height: 104,
                    padding: const EdgeInsets.all(18),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(28),
                    ),
                    child: Image.asset('assets/images/logo/loyatrack_logo.png',
                        fit: BoxFit.contain),
                  ),
                ),
                const SizedBox(height: 24),
                const Center(
                  child: Text('LoyaTrack',
                      style: TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 32,
                          color: Colors.white,
                          letterSpacing: -0.5)),
                ),
                const SizedBox(height: 12),
                Text(t.welcomeHeadline,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                        fontSize: 15,
                        height: 1.5,
                        color: Colors.white70)),
                const Spacer(flex: 4),
                // ── Actions ─────────────────────────────────────────
                SizedBox(
                  height: 54,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.white,
                      foregroundColor: AppColors.blue,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(15)),
                    ),
                    onPressed: () => _continuer(context, register: true),
                    child: Text(t.createAccount,
                        style: const TextStyle(
                            fontWeight: FontWeight.w700, fontSize: 16)),
                  ),
                ),
                const SizedBox(height: 14),
                SizedBox(
                  height: 54,
                  child: OutlinedButton(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.white,
                      side: BorderSide(color: Colors.white.withOpacity(0.6), width: 1.5),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(15)),
                    ),
                    onPressed: () => _continuer(context, register: false),
                    child: Text(t.signIn,
                        style: const TextStyle(
                            fontWeight: FontWeight.w700, fontSize: 16)),
                  ),
                ),
                const SizedBox(height: 8),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

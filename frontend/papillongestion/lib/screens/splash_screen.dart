import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import '../widgets/shared_widgets.dart';
import 'login_screen.dart';
import 'welcome_screen.dart';
import '../main_shell.dart';
import '../services/auth_service.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});
  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _fade, _scale;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 1200));
    _fade  = CurvedAnimation(parent: _ctrl, curve: Curves.easeIn);
    _scale = Tween<double>(begin: 0.7, end: 1.0)
        .animate(CurvedAnimation(parent: _ctrl, curve: Curves.elasticOut));
    _ctrl.forward();
    _checkSession();
  }

  void _checkSession() async {
    // Restaure la session ET respecte un temps de splash minimal, en PARALLÈLE
    // (au lieu de cumuler réseau + délai) → ouverture nettement plus rapide.
    final results = await Future.wait([
      AuthService().restaurerSession(),
      WelcomeScreen.dejaVu(),
      Future.delayed(const Duration(milliseconds: 1200)),
    ]);
    final bool loggedIn = results[0] as bool;
    final bool welcomeVu = results[1] as bool;

    if (!mounted) return;

    // Connecté → app. Sinon : 1er lancement → Welcome, après → Login.
    Widget destination;
    if (loggedIn) {
      destination = const MainShell();
    } else if (!welcomeVu) {
      destination = const WelcomeScreen();
    } else {
      destination = const LoginScreen();
    }

    Navigator.of(context).pushReplacement(PageRouteBuilder(
      pageBuilder: (_, a, __) => destination,
      transitionsBuilder: (_, a, __, child) =>
          FadeTransition(opacity: a, child: child),
      transitionDuration: const Duration(milliseconds: 500),
    ));
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: const BoxDecoration(gradient: kGradient),
        child: SafeArea(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Spacer(flex: 2),
              FadeTransition(
                opacity: _fade,
                child: ScaleTransition(
                  scale: _scale,
                  child: Column(children: [
                    // Logo blanc
                    Container(
                      width: 110,
                      height: 110,
                      decoration: BoxDecoration(
                          // image: DecorationImage(image: AssetImage("assets/images/logo/logoLoya.png"), fit: BoxFit.cover, scale: 1.0),
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(30),
                          boxShadow: [
                            BoxShadow(
                                color: Colors.black.withOpacity(0.18),
                                blurRadius: 24,
                                offset: const Offset(0, 8))
                          ]),
                      padding: const EdgeInsets.all(14),

                      child: Image.asset("assets/images/logo/loyatrack_logo.png", fit: BoxFit.contain,),
                    ),
                    const SizedBox(height: 28),
                    const Text('LoyaTrack',
                        style: TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 30,
                            color: Colors.white,
                            letterSpacing: -0.5)),
                    const SizedBox(height: 10),
                    Text(AppLocalizations.of(context).splashTagline,
                        style: const TextStyle(
                            fontSize: 14,
                            color: Colors.white70,
                            letterSpacing: 0.5)),
                  ]),
                ),
              ),
              const Spacer(flex: 2),
              Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                _dot(true),
                const SizedBox(width: 8),
                _dot(false),
                const SizedBox(width: 8),
                _dot(false),
              ]),
              const SizedBox(height: 24),
              SizedBox(
                  width: 26,
                  height: 26,
                  child: CircularProgressIndicator(
                      strokeWidth: 2.5,
                      color: Colors.white.withOpacity(0.6))),
              const SizedBox(height: 48),
            ],
          ),
        ),
      ),
    );
  }

  Widget _dot(bool active) => AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        width: active ? 24 : 8,
        height: 8,
        decoration: BoxDecoration(
            color: active ? Colors.white : Colors.white38,
            borderRadius: BorderRadius.circular(4)),
      );
}

import 'package:flutter/material.dart';
import 'screens/dashboard_screen.dart';
import 'screens/locataires_screen.dart';
import 'screens/historique_screen.dart';
import 'screens/reglages_screen.dart';
import 'widgets/shared_widgets.dart';
import 'core/abonnement_provider.dart' show abonnementProvider;

class MainShell extends StatefulWidget {
  const MainShell({super.key});
  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  int _index = 0;

  late final List<Widget> _screens;

  @override
  void initState() {
    super.initState();
    // Charge le statut d'abonnement dès l'entrée dans l'app (essai/Pro/expiré).
    abonnementProvider.rafraichir();
    _screens = [
      DashboardScreen(onNavigate: (i) => setState(() => _index = i)),
      const LocatairesScreen(),
      const HistoriqueScreen(),
      const ReglagesScreen(),
    ];
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBody: true,
      body: IndexedStack(
        index: _index,
        children: _screens,
      ),
      bottomNavigationBar: AppBottomNav(
        currentIndex: _index,
        onTap: (i) => setState(() => _index = i),
      ),
    );
  }
}

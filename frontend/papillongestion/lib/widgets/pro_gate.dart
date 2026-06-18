import 'package:flutter/material.dart';

import '../core/abonnement_provider.dart';
import '../screens/paywall_screen.dart';
import '../theme/app_theme.dart';

/// Petit badge « PRO » à poser à côté d'une fonction réservée au plan Pro.
class ProBadge extends StatelessWidget {
  const ProBadge({super.key});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: AppColors.warning,
          borderRadius: BorderRadius.circular(6),
        ),
        child: const Text('PRO',
            style: TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.w800, letterSpacing: 0.5)),
      );
}

/// Affiche un badge PRO uniquement si le bailleur n'a pas le droit `feature`.
class ProBadgeIfLocked extends StatelessWidget {
  final String feature;
  const ProBadgeIfLocked(this.feature, {super.key});

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: abonnementProvider,
        builder: (context, _) =>
            abonnementProvider.aDroit(feature) ? const SizedBox.shrink() : const ProBadge(),
      );
}

/// Vérifie l'accès à `feature` AVANT d'exécuter une action Pro.
/// Renvoie true si autorisé ; sinon affiche l'upsell et renvoie false.
bool exigerFonction(BuildContext context, String feature) {
  if (abonnementProvider.aDroit(feature)) return true;
  showProUpsell(context, feature: feature);
  return false;
}

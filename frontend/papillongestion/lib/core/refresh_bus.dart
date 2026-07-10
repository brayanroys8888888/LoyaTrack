import 'package:flutter/foundation.dart';

/// Signal global de rafraîchissement des données.
///
/// Incrémenté (`bump()`) après toute mutation en base — ajout, modification ou
/// suppression d'un locataire ou d'un paiement, dans n'importe quel écran. Les
/// écrans principaux (tableau de bord, locataires, historique) l'écoutent et se
/// réactualisent, de sorte qu'en revenant/naviguant vers un écran ses données
/// sont toujours à jour, sans « tirer pour rafraîchir » manuel.
class RefreshBus extends ChangeNotifier {
  int _version = 0;
  int get version => _version;

  void bump() {
    _version++;
    notifyListeners();
  }
}

/// Instance globale unique.
final refreshBus = RefreshBus();

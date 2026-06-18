import 'package:flutter/foundation.dart';
import '../models/models.dart';
import '../services/abonnement_service.dart';

/// Instance globale unique : utilisée directement par l'UI (ListenableBuilder)
/// et par les hooks de l'ApiClient, sans dépendre du lookup InheritedWidget.
final abonnementProvider = AbonnementProvider();

/// Détient le statut d'abonnement courant et le diffuse à l'UI
/// (bannière d'essai, verrous Pro). Rafraîchi au démarrage et après paiement.
class AbonnementProvider extends ChangeNotifier {
  final AbonnementService _service = AbonnementService();

  Abonnement? _ab;
  bool _charge = false;

  bool get charge => _charge;
  Abonnement get statut => _ab ?? Abonnement.inconnu;

  bool aDroit(String feature) => statut.aDroit(feature);
  bool get estPro => statut.estPro;
  bool get estEssai => statut.estEssai;

  Future<void> rafraichir() async {
    final s = await _service.getStatut();
    if (s != null) {
      _ab = s;
    }
    _charge = true;
    notifyListeners();
  }
}

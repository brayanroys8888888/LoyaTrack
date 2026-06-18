import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/parametres_service.dart';

/// Gère la langue de l'interface (FR/EN).
/// - Persistée localement (SharedPreferences) pour être appliquée dès le démarrage.
/// - Synchronisée avec `ConfigBailleur.langue_interface` côté backend.
class LocaleProvider extends ChangeNotifier {
  static const _key = 'app_language';
  static const supported = ['fr', 'en'];

  Locale _locale = const Locale('fr');
  Locale get locale => _locale;
  String get code => _locale.languageCode;

  LocaleProvider() {
    _load();
  }

  Future<void> _load() async {
    final p = await SharedPreferences.getInstance();
    final saved = p.getString(_key);
    if (saved != null && supported.contains(saved)) {
      _locale = Locale(saved);
      notifyListeners();
    }
  }

  Future<void> _persist(String c) async {
    final p = await SharedPreferences.getInstance();
    await p.setString(_key, c);
  }

  /// Applique une langue venant du backend (au login / restauration de session),
  /// sans la renvoyer au serveur.
  void setFromBackend(String? c) {
    if (c == null || !supported.contains(c) || c == code) return;
    _locale = Locale(c);
    _persist(c);
    notifyListeners();
  }

  /// Changement déclenché par l'utilisateur : persiste + notifie + push backend.
  Future<void> setLocale(String c) async {
    if (!supported.contains(c) || c == code) return;
    _locale = Locale(c);
    await _persist(c);
    notifyListeners();
    // Best-effort : on n'attend pas / on ignore les erreurs réseau.
    ParametresService().updateParametres({'langue_interface': c});
  }
}

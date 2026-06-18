import 'package:dio/dio.dart';
import '../core/api_client.dart';

/// Préférences du bailleur (écran Paramètres) : régional/affichage,
/// notifications & rappels, défauts financiers. Endpoint /parametres/.
class ParametresService {
  final Dio _dio = ApiClient().dio;

  /// Récupère les paramètres du bailleur connecté (créés à la volée côté backend).
  Future<Map<String, dynamic>?> getParametres() async {
    try {
      final r = await _dio.get('parametres/');
      return r.statusCode == 200 ? r.data as Map<String, dynamic> : null;
    } catch (e) {
      print('Erreur getParametres: $e');
      return null;
    }
  }

  /// Met à jour partiellement les paramètres. Renvoie la config à jour ou null.
  Future<Map<String, dynamic>?> updateParametres(Map<String, dynamic> changes) async {
    try {
      final r = await _dio.patch('parametres/', data: changes);
      return r.statusCode == 200 ? r.data as Map<String, dynamic> : null;
    } catch (e) {
      print('Erreur updateParametres: $e');
      return null;
    }
  }

  /// Change le mot de passe (utilisateur connecté).
  /// Renvoie `null` en cas de succès, sinon le message d'erreur.
  Future<String?> changePassword(String ancien, String nouveau) async {
    try {
      final r = await _dio.post('auth/change-password/', data: {
        'ancien_mot_de_passe': ancien,
        'nouveau_mot_de_passe': nouveau,
      });
      return r.statusCode == 200 ? null : 'Échec du changement de mot de passe';
    } on DioException catch (e) {
      final d = e.response?.data;
      if (d is Map) {
        final v = d['ancien_mot_de_passe'] ?? d['nouveau_mot_de_passe'] ?? d['detail'];
        if (v != null) return v is List ? v.join('\n') : v.toString();
      }
      return 'Échec du changement de mot de passe';
    } catch (e) {
      return 'Erreur réseau';
    }
  }
}

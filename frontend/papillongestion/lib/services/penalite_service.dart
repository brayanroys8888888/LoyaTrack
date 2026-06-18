import 'package:dio/dio.dart';
import '../core/api_client.dart';

/// Accès aux pénalités et à leur configuration par locataire (module 1.1).
class PenaliteService {
  final Dio _dio = ApiClient().dio;

  /// Liste les pénalités, éventuellement filtrées par locataire.
  Future<List<dynamic>> getPenalites({String? locataireId}) async {
    try {
      final response = await _dio.get('penalites/', queryParameters: {
        if (locataireId != null) 'locataire': locataireId,
      });
      if (response.statusCode == 200) {
        final data = response.data;
        return data is Map && data['results'] != null ? data['results'] : data;
      }
      return [];
    } catch (e) {
      print('Erreur getPenalites: $e');
      return [];
    }
  }

  /// Synthèse des pénalités pour le tableau de bord.
  Future<Map<String, dynamic>?> getResume() async {
    try {
      final response = await _dio.get('penalites/resume/');
      return response.statusCode == 200 ? response.data as Map<String, dynamic> : null;
    } catch (e) {
      print('Erreur getResume: $e');
      return null;
    }
  }

  /// Accorde une remise (totale si [montant] est nul) sur une pénalité. Motif obligatoire.
  Future<bool> remise(String penaliteId, {required String motif, double? montant}) async {
    try {
      final response = await _dio.post('penalites/$penaliteId/remise/', data: {
        'motif': motif,
        if (montant != null) 'montant': montant,
      });
      return response.statusCode == 200;
    } catch (e) {
      print('Erreur remise: $e');
      return false;
    }
  }

  /// Récupère la configuration de pénalité d'un locataire (ou null si absente).
  Future<Map<String, dynamic>?> getConfig(String locataireId) async {
    try {
      final response = await _dio.get('config-penalites/', queryParameters: {'locataire': locataireId});
      if (response.statusCode == 200) {
        final data = response.data;
        final list = data is Map && data['results'] != null ? data['results'] : data;
        return (list is List && list.isNotEmpty) ? list.first as Map<String, dynamic> : null;
      }
      return null;
    } catch (e) {
      print('Erreur getConfig: $e');
      return null;
    }
  }

  /// Crée ou met à jour la configuration de pénalité d'un locataire.
  Future<bool> saveConfig({
    required String locataireId,
    int? id,
    required bool actif,
    required int delaiGrace,
    required String typePenalite, // 'fixe' | 'pourcentage'
    double? montantFixe,
    double? pourcentage,
  }) async {
    final payload = {
      'locataire': locataireId,
      'actif': actif,
      'delai_grace': delaiGrace,
      'type_penalite': typePenalite,
      if (montantFixe != null) 'montant_fixe': montantFixe,
      if (pourcentage != null) 'pourcentage': pourcentage,
    };
    try {
      final response = id == null
          ? await _dio.post('config-penalites/', data: payload)
          : await _dio.patch('config-penalites/$id/', data: payload);
      return response.statusCode == 200 || response.statusCode == 201;
    } catch (e) {
      print('Erreur saveConfig: $e');
      return false;
    }
  }
}

import 'package:dio/dio.dart';
import '../core/api_client.dart';
import '../models/bien.dart';

/// Accès aux propriétés et unités de logement (module 2.1 multi-biens).
class BienService {
  final Dio _dio = ApiClient().dio;

  Future<List<Propriete>> getProprietes() async {
    try {
      final response = await _dio.get('proprietes/');
      if (response.statusCode == 200) {
        final data = response.data is Map && response.data['results'] != null
            ? response.data['results']
            : response.data;
        return (data as List).map((j) => Propriete.fromJson(j)).toList();
      }
      return [];
    } catch (e) {
      print('Erreur getProprietes: $e');
      return [];
    }
  }

  Future<List<UniteLogement>> getUnites({int? proprieteId}) async {
    try {
      final response = await _dio.get('unites/', queryParameters: {
        if (proprieteId != null) 'propriete': proprieteId,
      });
      if (response.statusCode == 200) {
        final data = response.data is Map && response.data['results'] != null
            ? response.data['results']
            : response.data;
        return (data as List).map((j) => UniteLogement.fromJson(j)).toList();
      }
      return [];
    } catch (e) {
      print('Erreur getUnites: $e');
      return [];
    }
  }

  Future<Propriete?> createPropriete({
    required String titre,
    required String type,
    String adresse = '',
  }) async {
    try {
      final response = await _dio.post('proprietes/', data: {
        'titre': titre,
        'type': type,
        'adresse': adresse,
      });
      return response.statusCode == 201 ? Propriete.fromJson(response.data) : null;
    } catch (e) {
      print('Erreur createPropriete: $e');
      return null;
    }
  }

  Future<UniteLogement?> createUnite({
    required int proprieteId,
    required String numero,
    required double loyerStandard,
  }) async {
    try {
      final response = await _dio.post('unites/', data: {
        'propriete': proprieteId,
        'numero': numero,
        'loyer_standard': loyerStandard,
      });
      return response.statusCode == 201 ? UniteLogement.fromJson(response.data) : null;
    } catch (e) {
      print('Erreur createUnite: $e');
      return null;
    }
  }
}

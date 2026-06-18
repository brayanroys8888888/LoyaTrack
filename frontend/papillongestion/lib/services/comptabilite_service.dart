import 'package:dio/dio.dart';
import '../core/api_client.dart';

class ComptabiliteService {
  final Dio _dio = ApiClient().dio;

  Future<List<dynamic>> getDepenses({int? annee}) async {
    try {
      final r = await _dio.get('depenses/', queryParameters: {if (annee != null) 'annee': annee});
      if (r.statusCode == 200) {
        final d = r.data;
        return d is Map && d['results'] != null ? d['results'] : d;
      }
      return [];
    } catch (e) { print('Erreur getDepenses: $e'); return []; }
  }

  Future<bool> createDepense({
    required String libelle,
    required double montant,
    required DateTime date,
    required String categorie,
    int? bien,
  }) async {
    try {
      final r = await _dio.post('depenses/', data: {
        'libelle': libelle,
        'montant': montant,
        'date': date.toIso8601String().split('T').first,
        'categorie': categorie,
        if (bien != null) 'bien': bien,
      });
      return r.statusCode == 201;
    } catch (e) { print('Erreur createDepense: $e'); return false; }
  }

  Future<Map<String, dynamic>?> getReleve(int annee) async {
    try {
      final r = await _dio.get('depenses/releve/', queryParameters: {'annee': annee});
      return r.statusCode == 200 ? r.data as Map<String, dynamic> : null;
    } catch (e) { print('Erreur getReleve: $e'); return null; }
  }

  Future<List<int>?> exportReleve(int annee, {required bool pdf}) async {
    try {
      final r = await _dio.get(
        'depenses/${pdf ? 'export_pdf' : 'export_excel'}/',
        queryParameters: {'annee': annee},
        options: Options(responseType: ResponseType.bytes),
      );
      return r.statusCode == 200 ? r.data as List<int> : null;
    } catch (e) { print('Erreur exportReleve: $e'); return null; }
  }
}

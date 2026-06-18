import 'package:dio/dio.dart';
import '../core/api_client.dart';

/// Service des états des lieux + photos (module 3.1).
class EtatService {
  final Dio _dio = ApiClient().dio;

  Future<List<dynamic>> getEtats(String locataireId) async {
    try {
      final r = await _dio.get('etats-des-lieux/', queryParameters: {'locataire': locataireId});
      if (r.statusCode == 200) {
        final d = r.data;
        return d is Map && d['results'] != null ? d['results'] : d;
      }
      return [];
    } catch (e) { print('Erreur getEtats: $e'); return []; }
  }

  Future<int?> createEtat({
    required String locataireId,
    required String type, // 'entree' | 'sortie'
    required DateTime date,
    String observations = '',
  }) async {
    try {
      final r = await _dio.post('etats-des-lieux/', data: {
        'locataire': locataireId,
        'type_etat': type,
        'date': date.toIso8601String().split('T').first,
        'observations': observations,
      });
      return r.statusCode == 201 ? r.data['id'] as int : null;
    } catch (e) { print('Erreur createEtat: $e'); return null; }
  }

  Future<bool> addPhoto({
    required int etatId,
    required String piece,
    required String description,
    required String photoPath,
  }) async {
    try {
      final form = FormData.fromMap({
        'etat': etatId,
        'piece': piece,
        'description': description,
        'photo': await MultipartFile.fromFile(photoPath),
      });
      final r = await _dio.post('photos-etat-des-lieux/', data: form);
      return r.statusCode == 201;
    } catch (e) { print('Erreur addPhoto: $e'); return false; }
  }

  Future<List<int>?> getRapportPdf(int etatId) async {
    try {
      final r = await _dio.get('etats-des-lieux/$etatId/rapport/',
          options: Options(responseType: ResponseType.bytes));
      return r.statusCode == 200 ? r.data as List<int> : null;
    } catch (e) { print('Erreur getRapportPdf: $e'); return null; }
  }
}

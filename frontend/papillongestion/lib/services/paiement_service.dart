import 'package:dio/dio.dart';
import '../models/models.dart';
import '../core/api_client.dart';

class PaiementService {
  final Dio _dio = ApiClient().dio;

  Future<List<Paiement>> getPaiements({String? locataireId}) async {
    try {
      final response = await _dio.get('paiements/', queryParameters: {
        if (locataireId != null) 'locataire': locataireId,
      });
      if (response.statusCode == 200) {
        List<dynamic> data;
        if (response.data is Map && response.data['results'] != null) {
          data = response.data['results'];
        } else {
          data = response.data as List<dynamic>;
        }
        return data.map((json) => Paiement.fromJson(json)).toList();
      }
      return [];
    } catch (e) {
      print('Erreur getPaiements: $e');
      return [];
    }
  }

  /// Télécharge la quittance de loyer (PDF) d'un paiement sous forme d'octets.
  Future<List<int>?> getQuittancePdf(String paiementId) async {
    try {
      final response = await _dio.get(
        'paiements/$paiementId/quittance/',
        options: Options(responseType: ResponseType.bytes),
      );
      return response.statusCode == 200 ? response.data as List<int> : null;
    } catch (e) {
      print('Erreur getQuittancePdf: $e');
      return null;
    }
  }

  /// Exporte la liste des paiements (filtrée) en PDF ou Excel (octets).
  /// [format] = 'pdf' | 'excel' ; [mode] = libellé FR du mode (optionnel).
  Future<List<int>?> exporterPaiements({required String format, String? mode}) async {
    try {
      final r = await _dio.get(
        'paiements/exporter/',
        queryParameters: {'fmt': format, if (mode != null) 'mode': mode},
        options: Options(responseType: ResponseType.bytes),
      );
      return r.statusCode == 200 ? r.data as List<int> : null;
    } catch (e) {
      print('Erreur exporterPaiements: $e');
      return null;
    }
  }

  Future<bool> createPaiement({
    required int locataireId,
    required double montant,
    required String modePaiement,
    required DateTime datePaiement,
    String? reference,
  }) async {
    try {
      final response = await _dio.post(
        'paiements/',
        data: {
          'locataire': locataireId,
          'montant': montant,
          'mode_paiement': modePaiement,
          'date_paiement': datePaiement.toIso8601String().split('T')[0],
          'reference': reference ?? '',
        },
      );
      return response.statusCode == 201;
    } catch (e) {
      print('Erreur createPaiement: $e');
      return false;
    }
  }
}

import 'package:dio/dio.dart';
import '../core/api_client.dart';
import '../models/annonce.dart';

/// Accès à la vitrine d'annonces (Palier 1). Toutes les routes sont scopées
/// bailleur côté serveur.
class AnnonceService {
  final Dio _dio = ApiClient().dio;

  List<dynamic> _liste(dynamic data) =>
      (data is Map && data['results'] != null) ? data['results'] : data;

  Future<List<Annonce>> getAnnonces({String? statut}) async {
    try {
      final r = await _dio.get('annonces/', queryParameters: {
        if (statut != null) 'statut': statut,
      });
      if (r.statusCode == 200) {
        return _liste(r.data).map((j) => Annonce.fromJson(j)).toList();
      }
      return [];
    } catch (e) {
      print('Erreur getAnnonces: $e');
      return [];
    }
  }

  Future<List<Ville>> getVilles() async {
    try {
      final r = await _dio.get('localisations/villes/');
      if (r.statusCode == 200) {
        return _liste(r.data).map((j) => Ville.fromJson(j)).toList();
      }
      return [];
    } catch (e) {
      print('Erreur getVilles: $e');
      return [];
    }
  }

  /// Crée un brouillon pré-rempli à partir d'une unité vacante.
  Future<Annonce?> depuisUnite(int uniteId) async {
    try {
      final r = await _dio.post('annonces/depuis-unite/', data: {'unite': uniteId});
      return r.statusCode == 201 ? Annonce.fromJson(r.data) : null;
    } catch (e) {
      print('Erreur depuisUnite: $e');
      return null;
    }
  }

  Future<Annonce?> createAnnonce(Map<String, dynamic> data) async {
    try {
      final r = await _dio.post('annonces/', data: data);
      return r.statusCode == 201 ? Annonce.fromJson(r.data) : null;
    } catch (e) {
      print('Erreur createAnnonce: $e');
      return null;
    }
  }

  Future<Annonce?> updateAnnonce(int id, Map<String, dynamic> data) async {
    try {
      final r = await _dio.patch('annonces/$id/', data: data);
      return r.statusCode == 200 ? Annonce.fromJson(r.data) : null;
    } catch (e) {
      print('Erreur updateAnnonce: $e');
      return null;
    }
  }

  Future<bool> deleteAnnonce(int id) async {
    try {
      final r = await _dio.delete('annonces/$id/');
      return r.statusCode == 204;
    } catch (e) {
      print('Erreur deleteAnnonce: $e');
      return false;
    }
  }

  /// Publie une annonce. Renvoie l'annonce publiée, ou la liste des manques
  /// (auto-checks) renvoyée par le backend en cas de refus (400).
  Future<ResultatPublication> publier(int id) async {
    try {
      final r = await _dio.post('annonces/$id/publier/');
      if (r.statusCode == 200) {
        return ResultatPublication(annonce: Annonce.fromJson(r.data));
      }
      return const ResultatPublication(erreurs: ['Échec de la publication.']);
    } on DioException catch (e) {
      final data = e.response?.data;
      if (data is Map && data['erreurs'] is List) {
        return ResultatPublication(
            erreurs: (data['erreurs'] as List).map((x) => x.toString()).toList());
      }
      return const ResultatPublication(erreurs: ['Échec de la publication.']);
    } catch (e) {
      print('Erreur publier: $e');
      return const ResultatPublication(erreurs: ['Échec de la publication.']);
    }
  }

  Future<Annonce?> renouveler(int id) async {
    try {
      final r = await _dio.post('annonces/$id/renouveler/');
      return r.statusCode == 200 ? Annonce.fromJson(r.data) : null;
    } catch (e) {
      print('Erreur renouveler: $e');
      return null;
    }
  }

  Future<Annonce?> depublier(int id, {bool pourvue = false}) async {
    try {
      final r = await _dio.post('annonces/$id/depublier/', data: {'pourvue': pourvue});
      return r.statusCode == 200 ? Annonce.fromJson(r.data) : null;
    } catch (e) {
      print('Erreur depublier: $e');
      return null;
    }
  }

  Future<PhotoAnnonce?> addPhoto(int id, String filePath) async {
    try {
      final form = FormData.fromMap({
        'image': await MultipartFile.fromFile(filePath),
      });
      final r = await _dio.post('annonces/$id/photos/', data: form);
      return r.statusCode == 201 ? PhotoAnnonce.fromJson(r.data) : null;
    } catch (e) {
      print('Erreur addPhoto: $e');
      return null;
    }
  }

  Future<bool> deletePhoto(int id, int photoId) async {
    try {
      final r = await _dio.delete('annonces/$id/photos/$photoId/');
      return r.statusCode == 204;
    } catch (e) {
      print('Erreur deletePhoto: $e');
      return false;
    }
  }

  // ── Messagerie (côté bailleur) ─────────────────────────────────────────────
  Future<List<Conversation>> getConversations() async {
    try {
      final r = await _dio.get('conversations/');
      if (r.statusCode == 200) {
        return _liste(r.data).map((j) => Conversation.fromJson(j)).toList();
      }
      return [];
    } catch (e) {
      print('Erreur getConversations: $e');
      return [];
    }
  }

  Future<Conversation?> getConversation(int id) async {
    try {
      final r = await _dio.get('conversations/$id/');
      return r.statusCode == 200 ? Conversation.fromJson(r.data) : null;
    } catch (e) {
      print('Erreur getConversation: $e');
      return null;
    }
  }

  Future<Conversation?> repondreConversation(int id, String corps) async {
    try {
      final r = await _dio.post('conversations/$id/repondre/', data: {'corps': corps});
      return r.statusCode == 200 ? Conversation.fromJson(r.data) : null;
    } catch (e) {
      print('Erreur repondreConversation: $e');
      return null;
    }
  }

  Future<bool> _actionConversation(int id, String action) async {
    try {
      final r = await _dio.post('conversations/$id/$action/');
      return r.statusCode == 200;
    } catch (e) {
      print('Erreur $action conversation: $e');
      return false;
    }
  }

  Future<bool> bloquerConversation(int id) => _actionConversation(id, 'bloquer');
  Future<bool> archiverConversation(int id) => _actionConversation(id, 'archiver');
}

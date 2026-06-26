import 'dart:convert';
import 'package:dio/dio.dart';
import '../core/api_client.dart';
import '../models/models.dart';

/// Levée quand le backend refuse de générer un document légal parce que des
/// informations obligatoires manquent (loi n°2014/023). [champs] = libellés
/// manquants ; [cible] = 'bailleur' | 'locataire' | 'les_deux'.
class DonneesIncompletesException implements Exception {
  final List<String> champs;
  final String cible;
  final String message;
  DonneesIncompletesException(this.champs, this.cible, this.message);
}

// Convertit l'enum Flutter vers la chaîne attendue par le backend Django
String _statutToBackend(StatutLocataire statut) {
  switch (statut) {
    case StatutLocataire.paye:         return 'Payé';
    case StatutLocataire.nonPaye:      return 'En retard';
    case StatutLocataire.enDiscussion: return 'En discussion';
    case StatutLocataire.enPenalite:   return 'En pénalité';
  }
}

class LocataireService {
  final Dio _dio = ApiClient().dio;

  Future<List<Locataire>> getLocataires() async {
    try {
      final response = await _dio.get('locataires/');
      if (response.statusCode == 200) {
        // Django REST Framework renvoie une réponse paginée :
        // {"count": N, "next": ..., "previous": ..., "results": [...]}
        // On extrait "results" si présent, sinon on traite comme une liste brute
        List<dynamic> data;
        if (response.data is Map && response.data['results'] != null) {
          data = response.data['results'];
        } else {
          data = response.data as List<dynamic>;
        }
        return data.map((json) => Locataire.fromJson(json)).toList();
      }
      return [];
    } catch (e) {
      print('Erreur getLocataires: $e');
      return [];
    }
  }

  Future<Locataire?> createLocataire({
    required String nom,
    required String prenom,
    required String telephone,
    required String logement,
    required double montantLoyer,
    required int jourEcheance,
    required StatutLocataire statut,
    required DateTime dateEntree,
    double? penaliteJournaliere,
    String? notes,
    bool modeTest = false,
    String? signatureBase64,
    String? profession,
    double? revenusMensuels,
    String? typePieceIdentite,
    String? numeroPieceIdentite,
    String languePreferee = 'fr',
    int? unite,
    String? adresseLogement,
    double? chargesMensuelles,
    int? dureeBailMois,
    String? frequencePaiement,
  }) async {
    try {
      final response = await _dio.post('locataires/', data: {
        'nom': nom,
        'prenom': prenom,
        'telephone': telephone,
        'logement': logement,
        if (unite != null) 'unite': unite,
        if (adresseLogement != null) 'adresse_logement': adresseLogement,
        if (chargesMensuelles != null) 'charges_mensuelles': chargesMensuelles,
        if (dureeBailMois != null) 'duree_bail_mois': dureeBailMois,
        if (frequencePaiement != null) 'frequence_paiement': frequencePaiement,
        'montant_loyer': montantLoyer,
        'jour_echeance': jourEcheance,
        'statut': _statutToBackend(statut),
        'date_entree': dateEntree.toIso8601String().split('T').first,
        if (penaliteJournaliere != null) 'penalite_journaliere': penaliteJournaliere,
        if (notes != null && notes.isNotEmpty) 'notes': notes,
        if (signatureBase64 != null) 'signature_base64': signatureBase64,
        if (profession != null && profession.isNotEmpty) 'profession': profession,
        if (revenusMensuels != null) 'revenus_mensuels': revenusMensuels,
        if (typePieceIdentite != null && typePieceIdentite.isNotEmpty) 'type_piece_identite': typePieceIdentite,
        if (numeroPieceIdentite != null && numeroPieceIdentite.isNotEmpty) 'numero_piece_identite': numeroPieceIdentite,
        'langue_preferee': languePreferee,
        'mode_test': modeTest,
      });
      if (response.statusCode == 201) {
        return Locataire.fromJson(response.data);
      }
      return null;
    } catch (e) {
      print('Erreur createLocataire: $e');
      return null;
    }
  }

  Future<bool> updateLocataire({
    required String id,
    required String nom,
    required String prenom,
    required String telephone,
    required String logement,
    required double montantLoyer,
    required int jourEcheance,
    required StatutLocataire statut,
    required DateTime dateEntree,
    double? penaliteJournaliere,
    String? notes,
    String? signatureBase64,
    String? languePreferee,
    int? unite,
    String? adresseLogement,
    double? chargesMensuelles,
    int? dureeBailMois,
    String? frequencePaiement,
    String? profession,
    double? revenusMensuels,
    String? typePieceIdentite,
    String? numeroPieceIdentite,
  }) async {
    try {
      final response = await _dio.patch('locataires/$id/', data: {
        'nom': nom,
        'prenom': prenom,
        'telephone': telephone,
        'logement': logement,
        if (unite != null) 'unite': unite,
        if (adresseLogement != null) 'adresse_logement': adresseLogement,
        if (chargesMensuelles != null) 'charges_mensuelles': chargesMensuelles,
        if (dureeBailMois != null) 'duree_bail_mois': dureeBailMois,
        if (frequencePaiement != null) 'frequence_paiement': frequencePaiement,
        'montant_loyer': montantLoyer,
        'jour_echeance': jourEcheance,
        'statut': _statutToBackend(statut),
        'date_entree': dateEntree.toIso8601String().split('T').first,
        if (penaliteJournaliere != null) 'penalite_journaliere': penaliteJournaliere,
        if (signatureBase64 != null) 'signature_base64': signatureBase64,
        if (languePreferee != null) 'langue_preferee': languePreferee,
        if (profession != null) 'profession': profession,
        if (revenusMensuels != null) 'revenus_mensuels': revenusMensuels,
        if (typePieceIdentite != null && typePieceIdentite.isNotEmpty) 'type_piece_identite': typePieceIdentite,
        if (numeroPieceIdentite != null) 'numero_piece_identite': numeroPieceIdentite,
        'notes': notes ?? '',
      });
      return response.statusCode == 200;
    } catch (e) {
      print('Erreur updateLocataire: $e');
      return false;
    }
  }

  Future<bool> deleteLocataire(String id) async {
    try {
      final response = await _dio.delete('locataires/$id/');
      return response.statusCode == 204;
    } catch (e) {
      print('Erreur deleteLocataire: $e');
      return false;
    }
  }

  /// Change uniquement le statut du locataire (action dédiée `/statut/`).
  /// Sert notamment à passer un locataire « En discussion » (gèle les pénalités).
  Future<bool> changerStatut(String id, StatutLocataire statut) async {
    try {
      final response = await _dio.patch('locataires/$id/statut/', data: {
        'statut': _statutToBackend(statut),
      });
      return response.statusCode == 200;
    } catch (e) {
      print('Erreur changerStatut: $e');
      return false;
    }
  }

  Future<Rappel?> envoyerRappel(String locataireId, {String typeRappel = 'SMS'}) async {
    try {
      final response = await _dio.post('locataires/$locataireId/rappeler/', data: {
        'type_rappel': typeRappel,
      });
      if (response.statusCode == 201) {
        return Rappel.fromJson(response.data);
      }
      return null;
    } catch (e) {
      print('Erreur envoyerRappel: $e');
      return null;
    }
  }

  Future<List<Rappel>> getRappels(String locataireId) async {
    try {
      final response = await _dio.get('locataires/$locataireId/rappels/');
      if (response.statusCode == 200) {
        final List<dynamic> data = response.data is Map ? response.data['results'] ?? response.data : response.data;
        return data.map((json) => Rappel.fromJson(json)).toList();
      }
      return [];
    } catch (e) {
      print('Erreur getRappels: $e');
      return [];
    }
  }

  Future<bool> triggerAutomations() async {
    try {
      final response = await _dio.post('locataires/trigger_automations/');
      return response.statusCode == 200;
    } catch (e) {
      print('Erreur triggerAutomations: $e');
      return false;
    }
  }

  /// Upload de la pièce d'identité (PATCH multipart) — module 2.3.
  Future<bool> uploadPieceIdentite(String id, String filePath) async {
    try {
      final form = FormData.fromMap({
        'piece_identite': await MultipartFile.fromFile(filePath),
      });
      final r = await _dio.patch('locataires/$id/', data: form);
      return r.statusCode == 200;
    } catch (e) { print('Erreur uploadPieceIdentite: $e'); return false; }
  }

  /// Ajoute une pièce d'identité (recto/verso/PDF) — plusieurs par locataire.
  /// Renvoie l'entrée créée ({id, fichier, libelle}) ou null.
  Future<Map<String, dynamic>?> ajouterPieceIdentite(String id, String filePath,
      {String libelle = ''}) async {
    try {
      final form = FormData.fromMap({
        'fichier': await MultipartFile.fromFile(filePath),
        if (libelle.isNotEmpty) 'libelle': libelle,
      });
      final r = await _dio.post('locataires/$id/ajouter_piece/', data: form);
      return r.statusCode == 201 ? r.data as Map<String, dynamic> : null;
    } catch (e) {
      print('Erreur ajouterPieceIdentite: $e');
      return null;
    }
  }

  /// Supprime une pièce d'identité jointe.
  Future<bool> supprimerPieceIdentite(String locataireId, dynamic pieceId) async {
    try {
      final r = await _dio.delete('locataires/$locataireId/pieces/$pieceId/');
      return r.statusCode == 204;
    } catch (e) {
      print('Erreur supprimerPieceIdentite: $e');
      return false;
    }
  }

  /// Import en masse depuis un fichier CSV/Excel (POST multipart) — module 2.4.
  Future<Map<String, dynamic>?> importLocataires(String filePath, String fileName) async {
    try {
      final form = FormData.fromMap({
        'fichier': await MultipartFile.fromFile(filePath, filename: fileName),
      });
      final r = await _dio.post('locataires/importer/', data: form);
      return r.statusCode == 200 ? r.data as Map<String, dynamic> : null;
    } catch (e) { print('Erreur importLocataires: $e'); return null; }
  }

  /// Télécharge le modèle CSV d'import.
  Future<List<int>?> getModeleImport() async {
    try {
      final r = await _dio.get('locataires/modele_import/',
          options: Options(responseType: ResponseType.bytes));
      return r.statusCode == 200 ? r.data as List<int> : null;
    } catch (e) { print('Erreur getModeleImport: $e'); return null; }
  }

  /// Génère (ou régénère) le lien du portail locataire et l'envoie par SMS (3.5).
  Future<String?> genererLienPortail(String locataireId, {bool envoyerSms = false}) async {
    try {
      final r = await _dio.post('portail/generer/', data: {
        'locataire': locataireId,
        'envoyer_sms': envoyerSms,
      });
      return r.statusCode == 200 ? r.data['lien'] as String? : null;
    } catch (e) { print('Erreur genererLienPortail: $e'); return null; }
  }

  // ----- Gestion (caution, augmentation, résiliation) -----
  Future<bool> augmenterLoyer(String id, {required double montant, required DateTime dateDebut, String motif = ''}) async {
    try {
      final r = await _dio.post('locataires/$id/augmenter_loyer/', data: {
        'montant': montant,
        'date_debut': dateDebut.toIso8601String().split('T').first,
        'motif': motif,
      });
      return r.statusCode == 201;
    } catch (e) { print('Erreur augmenterLoyer: $e'); return false; }
  }

  Future<bool> verserCaution(String id, {required double montant, required DateTime date}) async {
    try {
      final r = await _dio.post('locataires/$id/verser_caution/', data: {
        'montant': montant,
        'date': date.toIso8601String().split('T').first,
      });
      return r.statusCode == 200;
    } catch (e) { print('Erreur verserCaution: $e'); return false; }
  }

  Future<bool> restituerCaution(String id, {required double montant, required DateTime date, String motif = ''}) async {
    try {
      final r = await _dio.post('locataires/$id/restituer_caution/', data: {
        'montant': montant,
        'date': date.toIso8601String().split('T').first,
        'motif': motif,
      });
      return r.statusCode == 200;
    } catch (e) { print('Erreur restituerCaution: $e'); return false; }
  }

  Future<bool> resilier(String id, {required DateTime dateSortie, String motif = ''}) async {
    try {
      final r = await _dio.post('locataires/$id/resilier/', data: {
        'date_sortie': dateSortie.toIso8601String().split('T').first,
        'motif': motif,
      });
      return r.statusCode == 200;
    } catch (e) { print('Erreur resilier: $e'); return false; }
  }

  /// Télécharge le contrat de bail (PDF) du locataire sous forme d'octets.
  /// Lève [DonneesIncompletesException] si des mentions légales obligatoires
  /// manquent (HTTP 422) — l'appelant affiche la liste et redirige.
  Future<List<int>?> getContratPdf(String locataireId) async {
    try {
      final response = await _dio.get(
        'locataires/$locataireId/contrat/',
        options: Options(
          responseType: ResponseType.bytes,
          // 422 = données incomplètes : on le traite ici sans le laisser
          // remonter comme erreur (403/401 continuent de passer par les hooks).
          validateStatus: (s) => s == 200 || s == 422,
        ),
      );
      if (response.statusCode == 200) return response.data as List<int>;
      if (response.statusCode == 422) {
        final body = _jsonFromBytes(response.data);
        if (body != null && body['code'] == 'donnees_incompletes') {
          throw DonneesIncompletesException(
            ((body['champs'] as List?) ?? const [])
                .map((e) => e.toString())
                .toList(),
            body['cible']?.toString() ?? 'locataire',
            body['message']?.toString() ?? '',
          );
        }
      }
      return null;
    } on DonneesIncompletesException {
      rethrow;
    } catch (e) {
      print('Erreur getContratPdf: $e');
      return null;
    }
  }

  /// Décode un corps de réponse renvoyé en octets (responseType.bytes) en JSON.
  Map<String, dynamic>? _jsonFromBytes(dynamic data) {
    try {
      if (data is List<int>) {
        return jsonDecode(utf8.decode(data)) as Map<String, dynamic>;
      }
      if (data is String) return jsonDecode(data) as Map<String, dynamic>;
      if (data is Map) return Map<String, dynamic>.from(data);
    } catch (_) {}
    return null;
  }

  Future<Map<String, dynamic>?> demarrerTest(String locataireId) async {
    try {
      final response = await _dio.post('locataires/$locataireId/demarrer_test/');
      if (response.statusCode == 200) {
        return response.data as Map<String, dynamic>;
      }
      return null;
    } catch (e) {
      print('Erreur demarrerTest: $e');
      return null;
    }
  }
}

import 'package:dio/dio.dart';
import '../core/api_client.dart';
import '../models/models.dart';

/// Plan du catalogue (`GET /abonnement/plans/`).
class PlanAbonnement {
  final String cle, nom;
  final int mensuel, annuel;
  final int? maxBiens;
  final List<String> features;

  const PlanAbonnement({
    required this.cle, required this.nom, required this.mensuel,
    required this.annuel, required this.maxBiens, required this.features,
  });

  factory PlanAbonnement.fromJson(Map<String, dynamic> j) => PlanAbonnement(
        cle: j['cle'], nom: j['nom'],
        mensuel: j['mensuel'] ?? 0, annuel: j['annuel'] ?? 0,
        maxBiens: j['max_biens'],
        features: List<String>.from(j['features'] ?? const []),
      );
}

class AbonnementService {
  final Dio _dio = ApiClient().dio;

  /// Statut courant. Renvoie null en cas d'échec réseau (l'appelant décide).
  Future<Abonnement?> getStatut() async {
    try {
      final r = await _dio.get('abonnement/');
      if (r.statusCode == 200) return Abonnement.fromJson(r.data);
      return null;
    } catch (e) {
      print('Erreur getStatut abonnement: $e');
      return null;
    }
  }

  /// Demande un magic-link (usage unique, ≤10 min) vers l'espace web d'abonnement.
  /// Renvoie null en cas d'échec (l'appelant utilise alors l'URL statique).
  Future<String?> getLienWeb() async {
    try {
      final r = await _dio.post('abonnement/lien-web/');
      if (r.statusCode == 200) return r.data['url'] as String?;
      return null;
    } catch (e) {
      print('Erreur getLienWeb: $e');
      return null;
    }
  }

  Future<List<PlanAbonnement>> getPlans() async {
    try {
      final r = await _dio.get('abonnement/plans/');
      if (r.statusCode == 200) {
        final List data = r.data['plans'] ?? [];
        return data.map((e) => PlanAbonnement.fromJson(e)).toList();
      }
      return [];
    } catch (e) {
      print('Erreur getPlans abonnement: $e');
      return [];
    }
  }
}

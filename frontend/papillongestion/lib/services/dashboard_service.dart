import 'package:dio/dio.dart';
import '../core/api_client.dart';

/// Un locataire à encaisser ce mois (ligne actionnable du cockpit).
class LocataireAEncaisser {
  final int locataireId;
  final String nom;
  final String logement;
  final String telephone;
  final int montantDu;
  final int joursRetard;
  final bool partiel;

  const LocataireAEncaisser({
    required this.locataireId,
    required this.nom,
    required this.logement,
    required this.telephone,
    required this.montantDu,
    required this.joursRetard,
    required this.partiel,
  });

  factory LocataireAEncaisser.fromJson(Map<String, dynamic> json) => LocataireAEncaisser(
        locataireId: json['locataire_id'] ?? 0,
        nom: json['nom']?.toString() ?? '',
        logement: json['logement']?.toString() ?? '',
        telephone: json['telephone']?.toString() ?? '',
        montantDu: json['montant_du'] ?? 0,
        joursRetard: json['jours_retard'] ?? 0,
        partiel: json['partiel'] == true,
      );
}

class DashboardStats {
  final int totalLocataires;
  final int loyersPayes;
  final int enPenalite;
  final int enDiscussion;
  final double revenusEncaisses;
  final double revenusAttendus;
  final double penalitesDues;
  final int nombreBiens;
  final int totalUnites;
  final int unitesOccupees;
  final int unitesVacantes;
  final double tauxOccupation;
  final List<String> alertes;

  // ── Cockpit d'encaissement (mois courant) ──
  final int attenduMois;
  final int encaisseMois;
  final int resteAEncaisser;
  final double tauxRecouvrement;
  final int aJour;
  final int enRetard;
  final int partiel;
  final int enAttente;
  final List<LocataireAEncaisser> aEncaisser;

  const DashboardStats({
    required this.totalLocataires,
    required this.loyersPayes,
    required this.enPenalite,
    required this.enDiscussion,
    required this.revenusEncaisses,
    required this.revenusAttendus,
    required this.penalitesDues,
    this.nombreBiens = 0,
    this.totalUnites = 0,
    this.unitesOccupees = 0,
    this.unitesVacantes = 0,
    this.tauxOccupation = 0,
    required this.alertes,
    this.attenduMois = 0,
    this.encaisseMois = 0,
    this.resteAEncaisser = 0,
    this.tauxRecouvrement = 0,
    this.aJour = 0,
    this.enRetard = 0,
    this.partiel = 0,
    this.enAttente = 0,
    this.aEncaisser = const [],
  });

  factory DashboardStats.fromJson(Map<String, dynamic> json) {
    final rep = (json['repartition'] as Map?) ?? const {};
    return DashboardStats(
      totalLocataires: json['total_locataires'] ?? 0,
      loyersPayes: json['loyers_payes'] ?? 0,
      enPenalite: json['en_penalite'] ?? 0,
      enDiscussion: json['en_discussion'] ?? 0,
      revenusEncaisses: double.tryParse(json['revenus_encaisses']?.toString() ?? '0') ?? 0,
      revenusAttendus: double.tryParse(json['revenus_attendus']?.toString() ?? '0') ?? 0,
      penalitesDues: double.tryParse(json['penalites_dues']?.toString() ?? '0') ?? 0,
      nombreBiens: json['nombre_biens'] ?? 0,
      totalUnites: json['total_unites'] ?? 0,
      unitesOccupees: json['unites_occupees'] ?? 0,
      unitesVacantes: json['unites_vacantes'] ?? 0,
      tauxOccupation: double.tryParse(json['taux_occupation']?.toString() ?? '0') ?? 0,
      alertes: List<String>.from(json['alertes'] ?? []),
      attenduMois: json['attendu_mois'] ?? 0,
      encaisseMois: json['encaisse_mois'] ?? 0,
      resteAEncaisser: json['reste_a_encaisser'] ?? 0,
      tauxRecouvrement: double.tryParse(json['taux_recouvrement']?.toString() ?? '0') ?? 0,
      aJour: rep['a_jour'] ?? 0,
      enRetard: rep['en_retard'] ?? 0,
      partiel: rep['partiel'] ?? 0,
      enAttente: rep['en_attente'] ?? 0,
      aEncaisser: ((json['a_encaisser'] as List?) ?? const [])
          .map((e) => LocataireAEncaisser.fromJson(Map<String, dynamic>.from(e)))
          .toList(),
    );
  }

  int get impayes => totalLocataires - loyersPayes;
}

class DashboardService {
  final Dio _dio = ApiClient().dio;

  Future<DashboardStats?> getStats() async {
    try {
      final response = await _dio.get('dashboard/');
      if (response.statusCode == 200) {
        return DashboardStats.fromJson(response.data);
      }
      return null;
    } catch (e) {
      print('Erreur getStats: $e');
      return null;
    }
  }
}

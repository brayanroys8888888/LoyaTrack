import 'package:dio/dio.dart';
import '../core/api_client.dart';

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
  });

  factory DashboardStats.fromJson(Map<String, dynamic> json) {
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

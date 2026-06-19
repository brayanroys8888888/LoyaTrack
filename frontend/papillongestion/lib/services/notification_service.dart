import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../core/api_config.dart';

class NotificationService {
  static final String baseUrl = ApiConfig.apiRoot;
  static const _storage = FlutterSecureStorage();

  static Future<String?> _getToken() async {
    return await _storage.read(key: 'access_token');
  }

  static Future<List<dynamic>> getNotifications() async {
    final token = await _getToken();
    if (token == null) return [];

    final response = await http.get(
      Uri.parse('$baseUrl/notifications/'),
      headers: {
        'Authorization': 'Bearer $token',
      },
    );

    if (response.statusCode == 200) {
      final decoded = jsonDecode(response.body);
      if (decoded is Map && decoded['results'] != null) {
        return decoded['results'] as List<dynamic>;
      }
      return decoded as List<dynamic>;
    } else {
      throw Exception('Erreur lors du chargement des notifications');
    }
  }

  static Future<void> marquerLue(int id) async {
    final token = await _getToken();
    if (token == null) return;

    await http.post(
      Uri.parse('$baseUrl/notifications/$id/marquer_lue/'),
      headers: {
        'Authorization': 'Bearer $token',
      },
    );
  }

  static Future<void> marquerToutLu() async {
    final token = await _getToken();
    if (token == null) return;

    await http.post(
      Uri.parse('$baseUrl/notifications/marquer_tout_lu/'),
      headers: {
        'Authorization': 'Bearer $token',
      },
    );
  }
}

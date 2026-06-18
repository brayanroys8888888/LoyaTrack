import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'api_config.dart';

class ApiClient {
  static final ApiClient _instance = ApiClient._internal();
  late Dio dio;
  final _storage = const FlutterSecureStorage();

  /// Appelé quand la session est définitivement perdue (refresh impossible).
  /// L'app y branche la redirection vers l'écran de connexion.
  static void Function()? onSessionExpired;

  /// Appelé sur un 403 `abonnement_expire` -> redirection vers le paywall.
  static void Function()? onSubscriptionExpired;

  /// Appelé sur un 403 `fonction_pro` -> feuille d'upsell (feature concernée si connue).
  static void Function(String? feature)? onProRequired;

  // Single-flight : un seul refresh à la fois, les requêtes concurrentes l'attendent.
  Future<bool>? _refreshing;

  factory ApiClient() => _instance;

  ApiClient._internal() {
    dio = Dio(
      BaseOptions(
        baseUrl: ApiConfig.baseUrl,
        connectTimeout: const Duration(seconds: 10),
        receiveTimeout: const Duration(seconds: 10),
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
        },
      ),
    );

    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) async {
          final token = await _storage.read(key: 'access_token');
          if (token != null) {
            options.headers['Authorization'] = 'Bearer $token';
          }
          return handler.next(options);
        },
        onError: (DioException e, handler) async {
          final req = e.requestOptions;
          final is401 = e.response?.statusCode == 401;
          final isRefreshCall = req.path.contains('token/refresh');
          final alreadyRetried = req.extra['__retried'] == true;

          // 403 lié à l'abonnement : code porté par le corps JSON du backend.
          if (e.response?.statusCode == 403) {
            final body = e.response?.data;
            final code = (body is Map) ? body['code'] : null;
            if (code == 'abonnement_expire') {
              onSubscriptionExpired?.call();
            } else if (code == 'fonction_pro') {
              onProRequired?.call(body is Map ? body['feature'] as String? : null);
            }
            return handler.next(e);
          }

          // 401 sur une requête authentifiée -> tenter un refresh puis rejouer.
          if (is401 && !isRefreshCall && !alreadyRetried) {
            final ok = await _refreshAccessToken();
            if (ok) {
              final newToken = await _storage.read(key: 'access_token');
              req.extra['__retried'] = true;
              req.headers['Authorization'] = 'Bearer $newToken';
              try {
                final clone = await dio.fetch(req);
                return handler.resolve(clone);
              } catch (err) {
                return handler.next(err is DioException ? err : e);
              }
            } else {
              await _clearSession();
            }
          }
          return handler.next(e);
        },
      ),
    );
  }

  /// Rafraîchit l'access token via le refresh token (single-flight).
  Future<bool> _refreshAccessToken() {
    return _refreshing ??= _doRefresh().whenComplete(() => _refreshing = null);
  }

  Future<bool> _doRefresh() async {
    final refresh = await _storage.read(key: 'refresh_token');
    if (refresh == null) return false;
    try {
      // Dio neuf, sans intercepteurs, pour éviter toute récursion.
      final raw = Dio(BaseOptions(baseUrl: ApiConfig.baseUrl));
      final r = await raw.post('auth/token/refresh/', data: {'refresh': refresh});
      if (r.statusCode == 200 && r.data['access'] != null) {
        await _storage.write(key: 'access_token', value: r.data['access']);
        // Rotation activée côté backend : un nouveau refresh est renvoyé.
        if (r.data['refresh'] != null) {
          await _storage.write(key: 'refresh_token', value: r.data['refresh']);
        }
        return true;
      }
      return false;
    } catch (_) {
      return false;
    }
  }

  Future<void> _clearSession() async {
    await _storage.delete(key: 'access_token');
    await _storage.delete(key: 'refresh_token');
    onSessionExpired?.call();
  }
}

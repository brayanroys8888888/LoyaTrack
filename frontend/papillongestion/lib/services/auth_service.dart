import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../core/api_client.dart';
import 'firebase_service.dart';

/// Résultat d'une tentative de connexion.
class LoginResult {
  final bool success;       // connecté (tokens stockés)
  final bool otpRequired;   // 2FA : un code OTP est attendu
  final int? userId;        // pour l'étape verify-otp
  final String? devCode;    // code OTP en mode DEBUG (tests)
  final String? error;
  const LoginResult({this.success = false, this.otpRequired = false, this.userId, this.devCode, this.error});
}

class AuthService {
  final Dio _dio = ApiClient().dio;
  final _storage = const FlutterSecureStorage();

  Future<void> _saveTokens(Map data) async {
    await _storage.write(key: 'access_token', value: data['access']);
    await _storage.write(key: 'refresh_token', value: data['refresh']);
    await FirebaseService.registerTokenWithBackend();
  }

  /// Connexion par téléphone OU email + mot de passe.
  Future<LoginResult> login(String identifiant, String password) async {
    try {
      final r = await _dio.post('auth/login/', data: {
        'identifiant': identifiant,
        'password': password,
      });
      if (r.statusCode == 200) {
        if (r.data['otp_requis'] == true) {
          return LoginResult(otpRequired: true, userId: r.data['user_id'], devCode: r.data['dev_code']);
        }
        await _saveTokens(r.data);
        return const LoginResult(success: true);
      }
      return const LoginResult(error: 'Réponse inattendue');
    } on DioException catch (e) {
      final msg = e.response?.data is Map ? (e.response?.data['detail'] ?? e.response?.data.toString()) : 'Identifiants invalides';
      return LoginResult(error: msg.toString());
    } catch (e) {
      return LoginResult(error: e.toString());
    }
  }

  /// Valide le code OTP de connexion (2FA) et stocke les tokens.
  Future<bool> verifyLoginOtp(int userId, String code) async {
    try {
      final r = await _dio.post('auth/login/verify-otp/', data: {'user_id': userId, 'code': code});
      if (r.statusCode == 200) {
        await _saveTokens(r.data);
        return true;
      }
      return false;
    } catch (e) {
      print('Erreur verifyLoginOtp: $e');
      return false;
    }
  }

  /// Active / désactive la 2FA (utilisateur connecté).
  Future<bool?> toggle2FA({bool? active}) async {
    try {
      final r = await _dio.post('auth/2fa/toggle/', data: {if (active != null) 'active': active});
      return r.statusCode == 200 ? r.data['deux_fa_active'] as bool : null;
    } catch (e) {
      print('Erreur toggle2FA: $e');
      return null;
    }
  }

  /// Inscription : email et/ou téléphone (au moins un).
  Future<LoginResult> register({
    String? email,
    String? telephone,
    required String password,
    required String confirmPassword,
    String nom = '',
    String prenom = '',
  }) async {
    try {
      final r = await _dio.post('auth/register/', data: {
        if (email != null && email.isNotEmpty) 'email': email,
        if (telephone != null && telephone.isNotEmpty) 'telephone': telephone,
        'password': password,
        'password_confirm': confirmPassword,
        'first_name': prenom,
        'last_name': nom,
      });
      if (r.statusCode == 201) {
        await _saveTokens(r.data);
        return const LoginResult(success: true);
      }
      return const LoginResult(error: 'Inscription échouée');
    } on DioException catch (e) {
      final d = e.response?.data;
      return LoginResult(error: d is Map ? d.values.first.toString() : 'Inscription échouée');
    } catch (e) {
      return LoginResult(error: e.toString());
    }
  }

  // ---- Réinitialisation par OTP SMS ----
  Future<String?> passwordForgot(String identifiant) async {
    try {
      final r = await _dio.post('auth/password/forgot/', data: {'telephone': identifiant});
      return r.statusCode == 200 ? (r.data['dev_code'] as String?) ?? '' : null;
    } catch (e) {
      print('Erreur passwordForgot: $e');
      return null;
    }
  }

  Future<String?> passwordVerifyOtp(String identifiant, String code) async {
    try {
      final r = await _dio.post('auth/password/verify-otp/', data: {'telephone': identifiant, 'code': code});
      return r.statusCode == 200 ? r.data['reset_token'] as String? : null;
    } catch (e) {
      print('Erreur passwordVerifyOtp: $e');
      return null;
    }
  }

  /// Renvoie `null` en cas de succès, sinon le message d'erreur (ex: règles de mot de passe).
  Future<String?> passwordReset(String resetToken, String newPassword) async {
    try {
      final r = await _dio.post('auth/password/reset/', data: {'reset_token': resetToken, 'new_password': newPassword});
      return r.statusCode == 200 ? null : 'Échec de la réinitialisation';
    } on DioException catch (e) {
      final d = e.response?.data;
      if (d is Map && d['error'] != null) {
        final err = d['error'];
        return err is List ? err.join('\n') : err.toString();
      }
      return 'Échec de la réinitialisation';
    } catch (e) {
      return 'Erreur réseau';
    }
  }

  /// Profil de l'utilisateur connecté (GET /auth/me/).
  Future<Map<String, dynamic>?> getProfile() async {
    try {
      final r = await _dio.get('auth/me/');
      return r.statusCode == 200 ? r.data as Map<String, dynamic> : null;
    } catch (e) {
      print('Erreur getProfile: $e');
      return null;
    }
  }

  Future<void> logout() async {
    await _storage.delete(key: 'access_token');
    await _storage.delete(key: 'refresh_token');
  }

  Future<bool> isLoggedIn() async {
    return (await _storage.read(key: 'access_token')) != null;
  }

  /// Restaure la session au démarrage : vérifie le token via /auth/me/ ;
  /// l'intercepteur tentera un refresh automatique si l'access est expiré.
  Future<bool> restaurerSession() async {
    final access = await _storage.read(key: 'access_token');
    final refresh = await _storage.read(key: 'refresh_token');
    if (access == null && refresh == null) return false;
    try {
      final r = await _dio.get('auth/me/');
      return r.statusCode == 200;
    } catch (_) {
      return false;
    }
  }
}

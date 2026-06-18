import 'dart:convert';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;

/// Handles background messages when app is terminated or in background
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp();
}

class FirebaseService {
  static const String _baseUrl = 'http://10.0.2.2:8000/api/v1';
  static const _storage = FlutterSecureStorage();

  static final FlutterLocalNotificationsPlugin _localNotifications =
      FlutterLocalNotificationsPlugin();

  static final AndroidNotificationChannel _channel = AndroidNotificationChannel(
    'loyatrack_channel',
    'LoyaTrack Notifications',
    description: 'Rappels de loyer et alertes de pénalité',
    importance: Importance.high,
    playSound: true,
  );

  /// Call once in main() after Firebase.initializeApp()
  static Future<void> initialize() async {
    // Setup local notifications
    await _localNotifications
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(_channel);

    const androidSettings =
        AndroidInitializationSettings('@mipmap/ic_launcher');
    const initSettings = InitializationSettings(android: androidSettings);
    await _localNotifications.initialize(initSettings);

    // Request permissions (Android 13+ / iOS)
    final messaging = FirebaseMessaging.instance;
    await messaging.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );

    // Show foreground notifications as heads-up
    await messaging.setForegroundNotificationPresentationOptions(
      alert: true,
      badge: true,
      sound: true,
    );

    // Listen for foreground messages and display them as local notifications
    FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      final notification = message.notification;
      if (notification != null) {
        _localNotifications.show(
          notification.hashCode,
          notification.title,
          notification.body,
          NotificationDetails(
            android: AndroidNotificationDetails(
              _channel.id,
              _channel.name,
              channelDescription: _channel.description,
              importance: Importance.high,
              priority: Priority.high,
              icon: '@mipmap/ic_launcher',
            ),
          ),
        );
      }
    });

    // Send FCM token to Django backend after setup
    await registerTokenWithBackend();
  }

  /// Gets the device FCM token and sends it to the Django API
  static Future<void> registerTokenWithBackend() async {
    try {
      final token = await FirebaseMessaging.instance.getToken();
      if (token == null) return;

      final accessToken = await _storage.read(key: 'access_token');
      if (accessToken == null) return;

      await http.post(
        Uri.parse('$_baseUrl/auth/fcm-token/'),
        headers: {
          'Authorization': 'Bearer $accessToken',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({'fcm_token': token}),
      );

      // Also listen for token refresh
      FirebaseMessaging.instance.onTokenRefresh.listen((newToken) async {
        final freshToken = await _storage.read(key: 'access_token');
        if (freshToken == null) return;
        await http.post(
          Uri.parse('$_baseUrl/auth/fcm-token/'),
          headers: {
            'Authorization': 'Bearer $freshToken',
            'Content-Type': 'application/json',
          },
          body: jsonEncode({'fcm_token': newToken}),
        );
      });
    } catch (e) {
      // Silently fail if not authenticated yet - will retry on next login
    }
  }
}

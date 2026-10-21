import 'package:flutter/foundation.dart' show kIsWeb;

/// Stub for web – push notifications are not supported
class PushNotificationService {
  static Future<void> init() async {
    if (kIsWeb) return;
    // On mobile, lazily import the real implementation
    final real = await _loadMobile();
    await real.init();
  }

  static Future<String?> getToken() async {
    if (kIsWeb) return null;
    final real = await _loadMobile();
    return real.getToken();
  }

  static Future<void> _loadMobile() async {
    // Dynamic import prevents web compilation
    final mobile = await _MobilePushNotificationService.create();
    return mobile;
  }
}

/// Real implementation – loaded only on mobile
class _MobilePushNotificationService {
  static Future<_MobilePushNotificationService> create() async {
    final FirebaseMessaging messaging = FirebaseMessaging.instance;
    return _MobilePushNotificationService._(messaging);
  }

  final FirebaseMessaging messaging;
  _MobilePushNotificationService._(this.messaging);

  Future<void> init() async {
    await messaging.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );
  }

  Future<String?> getToken() async {
    return messaging.getToken();
  }

  Stream<String> get onTokenRefresh => messaging.onTokenRefresh;
}
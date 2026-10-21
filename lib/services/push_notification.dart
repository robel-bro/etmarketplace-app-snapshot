// lib/services/push_notification.dart
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter/foundation.dart';

class PushNotification {
  static final FlutterLocalNotificationsPlugin _localNotifications =
      FlutterLocalNotificationsPlugin();

  static Future<void> init() async {
    final messaging = FirebaseMessaging.instance;

    await messaging.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );

    // ── Create channels ──────────────────────────────
    const AndroidNotificationChannel normalChannel = AndroidNotificationChannel(
      'default_channel',
      'General Notifications',
      description: 'Order updates, promotions, and messages',
      importance: Importance.high,
      playSound: true,
      sound: RawResourceAndroidNotificationSound('bell'),
    );

    const AndroidNotificationChannel alarmChannel = AndroidNotificationChannel(
      'order_alerts',
      'Order Alerts',
      description: 'New orders and urgent alerts',
      importance: Importance.high,
      playSound: true,
      sound: RawResourceAndroidNotificationSound('alarm'),
    );

    final androidPlugin = _localNotifications
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>();

    try {
      await androidPlugin?.createNotificationChannel(normalChannel);
      debugPrint('✅ Created channel: default_channel');
    } catch (e) {
      debugPrint('❌ Failed to create default_channel: $e');
    }

    try {
      await androidPlugin?.createNotificationChannel(alarmChannel);
      debugPrint('✅ Created channel: order_alerts');
    } catch (e) {
      debugPrint('❌ Failed to create order_alerts: $e');
    }

    // ── Foreground message listener ─────────────────
    FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      final notification = message.notification;
      if (notification == null) return;

      final isHighPriority = message.data['priority'] == 'high';
      debugPrint('📩 onMessage – priority: ${message.data['priority']}, isHigh: $isHighPriority');

      final channelId = isHighPriority ? 'order_alerts' : 'default_channel';
      final sound = isHighPriority
          ? const RawResourceAndroidNotificationSound('alarm')
          : const RawResourceAndroidNotificationSound('bell');

      debugPrint('🔊 Using channel: $channelId, sound: ${isHighPriority ? "alarm" : "bell"}');

      _localNotifications.show(
        id: notification.hashCode,
        title: notification.title,
        body: notification.body,
        notificationDetails: NotificationDetails(
          android: AndroidNotificationDetails(
            channelId,
            isHighPriority ? 'Order Alerts' : 'General Notifications',
            channelDescription: isHighPriority
                ? 'New order and urgent alerts'
                : 'Order updates, promotions, and messages',
            importance: Importance.high,
            priority: isHighPriority ? Priority.high : Priority.defaultPriority,
            playSound: true,
            sound: sound,
            icon: '@mipmap/ic_launcher',
          ),
        ),
      );
    });

    FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
      debugPrint('📩 onMessageOpenedApp: ${message.data}');
    });
  }

  static Future<String?> getToken() async {
    final token = await FirebaseMessaging.instance.getToken();
    debugPrint('FCM Token: $token');
    return token;
  }

  static Stream<String> get onTokenRefresh =>
      FirebaseMessaging.instance.onTokenRefresh;
}
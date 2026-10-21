// lib/services/push_notification_mobile.dart
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

class PushNotification {
  static final FlutterLocalNotificationsPlugin _localNotifications =
      FlutterLocalNotificationsPlugin();

  /// Initialize Firebase Messaging and local notification channels.
  static Future<void> init() async {
    try {
      final messaging = FirebaseMessaging.instance;

      // Request permission for iOS and Android 13+
      await messaging.requestPermission(
        alert: true,
        badge: true,
        sound: true,
      );

      // Create Android notification channels
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

      await androidPlugin?.createNotificationChannel(normalChannel);
      await androidPlugin?.createNotificationChannel(alarmChannel);

      // Handle foreground notifications
      FirebaseMessaging.onMessage.listen((RemoteMessage message) {
        final notification = message.notification;
        if (notification == null) return;

        final isHighPriority = message.data['priority'] == 'high';
        final channelId = isHighPriority ? 'order_alerts' : 'default_channel';
        final sound = isHighPriority
            ? const RawResourceAndroidNotificationSound('alarm')
            : const RawResourceAndroidNotificationSound('bell');

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
            ),
          ),
        );
      });

      // Handle notification tap when app is in background/terminated
      FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
        // TODO: navigate based on message.data['deep_link'] if needed
      });
    } catch (e) {
      debugPrint('PushNotification.init error: $e');
    }
  }

  /// Get current FCM token.
  static Future<String?> getToken() async {
    try {
      final token = await FirebaseMessaging.instance.getToken();
      debugPrint('FCM Token: $token');
      return token;
    } catch (e) {
      debugPrint('Failed to get FCM token: $e');
      return null;
    }
  }

  /// Stream that emits new token when FCM refreshes it.
  static Stream<String> get onTokenRefresh =>
      FirebaseMessaging.instance.onTokenRefresh;
}
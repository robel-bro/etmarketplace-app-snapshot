class PushNotification {
  static Future<void> init() async {}
  static Future<String?> getToken() async => null;
  static Stream<String> get onTokenRefresh => const Stream.empty();
}
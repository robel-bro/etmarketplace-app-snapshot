// lib/api/token_storage.dart
import 'package:flutter/foundation.dart';
import 'token_storage_web.dart' if (dart.library.io) 'token_storage_mobile.dart';

abstract class TokenStorage {
  Future<String?> get accessToken;
  Future<String?> get refreshToken;
  Future<void> saveTokens({required String accessToken, required String refreshToken});
  Future<void> clearTokens();
}

TokenStorage getTokenStorage() => getPlatformTokenStorage();
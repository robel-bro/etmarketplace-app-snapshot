// lib/api/token_storage_mobile.dart
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'token_storage.dart';

const _storage = FlutterSecureStorage();

class MobileTokenStorage implements TokenStorage {
  // Optional in-memory cache for synchronous access (e.g., WebSocket token)
  String? _cachedAccessToken;

  @override
  Future<String?> get accessToken async {
    // Return cache if available; otherwise read from secure storage and cache it
    if (_cachedAccessToken != null) return _cachedAccessToken;
    _cachedAccessToken = await _storage.read(key: 'access_token');
    return _cachedAccessToken;
  }

  // Synchronous getter for cached token (returns null if not loaded yet)
  String? get cachedAccessToken => _cachedAccessToken;

  @override
  Future<String?> get refreshToken => _storage.read(key: 'refresh_token');

  @override
  Future<void> saveTokens({
    required String accessToken,
    required String refreshToken,
  }) async {
    _cachedAccessToken = accessToken;
    await _storage.write(key: 'access_token', value: accessToken);
    await _storage.write(key: 'refresh_token', value: refreshToken);
  }

  @override
  Future<void> clearTokens() async {
    _cachedAccessToken = null;
    await _storage.deleteAll();
  }
}

TokenStorage getPlatformTokenStorage() => MobileTokenStorage();
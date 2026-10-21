// lib/api/token_storage_web.dart
import 'dart:html' as html;
import 'token_storage.dart';

class WebTokenStorage implements TokenStorage {
  // Optional in-memory cache for synchronous access (e.g., WebSocket token)
  String? _cachedAccessToken;

  @override
  Future<String?> get accessToken {
    // Return cache if available; otherwise read from localStorage and cache it
    if (_cachedAccessToken != null) return Future.value(_cachedAccessToken);
    _cachedAccessToken = html.window.localStorage['access_token'];
    return Future.value(_cachedAccessToken);
  }

  // Synchronous getter for cached token (returns null if not loaded yet)
  String? get cachedAccessToken => _cachedAccessToken;

  @override
  Future<String?> get refreshToken =>
      Future.value(html.window.localStorage['refresh_token']);

  @override
  Future<void> saveTokens({
    required String accessToken,
    required String refreshToken,
  }) async {
    _cachedAccessToken = accessToken;
    html.window.localStorage['access_token'] = accessToken;
    html.window.localStorage['refresh_token'] = refreshToken;
  }

  @override
  Future<void> clearTokens() async {
    _cachedAccessToken = null;
    html.window.localStorage.remove('access_token');
    html.window.localStorage.remove('refresh_token');
  }
}

TokenStorage getPlatformTokenStorage() => WebTokenStorage();
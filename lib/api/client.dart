// 📁 lib/api/client.dart
import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../main.dart' show navigatorKey;
import 'token_storage.dart';

class OfflineException implements Exception {
  final String message;
  OfflineException(this.message);
  @override
  String toString() => message;
}

class ApiClient {
  static final ApiClient instance = ApiClient._();
  late final Dio dio;
  final TokenStorage _storage = getTokenStorage();

  static String? _cachedAccessToken;
  static bool _isOffline = false;
  static bool get isOffline => _isOffline;

  // ── Refresh lock and pending queue ──
  static bool _isRefreshing = false;
  static final List<Completer<String?>> _refreshWaiters = [];

  // ★ Resolve base URL from environment, with sensible defaults for local dev.
  static String get _baseUrl {
    final configured = dotenv.env['API_BASE_URL'];
    if (configured != null && configured.isNotEmpty) return configured;
    if (kIsWeb) return 'http://localhost:3000';
    if (defaultTargetPlatform == TargetPlatform.android) {
      return 'http://10.0.2.2:3000';
    }
    return 'http://localhost:3000';
  }

  // ★ WebSocket base URL for ActionCable (if needed later)
  static String get webSocketBaseUrl {
    final configured = dotenv.env['WS_URL'];
    if (configured != null && configured.isNotEmpty) return configured;
    if (kIsWeb) return 'ws://localhost:3000';
    if (defaultTargetPlatform == TargetPlatform.android) {
      return 'ws://10.0.2.2:3000';
    }
    return 'ws://localhost:3000';
  }

  // ★ Synchronously get cached token (useful for WebSocket connection)
  static String? get cachedAccessToken => _cachedAccessToken;

  ApiClient._() {
    dio = Dio(BaseOptions(
      baseUrl: _baseUrl,
      connectTimeout: const Duration(seconds: 30),
      receiveTimeout: const Duration(seconds: 30),
      headers: {
        'Content-Type': 'application/json',
        'Accept': 'application/json',
      },
    ));

    dio.interceptors.add(InterceptorsWrapper(
      onRequest: (options, handler) async {
        // Load token from cache or storage
        final token = await getToken();
        if (token != null && token.isNotEmpty) {
          options.headers['Authorization'] = 'Bearer $token';
        }
        handler.next(options);
      },
      onError: (error, handler) async {
        // Offline detection
        if (error.type == DioExceptionType.connectionError ||
            error.type == DioExceptionType.connectionTimeout ||
            error.type == DioExceptionType.receiveTimeout ||
            error.type == DioExceptionType.sendTimeout) {
          _isOffline = true;
          handler.reject(DioException(
            requestOptions: error.requestOptions,
            error: OfflineException('You are offline. Check your connection.'),
            type: DioExceptionType.connectionError,
          ));
          return;
        }

        if (error.response?.statusCode == 401) {
          final hadToken = await getToken() != null;
          if (hadToken) {
            final newToken = await _refreshTokenWithQueue();
            if (newToken != null) {
              // Retry original request with new token
              try {
                final opts = Options(
                  method: error.requestOptions.method,
                  headers: error.requestOptions.headers..['Authorization'] = 'Bearer $newToken',
                );
                final retryResponse = await dio.request(
                  error.requestOptions.path,
                  options: opts,
                  data: error.requestOptions.data,
                  queryParameters: error.requestOptions.queryParameters,
                );
                handler.resolve(retryResponse);
                _isOffline = false;
                return;
              } catch (e) {
                handler.next(e as DioException);
                return;
              }
            } else {
              // Refresh failed – clear and logout
              await clearAll();
              final ctx = navigatorKey.currentContext;
              if (ctx != null) {
                Navigator.of(ctx).pushNamedAndRemoveUntil(
                  '/login',
                  (route) => route.settings.name == '/welcome',
                );
              }
              handler.next(error);
              return;
            }
          } else {
            handler.next(error);
            return;
          }
        }

        _isOffline = false;
        handler.next(error);
      },
    ));
  }

  // ─── Initialization ────────────────────────────────
  static Future<void> init() async {
    // Ensure instance exists
    final api = instance;
    // Load cached token from storage if any
    final stored = await api._storage.accessToken;
    if (stored != null && stored.isNotEmpty) {
      _cachedAccessToken = stored;
    }
  }

  // ─── Token management ────────────────────────────────
  static Future<void> setToken(String token) async {
    _cachedAccessToken = token;
    await getTokenStorage().saveTokens(
      accessToken: token,
      refreshToken: await getTokenStorage().refreshToken ?? '',
    );
  }

  static Future<String?> getToken() async {
    if (_cachedAccessToken == null) {
      _cachedAccessToken = await getTokenStorage().accessToken;
    }
    return _cachedAccessToken;
  }

  static Future<void> clearAll() async {
    _cachedAccessToken = null;
    await getTokenStorage().clearTokens();
  }

  static Future<void> clearToken() async => clearAll();

  static bool get hasToken {
    return _cachedAccessToken != null && _cachedAccessToken!.isNotEmpty;
  }

  // ─── Refresh with queue (single refresh at a time) ──
  Future<String?> _refreshTokenWithQueue() async {
    // If already refreshing, wait for the result
    if (_isRefreshing) {
      final completer = Completer<String?>();
      _refreshWaiters.add(completer);
      return completer.future;
    }

    _isRefreshing = true;
    try {
      final newToken = await _tryRefresh();
      // Notify all waiters
      for (final completer in _refreshWaiters) {
        completer.complete(newToken);
      }
      _refreshWaiters.clear();
      return newToken;
    } catch (_) {
      for (final completer in _refreshWaiters) {
        completer.complete(null);
      }
      _refreshWaiters.clear();
      return null;
    } finally {
      _isRefreshing = false;
    }
  }

  Future<String?> _tryRefresh() async {
    try {
      final refresh = await _storage.refreshToken;
      if (refresh == null || refresh.isEmpty) return null;

      // Use a separate Dio instance without interceptors to avoid recursion
      final refreshDio = Dio(BaseOptions(
        baseUrl: dio.options.baseUrl,
        connectTimeout: const Duration(seconds: 15),
        receiveTimeout: const Duration(seconds: 15),
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
        },
      ));

      final response = await refreshDio.post(
        '/refresh',
        data: {'refresh_token': refresh},
      );

      if (response.statusCode == 200) {
        final newAccess = response.data['access_token'];
        final newRefresh = response.data['refresh_token'];
        if (newAccess != null && newRefresh != null) {
          await _storage.saveTokens(
            accessToken: newAccess,
            refreshToken: newRefresh,
          );
          _cachedAccessToken = newAccess;
          return newAccess;
        }
      }
    } catch (_) {}
    return null;
  }

  // ─── Convenience HTTP helpers ─────────────────────────
  Future<Response> get(String path, {Map<String, dynamic>? queryParameters}) =>
      dio.get(path, queryParameters: queryParameters);

  Future<Response> post(String path, {dynamic data}) =>
      dio.post(path, data: data);

  Future<Response> patch(String path, {dynamic data}) =>
      dio.patch(path, data: data);

  Future<Response> put(String path, {dynamic data}) =>
      dio.put(path, data: data);

  Future<Response> delete(String path, {dynamic data}) =>
      dio.delete(path, data: data);

  // ══════════════ Geocoding convenience ══════════════

  /// Reverse‑geocode coordinates using the backend.
  static Future<Map<String, dynamic>> reverseGeocode(double lat, double lng) async {
    final response = await instance.get(
      '/geocode/reverse',
      queryParameters: {
        'lat': lat.toString(),
        'lon': lng.toString(),
      },
    );
    return {
      'address': response.data['address'] as String? ?? '',
      'structured': response.data['structured'] as Map<String, dynamic>? ?? {},
    };
  }

  /// Get address suggestions for autocomplete.
  static Future<Map<String, dynamic>> suggestAddress(String query) async {
    final response = await instance.get(
      '/geocode/suggest',
      queryParameters: {'query': query},
    );
    final suggestions = (response.data['suggestions'] as List?) ?? [];
    return {'suggestions': suggestions};
  }

  /// Validate a place address and return structured data.
  static Future<Map<String, dynamic>> validatePlace(String address) async {
    final response = await instance.post(
      '/geocode/validate_place',
      data: {'address': address},
    );
    return response.data as Map<String, dynamic>;
  }
}
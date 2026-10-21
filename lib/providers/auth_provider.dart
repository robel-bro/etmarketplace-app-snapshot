// lib/providers/auth_provider.dart
import 'dart:async';
import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import '../api/client.dart';
import '../api/token_storage.dart';
import '../models/user.dart';
import '../services/push_notification.dart';

final authProvider = StateNotifierProvider<AuthNotifier, AsyncValue<User?>>((ref) {
  return AuthNotifier(ref);
});

class AuthNotifier extends StateNotifier<AsyncValue<User?>>
    with WidgetsBindingObserver {
  final TokenStorage _storage = getTokenStorage();
  final Ref _ref;

  StreamSubscription<String>? _fcmTokenRefreshSub;

  AuthNotifier(this._ref) : super(const AsyncValue.loading()) {
    WidgetsBinding.instance.addObserver(this);
    _setupFcmTokenRefreshListener();

    // ✅ Defer initial session check to avoid provider cycle
    Future.microtask(checkSession);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _fcmTokenRefreshSub?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      refresh();
    }
  }

  void _setupFcmTokenRefreshListener() {
    _fcmTokenRefreshSub?.cancel();
    _fcmTokenRefreshSub = PushNotification.onTokenRefresh.listen((newToken) {
      if (newToken.isNotEmpty) {
        _registerFcmToken();
      }
    });
  }

  Future<void> checkSession() async {
    final storedToken = await _storage.accessToken;
    if (storedToken != null && storedToken.isNotEmpty) {
      await ApiClient.setToken(storedToken);
    }

    try {
      final response = await ApiClient.instance.get('/session');
      final userData = response.data['user'];
      if (userData != null) {
        final user = User.fromJson(Map<String, dynamic>.from(userData));
        state = AsyncValue.data(user);
        _registerFcmToken();
      } else {
        state = const AsyncValue.data(null);
      }
    } catch (e) {
      debugPrint('checkSession error: $e');
      state = const AsyncValue.data(null);
    }
  }

  Future<void> refresh() async {
    try {
      final response = await ApiClient.instance.get('/session');
      final userData = response.data['user'];
      if (userData != null) {
        final user = User.fromJson(Map<String, dynamic>.from(userData));
        state = AsyncValue.data(user);
        _registerFcmToken();
      } else {
        state = const AsyncValue.data(null);
      }
    } catch (e) {
      debugPrint('refresh error: $e');
      state = const AsyncValue.data(null);
    }
  }

  Future<bool> login(String phone, String password) async {
    state = const AsyncValue.loading();
    try {
      final response = await ApiClient.instance.post('/login', data: {
        'phone': phone,
        'password': password,
      });

      debugPrint('Login raw response: ${response.data}');

      final Map<String, dynamic> body;
      if (response.data is Map<String, dynamic>) {
        body = response.data as Map<String, dynamic>;
      } else if (response.data is Map) {
        body = Map<String, dynamic>.from(response.data as Map);
      } else if (response.data is String) {
        body = Map<String, dynamic>.from(jsonDecode(response.data as String));
      } else {
        throw Exception('Unexpected response type: ${response.data.runtimeType}');
      }

      final userDataRaw = body['user'];
      final accessToken  = body['access_token'];
      final refreshToken = body['refresh_token'];

      if (userDataRaw == null) {
        debugPrint('No user data in response: $body');
        return false;
      }

      final userData = Map<String, dynamic>.from(userDataRaw as Map);
      final user = User.fromJson(userData);

      if (accessToken != null && refreshToken != null) {
        await _storage.saveTokens(
          accessToken: accessToken.toString(),
          refreshToken: refreshToken.toString(),
        );
        await ApiClient.setToken(accessToken.toString());
      }

      state = AsyncValue.data(user);
      _registerFcmToken();
      return true;
    } catch (e) {
      debugPrint('Login error: $e');
      state = const AsyncValue.data(null);
      return false;
    }
  }

  Future<bool> register(String phone, String name, String password, {String? region}) async {
    state = const AsyncValue.loading();
    try {
      final payload = <String, dynamic>{
        'user': {
          'phone': phone,
          'full_name': name,
          'password': password,
          'password_confirmation': password,
        }
      };
      if (region != null && region.isNotEmpty) {
        payload['region'] = region;
      }
      await ApiClient.instance.post('/sign_up', data: payload);
      state = const AsyncValue.data(null);
      return true;
    } catch (e) {
      debugPrint('Register error: $e');
      state = const AsyncValue.data(null);
      return false;
    }
  }

  Future<bool> verifyRegisterOtp({required String phone, required String code}) async {
    state = const AsyncValue.loading();
    try {
      final response = await ApiClient.instance.post('/verify_otp', data: {
        'phone': phone,
        'code': code,
      });
      final userDataRaw = response.data['user'];
      final accessToken  = response.data['access_token'];
      final refreshToken = response.data['refresh_token'];

      if (userDataRaw != null) {
        final user = User.fromJson(Map<String, dynamic>.from(userDataRaw));
        if (accessToken != null && refreshToken != null) {
          await _storage.saveTokens(
            accessToken: accessToken.toString(),
            refreshToken: refreshToken.toString(),
          );
          await ApiClient.setToken(accessToken.toString());
        }
        state = AsyncValue.data(user);
        _registerFcmToken();
        return true;
      }
      state = const AsyncValue.data(null);
      return true;
    } catch (e) {
      debugPrint('Verify OTP error: $e');
      state = const AsyncValue.data(null);
      return false;
    }
  }

  Future<void> resendRegisterOtp({required String phone}) async {
    try {
      await ApiClient.instance.post('/send_otp', data: {'phone': phone});
    } catch (e) {
      debugPrint('Resend OTP error: $e');
    }
  }

  Future<void> logout() async {
    try { await ApiClient.instance.delete('/api/v1/profile/fcm_token'); } catch (_) {}
    try { await ApiClient.instance.delete('/logout'); } catch (_) {}
    await _storage.clearTokens();
    await ApiClient.clearAll();
    state = const AsyncValue.data(null);
    // ✅ cart/wishlist/compare providers react to auth state change automatically
  }

  Future<void> _registerFcmToken() async {
    if (kIsWeb) return;
    try {
      String? token = await PushNotification.getToken();
      if (token != null && token.isNotEmpty) {
        await ApiClient.instance.patch('/api/v1/profile/fcm_token', data: {
          'fcm_token': token,
        });
        debugPrint('FCM token registered successfully');
      }
    } catch (e) {
      debugPrint('FCM token registration failed: $e');
    }
  }
}
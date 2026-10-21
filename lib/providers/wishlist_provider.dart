// lib/providers/wishlist_provider.dart
import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../api/client.dart';
import '../models/wishlist.dart';
import '../providers/auth_provider.dart';

final wishlistProvider =
    StateNotifierProvider<WishlistNotifier, List<WishlistItem>>((ref) {
  return WishlistNotifier(ref);
});

class WishlistNotifier extends StateNotifier<List<WishlistItem>> {
  final Ref _ref;
  bool _wasAuthenticated = false;
  bool _listenerAttached = false;

  WishlistNotifier(this._ref) : super([]) {
    _attachAuthListener();
    Future.microtask(_init);
  }

  void _attachAuthListener() {
    if (_listenerAttached) return;
    _listenerAttached = true;

    _ref.listen(authProvider, (prev, next) {
      final nowAuthenticated = next != null;
      if (nowAuthenticated && !_wasAuthenticated) {
        _mergeAndClearGuestWishlist();
      } else if (!nowAuthenticated) {
        _saveGuestWishlist();
        state = [];
      }
      _wasAuthenticated = nowAuthenticated;
    });
  }

  Future<void> _init() async {
    final auth = _ref.read(authProvider);
    _wasAuthenticated = auth != null;
    if (_wasAuthenticated) {
      await fetchWishlist();
    } else {
      await _loadGuestWishlist();
    }
  }

  // ─── Guest persistence ─────────────────────────────
  static const _guestKey = 'guest_wishlist';

  Future<void> _loadGuestWishlist() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final jsonStr = prefs.getString(_guestKey);
      if (jsonStr != null) {
        final List data = jsonDecode(jsonStr) as List;
        state = data.map((json) => WishlistItem.fromJson(json)).toList();
      } else {
        state = [];
      }
    } catch (_) {
      state = [];
    }
  }

  Future<void> _saveGuestWishlist() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final jsonList = state.map((item) => {
            'id': item.id,
            'product_id': item.productId,
            'title': item.title,
            'price': item.price,
            'image_url': item.imageUrl,
            'variant_attributes': item.variantAttributes,
          }).toList();
      await prefs.setString(_guestKey, jsonEncode(jsonList));
    } catch (_) {}
  }

  Future<void> _mergeAndClearGuestWishlist() async {
    final prefs = await SharedPreferences.getInstance();
    final jsonStr = prefs.getString(_guestKey);
    if (jsonStr == null) {
      await fetchWishlist();
      return;
    }

    final List data = jsonDecode(jsonStr) as List;
    for (final json in data) {
      final productId = json['product_id'] as int;
      if (productId == null) continue;
      try {
        await ApiClient.instance.post('/wishlist/add_item', data: {
          'product_id': productId,
        });
      } catch (_) {}
    }

    await prefs.remove(_guestKey);
    await fetchWishlist();
  }

  // ─── Server wishlist ──────────────────────────────
  Future<void> fetchWishlist() async {
    if (!ApiClient.hasToken) {
      await _loadGuestWishlist();
      return;
    }
    try {
      final response = await ApiClient.instance.get('/wishlist');
      final data = response.data;
      final itemsList = (data is Map ? data['items'] : data) as List? ?? [];
      state = itemsList.map((json) => WishlistItem.fromJson(json)).toList();
    } catch (_) {
      state = [];
    }
  }

  // ─── Public actions ──────────────────────────────
  Future<void> addItem(dynamic product, {Map<String, String>? variant}) async {
    if (!ApiClient.hasToken) {
      _addGuestItem(product);
      return;
    }
    try {
      final payload = <String, dynamic>{
        'product_id': product.id,
      };
      if (variant != null && variant.isNotEmpty) {
        payload['variant'] = variant;
      }
      await ApiClient.instance.post('/wishlist/add_item', data: payload);
      await fetchWishlist();
    } catch (_) {}
  }

  void _addGuestItem(dynamic product) {
    if (state.any((item) => item.productId == product.id)) return;

    final newItem = WishlistItem(
      id: DateTime.now().millisecondsSinceEpoch,
      productId: product.id,
      title: product.title,
      price: product.effectivePrice ?? product.price,
      imageUrl: product.images != null && product.images.isNotEmpty
          ? product.images.first
          : (product.image_urls != null && product.image_urls.isNotEmpty
              ? product.image_urls.first
              : ''),
      variantAttributes: product.variant ?? {},
    );

    state = [...state, newItem];
    _saveGuestWishlist();
  }

  Future<void> removeItem(int productId) async {
    if (!ApiClient.hasToken) {
      _removeGuestItem(productId);
      return;
    }
    try {
      await ApiClient.instance.delete('/wishlist/remove_item/$productId');
      await fetchWishlist();
    } catch (_) {}
  }

  void _removeGuestItem(int productId) {
    state = state.where((item) => item.productId != productId).toList();
    _saveGuestWishlist();
  }

  bool isInWishlist(int productId) {
    return state.any((item) => item.productId == productId);
  }
}
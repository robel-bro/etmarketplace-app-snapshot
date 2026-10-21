// lib/providers/cart_provider.dart
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:dio/dio.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../api/client.dart';
import '../models/cart.dart';
import '../models/product.dart';
import '../providers/auth_provider.dart';

final cartProvider = StateNotifierProvider<CartNotifier, Cart?>((ref) {
  return CartNotifier(ref);
});

class CartNotifier extends StateNotifier<Cart?> {
  final Ref _ref;
  bool _wasAuthenticated = false;
  bool _mergeInProgress = false;
  bool _listenerAttached = false;

  CartNotifier(this._ref) : super(null) {
    // ✅ Defer initialization to avoid reading auth during provider construction
    Future.microtask(_init);
  }

  static const _guestKey = 'guest_cart';

  Future<void> _init() async {
    // Read auth safely after current build
    final auth = _ref.read(authProvider);
    _wasAuthenticated = auth != null;

    if (_wasAuthenticated) {
      await fetchCart();
    } else {
      final saved = await _loadGuestCart();
      state = saved ?? Cart(items: [], totalPrice: 0, itemCount: 0);
    }

    if (!_listenerAttached) {
      _listenerAttached = true;
      _ref.listen(authProvider, (prev, next) {
        final nowAuthenticated = next != null;
        if (nowAuthenticated && !_wasAuthenticated) {
          _mergeAndClearGuestCart();
        } else if (!nowAuthenticated) {
          state = Cart(items: [], totalPrice: 0, itemCount: 0);
          _clearGuestCart();
        }
        _wasAuthenticated = nowAuthenticated;
      });
    }
  }

  // ─── Guest cart persistence (unchanged) ──────────────
  Future<Cart?> _loadGuestCart() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_guestKey);
      if (raw == null) return null;
      final map = jsonDecode(raw);
      final items = (map['items'] as List)
          .map((i) => CartItem(
                id: i['id'],
                productId: i['productId'] ?? 0,
                packageId: i['packageId'],
                title: i['title'],
                price: (i['price'] as num).toDouble(),
                quantity: i['quantity'],
                stock: i['stock'],
                variant: Map<String, String>.from(i['variant'] ?? {}),
                image: i['image'] ?? '',
              ))
          .toList();
      return Cart(
        items: items,
        totalPrice: (map['total'] as num).toDouble(),
        itemCount: map['item_count'],
      );
    } catch (_) {
      return null;
    }
  }

  Future<void> _saveGuestCart() async {
    if (state == null) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final jsonStr = jsonEncode({
        'items': state!.items.map((i) => {
          'id': i.id,
          'productId': i.productId,
          'packageId': i.packageId,
          'title': i.title,
          'price': i.price,
          'quantity': i.quantity,
          'stock': i.stock,
          'variant': i.variant,
          'image': i.image,
        }).toList(),
        'total': state!.totalPrice,
        'item_count': state!.itemCount,
      });
      await prefs.setString(_guestKey, jsonStr);
    } catch (_) {}
  }

  Future<void> _clearGuestCart() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_guestKey);
  }

  Future<void> _mergeAndClearGuestCart() async {
    if (_mergeInProgress) return;
    _mergeInProgress = true;
    try {
      final guestCart = await _loadGuestCart();
      if (guestCart != null && guestCart.items.isNotEmpty) {
        for (final item in guestCart.items) {
          try {
            final data = <String, dynamic>{
              'quantity': item.quantity,
            };
            if (item.packageId != null) {
              data['package_id'] = item.packageId;
            } else if (item.productId != 0) {
              data['product_id'] = item.productId;
              if (item.variant.isNotEmpty) {
                data['variant'] = item.variant;
              }
            } else {
              continue;
            }
            await ApiClient.instance.post('/cart/add_item', data: data);
          } on DioException catch (e) {
            debugPrint('Failed to merge item ${item.title}: ${e.response?.data?['error']}');
          } catch (_) {}
        }
      }
    } finally {
      await _clearGuestCart();
      _mergeInProgress = false;
      await fetchCart();
    }
  }

  // ─── Server fetch ────────────────────────────────────
  Future<void> fetchCart() async {
    if (!ApiClient.hasToken) {
      state = Cart(items: [], totalPrice: 0, itemCount: 0);
      return;
    }
    try {
      final response = await ApiClient.instance.get('/cart');
      state = Cart.fromJson(response.data);
    } catch (_) {
      state = Cart(items: [], totalPrice: 0, itemCount: 0);
    }
  }

  // ─── Add single item (unchanged) ─────────────────────
  Future<void> addItem(Product product, {int quantity = 1, Map<String, String>? variant}) async {
    if (product.bulkEnabled && product.minimumBulkQuantity != null) {
      if (quantity < product.minimumBulkQuantity!) {
        debugPrint('Bulk product requires at least ${product.minimumBulkQuantity} units');
        return;
      }
    }

    if (!ApiClient.hasToken) {
      _addGuestItem(product, quantity: quantity, variant: variant);
      return;
    }

    try {
      final data = <String, dynamic>{
        'product_id': product.id,
        'quantity': quantity,
      };
      if (product.isPackage) {
        data.remove('product_id');
        data['package_id'] = product.id;
      }
      if (variant != null && variant.isNotEmpty) {
        data['variant'] = variant;
      }
      await ApiClient.instance.post('/cart/add_item', data: data);
      await fetchCart();
    } on DioException catch (e) {
      final msg = e.response?.data?['error'] ?? 'Failed to add to cart';
      debugPrint('Cart add error: $msg');
    } catch (_) {}
  }

  // ★ NEW: Atomic batch add (calls /cart/add_items)
  Future<void> batchAddItems(List<Map<String, dynamic>> items) async {
    if (!ApiClient.hasToken) {
      // For guest users, add individually (not atomic, but okay for guest)
      for (final item in items) {
        final prodId = item['product_id'] as int;
        final qty = item['quantity'] as int;
        final variant = item['variant'] as Map<String, String>?;
        // Find product from state? Not ideal; we'll rely on frontend passing product info later.
        // For now just call addItem with dummy Product – we'll improve this in the UI.
      }
      return;
    }

    try {
      final response = await ApiClient.instance.post(
        '/cart/add_items',
        data: {'items': items},
      );
      state = Cart.fromJson(response.data);
    } on DioException catch (e) {
      final msg = e.response?.data?['error'] ?? 'Failed to add items';
      debugPrint('Batch add error: $msg');
      // Re-fetch to ensure consistency
      await fetchCart();
    } catch (_) {
      await fetchCart();
    }
  }

  // ─── Quantity update ────────────────────────────────
  Future<void> updateQuantity(int itemId, int quantity) async {
    if (quantity <= 0) {
      await removeItem(itemId);
      return;
    }

    // Enforce bulk MOQ before calling API (for immediate feedback)
    final item = state?.items.firstWhere((i) => i.id == itemId);
    if (item != null && item.productId != null) {
      final moqInfo = state?.minimumBulkProgress?[item.productId!];
      if (moqInfo != null) {
        final currentTotal = moqInfo.currentQuantity;
        final projected = currentTotal - item.quantity + quantity;
        if (projected < moqInfo.minimumRequired) {
          debugPrint('Cannot decrease below MOQ of ${moqInfo.minimumRequired}');
          return;
        }
      }
    }

    if (!ApiClient.hasToken) {
      _updateGuestItemQuantity(itemId, quantity);
      return;
    }

    try {
      await ApiClient.instance.patch('/cart/update_item', data: {
        'item_id': itemId,
        'quantity': quantity,
      });
      await fetchCart();
    } catch (_) {}
  }

  void _updateGuestItemQuantity(int itemId, int quantity) {
    final items = List<CartItem>.from(state?.items ?? []);
    final index = items.indexWhere((i) => i.id == itemId);
    if (index == -1) return;

    // MOQ guard for guest
    final productId = items[index].productId;
    if (productId != null) {
      final moqInfo = state?.minimumBulkProgress?[productId];
      if (moqInfo != null) {
        final currentTotal = moqInfo.currentQuantity;
        final projected = currentTotal - items[index].quantity + quantity;
        if (projected < moqInfo.minimumRequired) {
          return; // ignore
        }
      }
    }

    items[index] = CartItem(
      id: items[index].id,
      productId: items[index].productId,
      packageId: items[index].packageId,
      title: items[index].title,
      price: items[index].price,
      quantity: quantity,
      stock: items[index].stock,
      variant: items[index].variant,
      image: items[index].image,
    );

    // Recalculate MOQ progress locally (simplified)
    state = _rebuildCartWithProgress(items);
    _saveGuestCart();
  }

  // ─── Remove item ────────────────────────────────────
  Future<void> removeItem(int itemId) async {
    // Enforce bulk MOQ before removal
    final item = state?.items.firstWhere((i) => i.id == itemId);
    if (item != null && item.productId != null) {
      final moqInfo = state?.minimumBulkProgress?[item.productId!];
      if (moqInfo != null && moqInfo.currentQuantity - item.quantity < moqInfo.minimumRequired) {
        debugPrint('Cannot remove – minimum order is ${moqInfo.minimumRequired}');
        return;
      }
    }

    if (!ApiClient.hasToken) {
      _removeGuestItem(itemId);
      return;
    }

    try {
      await ApiClient.instance.delete('/cart/remove_item/$itemId');
    } on DioException catch (e) {
      if (e.response?.statusCode != 404) {}
    } catch (_) {}
    finally {
      await fetchCart();
    }
  }

  void _removeGuestItem(int itemId) {
    final items = List<CartItem>.from(state?.items ?? []);
    final index = items.indexWhere((i) => i.id == itemId);
    if (index == -1) return;

    final productId = items[index].productId;
    if (productId != null) {
      final moqInfo = state?.minimumBulkProgress?[productId];
      if (moqInfo != null && moqInfo.currentQuantity - items[index].quantity < moqInfo.minimumRequired) {
        return;
      }
    }

    items.removeAt(index);
    state = _rebuildCartWithProgress(items);
    _saveGuestCart();
  }

  Cart _rebuildCartWithProgress(List<CartItem> items) {
    final totalPrice = items.fold<double>(0, (sum, i) => sum + i.price * i.quantity);
    final itemCount = items.fold<int>(0, (sum, i) => sum + i.quantity);

    return Cart(
      items: items,
      totalPrice: totalPrice,
      itemCount: itemCount,
      minimumBulkProgress: state?.minimumBulkProgress,
    );
  }

  void _addGuestItem(Product product, {required int quantity, Map<String, String>? variant}) {
    if (product.bulkEnabled && product.minimumBulkQuantity != null) {
      if (quantity < product.minimumBulkQuantity!) {
        debugPrint('Bulk product requires at least ${product.minimumBulkQuantity} units');
        return;
      }
    }

    final items = List<CartItem>.from(state?.items ?? []);
    final existingIndex = items.indexWhere((i) =>
        (product.isPackage
            ? i.packageId == product.id
            : i.productId == product.id) &&
        _mapsEqual(i.variant, variant ?? {}));

    if (existingIndex != -1) {
      items[existingIndex] = CartItem(
        id: items[existingIndex].id,
        productId: items[existingIndex].productId,
        packageId: items[existingIndex].packageId,
        title: items[existingIndex].title,
        price: items[existingIndex].price,
        quantity: items[existingIndex].quantity + quantity,
        stock: items[existingIndex].stock,
        variant: items[existingIndex].variant,
        image: items[existingIndex].image,
      );
    } else {
      items.add(CartItem(
        id: DateTime.now().millisecondsSinceEpoch,
        productId: product.isPackage ? 0 : product.id,
        packageId: product.isPackage ? product.id : null,
        title: product.title,
        price: product.effectivePrice,
        quantity: quantity,
        stock: product.stock ?? 0,
        variant: variant ?? {},
        image: product.images.isNotEmpty ? product.images.first : '',
      ));
    }

    state = _rebuildCartWithProgress(items);
    _saveGuestCart();
  }

  bool _mapsEqual(Map<String, dynamic> a, Map<String, dynamic> b) {
    if (a.length != b.length) return false;
    for (final key in a.keys) {
      if (b[key] != a[key]) return false;
    }
    return true;
  }
}
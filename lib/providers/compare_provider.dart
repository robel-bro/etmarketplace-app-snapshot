// 📁 lib/providers/compare_provider.dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../api/client.dart';
import '../models/product.dart';

class CompareNotifier extends StateNotifier<List<Product>> {
  final Map<int, Map<String, String>> _variantCache = {};

  CompareNotifier() : super([]);

  Future<void> fetchCompare() async {
    if (!ApiClient.hasToken) {
      state = [];
      _variantCache.clear();
      return;
    }
    try {
      final response = await ApiClient.instance.get('/comparisons');
      final List data = response.data is List
          ? response.data
          : (response.data['data'] ?? []);
      final List<Product> products = [];
      _variantCache.clear();
      for (final item in data) {
        final product = Product.fromJson(item);
        products.add(product);
        if (item['variant_attributes'] is Map) {
          _variantCache[product.id] = Map<String, String>.from(
            (item['variant_attributes'] as Map).map((k, v) => MapEntry(k.toString(), v.toString()))
          );
        }
      }
      state = products;
    } catch (_) {
      state = [];
      _variantCache.clear();
    }
  }

  Future<void> addProduct(Product product, {Map<String, String>? variant}) async {
    if (state.any((p) => p.id == product.id)) return;

    state = [...state, product];
    if (variant != null && variant.isNotEmpty) {
      _variantCache[product.id] = variant;
    }

    if (ApiClient.hasToken) {
      try {
        final payload = <String, dynamic>{
          'product_id': product.id,
        };
        if (variant != null && variant.isNotEmpty) {
          payload['variant'] = variant;   // ★ backend expects 'variant', not 'variant_attributes'
        }
        await ApiClient.instance.post('/comparisons', data: payload);
      } catch (_) {
        state = state.where((p) => p.id != product.id).toList();
        _variantCache.remove(product.id);
      }
    }
  }

  void removeProduct(int productId) {
    state = state.where((p) => p.id != productId).toList();
    _variantCache.remove(productId);
    if (ApiClient.hasToken) {
      ApiClient.instance.delete('/comparisons/$productId').catchError((_) {});
    }
  }

  void clear() {
    final ids = state.map((p) => p.id).toList();   // ★ copy before clearing
    state = [];
    _variantCache.clear();
    if (ApiClient.hasToken) {
      for (final id in ids) {
        ApiClient.instance.delete('/comparisons/$id').catchError((_) {});
      }
    }
  }

  bool contains(int productId) => state.any((p) => p.id == productId);
  Map<String, String>? getVariant(int productId) => _variantCache[productId];
}

final compareProvider =
    StateNotifierProvider<CompareNotifier, List<Product>>(
  (ref) => CompareNotifier(),
);
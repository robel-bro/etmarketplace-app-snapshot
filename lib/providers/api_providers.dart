import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../api/client.dart';
import '../models/category.dart';
import '../models/product.dart';

// Helper to extract data from various response formats
List<dynamic> _extractList(dynamic responseData) {
  if (responseData is List) return responseData;
  if (responseData is Map) {
    if (responseData.containsKey('data') && responseData['data'] is List) {
      return responseData['data'];
    }
    if (responseData.containsKey('items') && responseData['items'] is List) {
      return responseData['items'];
    }
  }
  return [];
}

// ------------------- Categories -------------------
final categoriesProvider = FutureProvider<List<Category>>((ref) async {
  try {
    final response = await ApiClient.instance.get('/categories');
    final data = _extractList(response.data);
    if (data.isNotEmpty) {
      return data.map((json) => Category.fromJson(json)).toList();
    }
    return [];
  } catch (e) {
    return [];
  }
});

// ------------------- Banners (with link field) -------------------
final bannersProvider = FutureProvider<List<Map<String, dynamic>>>((ref) async {
  try {
    final response = await ApiClient.instance.get('/homepage');
    final data = _extractList(response.data['hero_banners']);
    if (data.isNotEmpty) {
      return data.map((b) {
        return {
          'image_url': b['image_url']?.toString() ?? '',
          'title': b['title']?.toString() ?? '',
          'subtitle': b['subtitle']?.toString() ?? '',
          'link': b['link']?.toString() ?? '',
        };
      }).toList();
    }
    return [];
  } catch (e) {
    return [];
  }
});

// ------------------- Trending/Featured Products -------------------
final trendingProductsProvider = FutureProvider<List<Product>>((ref) async {
  try {
    final response = await ApiClient.instance.get('/products/featured');
    final data = _extractList(response.data);
    if (data.isNotEmpty) {
      return data.map((json) => Product.fromJson(json)).toList();
    }
    return [];
  } catch (e) {
    try {
      final response = await ApiClient.instance.get('/products', queryParameters: {'sort': 'popular'});
      final data = _extractList(response.data);
      if (data.isNotEmpty) {
        return data.map((json) => Product.fromJson(json)).toList();
      }
      return [];
    } catch (e) {
      return [];
    }
  }
});

// ------------------- Product Detail -------------------
final productProvider = FutureProvider.family<Product, int>((ref, id) async {
  final response = await ApiClient.instance.get('/products/$id');
  final productData = response.data['data'] ?? response.data;
  return Product.fromJson(productData);
});

// ------------------- Flash Deals -------------------
final flashDealsProvider = FutureProvider<List<Product>>((ref) async {
  try {
    final response = await ApiClient.instance.get('/deals/flash');
    final data = _extractList(response.data);
    if (data.isNotEmpty) {
      return data.map((json) => Product.fromJson(json)).toList();
    }
    return [];
  } catch (e) {
    return [];
  }
});

// ------------------- Hot Deals -------------------
final hotDealsProvider = FutureProvider<List<Product>>((ref) async {
  try {
    final response = await ApiClient.instance.get('/deals/hot');
    final data = _extractList(response.data);
    if (data.isNotEmpty) {
      return data.map((json) => Product.fromJson(json)).toList();
    }
    return [];
  } catch (e) {
    return [];
  }
});

// ------------------- Super Deals -------------------
final superDealsProvider = FutureProvider<List<Product>>((ref) async {
  try {
    final response = await ApiClient.instance.get('/deals/super');
    final data = _extractList(response.data);
    if (data.isNotEmpty) {
      return data.map((json) => Product.fromJson(json)).toList();
    }
    return [];
  } catch (e) {
    return [];
  }
});

// ------------------- Package Deals -------------------
final packageDealsProvider = FutureProvider<List<Product>>((ref) async {
  try {
    final response = await ApiClient.instance.get('/deals/package');
    final data = _extractList(response.data);
    if (data.isNotEmpty) {
      return data.map((json) => Product.fromJson(json)).toList();
    }
    return [];
  } catch (e) {
    return [];
  }
});

// ------------------- Collections -------------------
final collectionsProvider = FutureProvider<List<Product>>((ref) async {
  try {
    final response = await ApiClient.instance.get('/collections');
    final data = _extractList(response.data);
    if (data.isNotEmpty) {
      return data.map((json) => Product.fromJson(json)).toList();
    }
    return [];
  } catch (e) {
    return [];
  }
});
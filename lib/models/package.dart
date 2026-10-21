// lib/models/package.dart (hardened – safe parsing for all API responses)
import 'dart:convert';

class Package {
  final int id;
  final String name;
  final String? description;
  final double price;
  final double? originalPrice;
  final String? discountType;
  final double? discountValue;
  final int discountPercentage;
  final int? stock;
  final bool featured;
  final String status;
  final List<String> imageUrls;
  final List<int> imageIds;
  final List<String> videoUrls;
  final List<int> videoIds;
  final int itemsCount;
  final String? shippingType;
  final double? shippingValue;
  final bool sellerPaysShipping;
  final String? shippingSubsidyType;
  final double? shippingSubsidyValue;
  final List<String> features;
  final Map<String, dynamic>? vendor;
  final List<Map<String, dynamic>>? categories;
  final List<Map<String, dynamic>>? products;
  final double? rating;
  final int? reviewsCount;
  final String? vendorBadge;

  final bool bulkEnabled;
  final bool outOfStock;
  final bool freeDelivery;
  final String? deliveryLabel;
  final int? availableStock;
  final int? maxPossibleStock;

  Package({
    required this.id,
    required this.name,
    this.description,
    required this.price,
    this.originalPrice,
    this.discountType,
    this.discountValue,
    this.discountPercentage = 0,
    this.stock,
    this.featured = false,
    this.status = '',
    this.imageUrls = const [],
    this.imageIds = const [],
    this.videoUrls = const [],
    this.videoIds = const [],
    this.itemsCount = 0,
    this.shippingType,
    this.shippingValue,
    this.sellerPaysShipping = false,
    this.shippingSubsidyType,
    this.shippingSubsidyValue,
    this.features = const [],
    this.vendor,
    this.categories,
    this.products,
    this.rating,
    this.reviewsCount,
    this.vendorBadge,
    this.bulkEnabled = false,
    this.outOfStock = false,
    this.freeDelivery = false,
    this.deliveryLabel,
    this.availableStock,
    this.maxPossibleStock,
  });

  static double _parseDouble(dynamic value) {
    if (value == null) return 0.0;
    if (value is num) return value.toDouble();
    if (value is String) return double.tryParse(value) ?? 0.0;
    return 0.0;
  }

  static int _parseInt(dynamic value) {
    if (value == null) return 0;
    if (value is int) return value;
    if (value is double) return value.toInt();
    if (value is String) return int.tryParse(value) ?? 0;
    return 0;
  }

  static int? _parseIntOrNull(dynamic value) {
    if (value == null) return null;
    if (value is int) return value;
    if (value is double) return value.toInt();
    if (value is String) return int.tryParse(value);
    return null;
  }

  static double? _parseDoubleOrNull(dynamic value) {
    if (value == null) return null;
    if (value is num) return value.toDouble();
    if (value is String) return double.tryParse(value);
    return null;
  }

  static List<int> _parseIntList(dynamic value) {
    if (value is List) return value.map((e) => _parseInt(e)).toList();
    if (value is String) {
      try {
        final decoded = jsonDecode(value);
        if (decoded is List) return decoded.map((e) => _parseInt(e)).toList();
      } catch (_) {}
    }
    return [];
  }

  // Safe list of strings
  static List<String> _parseStringList(dynamic value) {
    if (value is List) {
      return value.map((e) => e?.toString() ?? '').where((s) => s.isNotEmpty).toList();
    }
    if (value is String) {
      try {
        final decoded = jsonDecode(value);
        if (decoded is List) {
          return decoded.map((e) => e?.toString() ?? '').where((s) => s.isNotEmpty).toList();
        }
        if (decoded is Map) {
          // Sometimes image_urls might be a map? unlikely but safe
          return const [];
        }
      } catch (_) {}
      // fallback: if plain string that isn't JSON, treat as single URL
      if (value.trim().isNotEmpty) return [value.trim()];
    }
    return [];
  }

  // Safe list of maps
  static List<Map<String, dynamic>>? _parseMapList(dynamic value) {
    if (value is List) {
      return value.map((e) {
        if (e is Map) return e.cast<String, dynamic>();
        if (e is String) {
          try {
            final decoded = jsonDecode(e);
            if (decoded is Map) return decoded.cast<String, dynamic>();
          } catch (_) {}
        }
        return <String, dynamic>{};
      }).toList();
    }
    if (value is String) {
      try {
        final decoded = jsonDecode(value);
        if (decoded is List) {
          return decoded.map((e) {
            if (e is Map) return e.cast<String, dynamic>();
            if (e is String) {
              try {
                final inner = jsonDecode(e);
                if (inner is Map) return inner.cast<String, dynamic>();
              } catch (_) {}
            }
            return <String, dynamic>{};
          }).toList();
        }
      } catch (_) {}
    }
    return null;
  }

  factory Package.fromJson(Map<String, dynamic> json) {
    // Vendor map can also come as string? unlikely but handle
    Map<String, dynamic>? vendorMap;
    final vendorRaw = json['vendor'];
    if (vendorRaw is Map) {
      vendorMap = vendorRaw.cast<String, dynamic>();
    } else if (vendorRaw is String) {
      try {
        final decoded = jsonDecode(vendorRaw);
        if (decoded is Map) vendorMap = decoded.cast<String, dynamic>();
      } catch (_) {}
    }

    final String? vendorBadge = (vendorMap?['badge'] ?? vendorMap?['membership_tier'])?.toString();

    return Package(
      id: _parseInt(json['id']),
      name: (json['title'] ?? json['name'] ?? '').toString(),
      description: json['description']?.toString(),
      price: _parseDouble(json['price']),
      originalPrice: _parseDoubleOrNull(json['original_price']),
      discountType: json['discount_type']?.toString(),
      discountValue: _parseDoubleOrNull(json['discount_value']),
      discountPercentage: _parseInt(json['discount_percentage']),
      stock: _parseIntOrNull(json['stock']),
      featured: json['featured'] == true,
      status: json['status']?.toString() ?? '',
      imageUrls: _parseStringList(json['image_urls']),
      imageIds: _parseIntList(json['image_ids']),
      videoUrls: _parseStringList(json['video_urls']),
      videoIds: _parseIntList(json['video_ids']),
      itemsCount: _parseInt(json['items_count']),
      shippingType: json['shipping_type']?.toString(),
      shippingValue: _parseDoubleOrNull(json['shipping_value']),
      sellerPaysShipping: json['seller_pays_shipping'] == true || json['seller_pays_shipping'] == 'true',
      shippingSubsidyType: json['shipping_subsidy_type']?.toString(),
      shippingSubsidyValue: _parseDoubleOrNull(json['shipping_subsidy_value']),
      features: _parseStringList(json['features']),
      vendor: vendorMap,
      categories: _parseMapList(json['categories']),
      products: _parseMapList(json['products']),
      rating: _parseDoubleOrNull(json['rating']),
      reviewsCount: _parseIntOrNull(json['reviews_count']),
      vendorBadge: vendorBadge,
      bulkEnabled: json['bulk_enabled'] == true || json['bulk_enabled'] == 'true',
      outOfStock: json['out_of_stock'] == true,
      freeDelivery: json['free_delivery'] == true,
      deliveryLabel: json['delivery_label']?.toString(),
      availableStock: _parseIntOrNull(json['available_stock']),
      maxPossibleStock: _parseIntOrNull(json['max_possible_stock']),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'description': description,
      'price': price,
      'original_price': originalPrice,
      'discount_type': discountType,
      'discount_value': discountValue,
      'discount_percentage': discountPercentage,
      'stock': stock,
      'featured': featured,
      'status': status,
      'image_urls': imageUrls,
      'image_ids': imageIds,
      'video_urls': videoUrls,
      'video_ids': videoIds,
      'items_count': itemsCount,
      'shipping_type': shippingType,
      'shipping_value': shippingValue,
      'seller_pays_shipping': sellerPaysShipping,
      'shipping_subsidy_type': shippingSubsidyType,
      'shipping_subsidy_value': shippingSubsidyValue,
      'features': features,
      'vendor': vendor,
      'categories': categories,
      'products': products,
      'rating': rating,
      'reviews_count': reviewsCount,
      'vendorBadge': vendorBadge,
      'bulk_enabled': bulkEnabled,
      'out_of_stock': outOfStock,
      'free_delivery': freeDelivery,
      'delivery_label': deliveryLabel,
      'available_stock': availableStock,
      'max_possible_stock': maxPossibleStock,
    };
  }
}
// lib/models/wishlist.dart
import 'dart:convert';

class WishlistItem {
  final int id;
  final int productId;
  final String title;
  final String? description;
  final double price;
  final double? effectivePrice;
  final double? originalPrice;
  final double? rating;
  final int reviewsCount;
  final int soldCount;
  final bool freeShipping;
  final int discount;
  final int stock;
  final List<String> imageUrls;
  final bool isFlashSale;
  final double? flashSalePrice;
  final DateTime? flashSaleEndsAt;
  final bool isSuperDeal;
  final double? superDealPrice;
  final DateTime? superDealEndsAt;
  final Map<String, dynamic>? category;
  final Map<String, dynamic>? vendor;
  final Map<String, dynamic> productAttributes;
  final List<Map<String, dynamic>> variants;
  final Map<String, String> variantAttributes;
  final String imageUrl;
  final bool bulkEnabled;
  final int? minimumBulkQuantity;

  WishlistItem({
    required this.id,
    required this.productId,
    required this.title,
    this.description,
    required this.price,
    this.effectivePrice,
    this.originalPrice,
    this.rating,
    this.reviewsCount = 0,
    this.soldCount = 0,
    this.freeShipping = false,
    this.discount = 0,
    this.stock = 0,
    this.imageUrls = const [],
    this.isFlashSale = false,
    this.flashSalePrice,
    this.flashSaleEndsAt,
    this.isSuperDeal = false,
    this.superDealPrice,
    this.superDealEndsAt,
    this.category,
    this.vendor,
    this.productAttributes = const {},
    this.variants = const [],
    this.variantAttributes = const {},
    this.imageUrl = '',
    this.bulkEnabled = false,
    this.minimumBulkQuantity,
  });

  // Safe numeric parsers
  static double _toDouble(dynamic value) {
    if (value == null) return 0.0;
    if (value is double) return value;
    if (value is int) return value.toDouble();
    if (value is String) return double.tryParse(value) ?? 0.0;
    return 0.0;
  }

  static int _toInt(dynamic value) {
    if (value == null) return 0;
    if (value is int) return value;
    if (value is String) return int.tryParse(value) ?? 0;
    return 0;
  }

  static bool _toBool(dynamic value) {
    if (value is bool) return value;
    if (value is String) return value.toLowerCase() == 'true';
    return false;
  }

  static List<String> _toImageList(dynamic raw) {
    if (raw == null) return [];
    if (raw is List) return raw.map((e) => e.toString()).toList();
    if (raw is String) return [raw];
    return [];
  }

  static DateTime? _toDateTime(dynamic value) {
    if (value == null) return null;
    if (value is DateTime) return value;
    return DateTime.tryParse(value.toString());
  }

  factory WishlistItem.fromJson(Map<String, dynamic> json) {
    final rawImages = json['image_urls'] ?? json['image_url'] ?? json['images'];
    final imageUrls = _toImageList(rawImages);
    final primaryImage = imageUrls.isNotEmpty ? imageUrls.first : (json['image_url']?.toString() ?? '');

    Map<String, dynamic>? safeMap(dynamic value) {
      if (value is Map<String, dynamic>) return value;
      if (value is Map) return value.map((k, v) => MapEntry(k.toString(), v));
      return null;
    }

    List<Map<String, dynamic>> safeVariants(dynamic value) {
      if (value is List) {
        return value.map((e) {
          if (e is Map<String, dynamic>) return e;
          if (e is Map) return e.map((k, v) => MapEntry(k.toString(), v));
          return <String, dynamic>{};
        }).toList();
      }
      return [];
    }

    Map<String, String> safeVariantAttrs(dynamic value) {
      if (value is Map) {
        return value.map((k, v) => MapEntry(k.toString(), v.toString()));
      }
      return {};
    }

    return WishlistItem(
      id: _toInt(json['id']),
      productId: _toInt(json['product_id']),
      title: json['title']?.toString() ?? '',
      description: json['description']?.toString(),
      price: _toDouble(json['price']),
      effectivePrice: json['effective_price'] != null ? _toDouble(json['effective_price']) : null,
      originalPrice: json['original_price'] != null ? _toDouble(json['original_price']) : null,
      rating: json['rating'] != null ? _toDouble(json['rating']) : null,
      reviewsCount: _toInt(json['reviews_count']),
      soldCount: _toInt(json['sold_count']),
      freeShipping: _toBool(json['free_shipping']),
      discount: _toInt(json['discount']),
      stock: _toInt(json['stock']),
      imageUrls: imageUrls,
      isFlashSale: _toBool(json['is_flash_sale']),
      flashSalePrice: json['flash_sale_price'] != null ? _toDouble(json['flash_sale_price']) : null,
      flashSaleEndsAt: _toDateTime(json['flash_sale_ends_at']),
      isSuperDeal: _toBool(json['is_super_deal']),
      superDealPrice: json['super_deal_price'] != null ? _toDouble(json['super_deal_price']) : null,
      superDealEndsAt: _toDateTime(json['super_deal_ends_at']),
      category: safeMap(json['category']),
      vendor: safeMap(json['vendor']),
      productAttributes: safeMap(json['product_attributes']) ?? {},
      variants: safeVariants(json['variants']),
      variantAttributes: safeVariantAttrs(json['variant_attributes']),
      imageUrl: primaryImage,
      bulkEnabled: _toBool(json['bulk_enabled']),
      minimumBulkQuantity: json['minimum_bulk_quantity'] != null ? _toInt(json['minimum_bulk_quantity']) : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'product_id': productId,
      'title': title,
      'description': description,
      'price': price,
      'effective_price': effectivePrice,
      'original_price': originalPrice,
      'rating': rating,
      'reviews_count': reviewsCount,
      'sold_count': soldCount,
      'free_shipping': freeShipping,
      'discount': discount,
      'stock': stock,
      'image_urls': imageUrls,
      'image_url': imageUrl,
      'is_flash_sale': isFlashSale,
      'flash_sale_price': flashSalePrice,
      'flash_sale_ends_at': flashSaleEndsAt?.toIso8601String(),
      'is_super_deal': isSuperDeal,
      'super_deal_price': superDealPrice,
      'super_deal_ends_at': superDealEndsAt?.toIso8601String(),
      'category': category,
      'vendor': vendor,
      'product_attributes': productAttributes,
      'variants': variants,
      'variant_attributes': variantAttributes,
      'bulk_enabled': bulkEnabled,
      'minimum_bulk_quantity': minimumBulkQuantity,
    };
  }
}
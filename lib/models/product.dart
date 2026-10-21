// notepad++ C:\Users\hp\et_marketplace_app\lib\models\product.dart

import 'package:flutter/foundation.dart';
import 'vendor.dart';

class Product {
  final int id;
  final String title;
  final double price;
  final double? originalPrice;
  final String imageUrl;
  final double rating;
  final int reviewsCount;
  final int soldCount;

  final bool freeShipping;
  final int discountPercentage;
  final int? sellerId;
  final String? sellerName;
  final String? sellerAvatar;
  final List<String> thumbnailUrls;
  final List<String> images;
  final String? taxInfo;
  final Map<String, dynamic> attributes;
  final String? shippingInfo;
  final Map<String, String> specifications;
  final String? description;

  final int? stock; // null = unlimited
  final int? categoryId;
  final Map<String, dynamic> productAttributes;

  final bool sellerPaysShipping;
  final String? shippingSubsidyType;
  final double? shippingSubsidyValue;

  final double effectivePrice;

  final List<String> videoUrls;
  final List<Map<String, dynamic>> variants;
  final bool isPackage;
  final String status;
  final String? discountType;
  final double? discountValue;

  final bool isFlashSale;
  final DateTime? flashSaleEndsAt;
  final double? flashSalePrice;
  final bool isSuperDeal;
  final DateTime? superDealEndsAt;
  final double? superDealPrice;

  final bool isHotDeal;
  final bool isTrending;

  final bool vendorAcceptingOrders;
  final DateTime? vendorReopenAt;
  final String? vendorBusinessName;
  final double vendorRating;
  final int vendorProductsCount;

  final bool bulkEnabled;
  final int? minimumBulkQuantity;
  final int? maxQuantityPerDay;
  final int? remainingDailyQuantity;

  final bool orderable;
  final String? unavailableReason;

  final double? weightKg;
  final double? lengthCm;
  final double? widthCm;
  final double? heightCm;

  final int? packageItemCount;
  final Vendor? vendor;

  final bool outOfStock;

  // New fields matching backend
  final bool freeDelivery;
  final String? deliveryLabel;
  final int? availableStock;
  final String? stockDisplay;   // "Unlimited" or the numeric string
  final bool hasVariants;       // true if product has real variant attributes

  Product({
    required this.id,
    required this.title,
    required this.price,
    this.originalPrice,
    required this.imageUrl,
    required this.rating,
    required this.reviewsCount,
    required this.soldCount,
    required this.freeShipping,
    this.discountPercentage = 0,
    this.sellerId,
    this.sellerName,
    this.sellerAvatar,
    this.thumbnailUrls = const [],
    this.images = const [],
    this.taxInfo,
    this.attributes = const {},
    this.shippingInfo,
    this.specifications = const {},
    this.description,
    this.stock,
    this.categoryId,
    this.productAttributes = const {},
    this.sellerPaysShipping = false,
    this.shippingSubsidyType,
    this.shippingSubsidyValue,
    required this.effectivePrice,
    this.videoUrls = const [],
    this.variants = const [],
    this.isPackage = false,
    this.status = 'active',
    this.discountType,
    this.discountValue,
    this.isFlashSale = false,
    this.flashSaleEndsAt,
    this.flashSalePrice,
    this.isSuperDeal = false,
    this.superDealEndsAt,
    this.superDealPrice,
    this.isHotDeal = false,
    this.isTrending = false,
    this.vendorAcceptingOrders = true,
    this.vendorReopenAt,
    this.vendorBusinessName,
    this.vendorRating = 0.0,
    this.vendorProductsCount = 0,
    this.bulkEnabled = false,
    this.minimumBulkQuantity,
    this.maxQuantityPerDay,
    this.remainingDailyQuantity,
    this.orderable = true,
    this.unavailableReason,
    this.weightKg,
    this.lengthCm,
    this.widthCm,
    this.heightCm,
    this.packageItemCount,
    this.vendor,
    this.outOfStock = false,
    this.freeDelivery = false,
    this.deliveryLabel,
    this.availableStock,
    this.stockDisplay,
    this.hasVariants = false,
  });

  List<String> get imageUrls => images;

  List<String> get colors =>
      (attributes['Color'] as List?)?.cast<String>() ?? [];
  List<String> get sizes =>
      (attributes['Size'] as List?)?.cast<String>() ?? [];

  static int _parseInt(dynamic value, {int defaultValue = 0}) {
    if (value == null) return defaultValue;
    if (value is int) return value;
    if (value is double) return value.toInt();
    if (value is String) {
      final d = double.tryParse(value);
      return d?.toInt() ?? defaultValue;
    }
    return defaultValue;
  }

  static double _parseDouble(dynamic value, {double defaultValue = 0.0}) {
    if (value == null) return defaultValue;
    if (value is double) return value;
    if (value is int) return value.toDouble();
    if (value is String) return double.tryParse(value) ?? defaultValue;
    return defaultValue;
  }

  static double? _parseOriginalPrice(dynamic value) {
    if (value == null) return null;
    double parsed;
    if (value is double) { parsed = value; }
    else if (value is int) { parsed = value.toDouble(); }
    else if (value is String) { parsed = double.tryParse(value) ?? 0.0; }
    else { return null; }
    return parsed > 0 ? parsed : null;
  }

  static int? _parseStock(dynamic value) {
    if (value == null) return null;
    if (value is int) return value;
    if (value is double) return value.toInt();
    if (value is String) {
      final d = double.tryParse(value);
      return d?.toInt();
    }
    return null;
  }

  factory Product.fromJson(Map<String, dynamic> json) {
    String _extractMainImage() {
      if (json['image_url'] != null) return json['image_url'].toString();
      if (json['imageUrl'] != null) return json['imageUrl'].toString();
      if (json['image'] != null) return json['image'].toString();
      if (json['thumbnail'] != null) return json['thumbnail'].toString();
      if (json['image'] is Map) {
        final img = json['image'] as Map<String, dynamic>;
        if (img['url'] != null) return img['url'].toString();
        if (img['src'] != null) return img['src'].toString();
      }
      if (json['image_urls'] is List) {
        final list = json['image_urls'] as List;
        if (list.isNotEmpty) {
          final first = list.first;
          if (first is String) return first;
          if (first is Map) {
            if (first['url'] != null) return first['url'].toString();
            if (first['src'] != null) return first['src'].toString();
          }
        }
      }
      if (json['images'] is List) {
        final list = json['images'] as List;
        if (list.isNotEmpty) {
          final first = list.first;
          if (first is String) return first;
          if (first is Map) {
            if (first['url'] != null) return first['url'].toString();
            if (first['src'] != null) return first['src'].toString();
          }
        }
      }
      if (json['media'] is List) {
        for (var m in json['media']) {
          if (m is Map) {
            if (m['url'] != null) return m['url'].toString();
            if (m['src'] != null) return m['src'].toString();
          }
        }
      }
      return '';
    }

    List<String> _extractImageList() {
      final List<String> result = [];
      void addItem(dynamic item) {
        if (item is String) result.add(item);
        else if (item is Map) {
          if (item['url'] != null) result.add(item['url'].toString());
          else if (item['src'] != null) result.add(item['src'].toString());
        }
      }
      if (json['image_urls'] is List) for (var item in json['image_urls']) addItem(item);
      if (result.isEmpty && json['images'] is List) for (var item in json['images']) addItem(item);
      if (result.isEmpty && json['image_gallery'] is List) for (var item in json['image_gallery']) result.add(item.toString());
      if (result.isEmpty && json['gallery'] is List) for (var item in json['gallery']) {
        if (item is String) result.add(item);
        else if (item is Map && item['url'] != null) result.add(item['url'].toString());
      }
      return result;
    }

    List<String> _extractThumbnails() {
      if (json['thumbnail_urls'] is List) return (json['thumbnail_urls'] as List).map((e) => e.toString()).toList();
      if (json['thumbnails'] is List) return (json['thumbnails'] as List).map((e) => e.toString()).toList();
      return [];
    }

    Map<String, dynamic> _extractAttributes() {
      final attrs = <String, dynamic>{};
      if (json['attributes'] is Map) (json['attributes'] as Map).forEach((k, v) => attrs[k.toString()] = v);
      if (json['variants'] is Map) (json['variants'] as Map).forEach((k, v) => attrs[k.toString()] = v);
      if (json['options'] is Map) (json['options'] as Map).forEach((k, v) => attrs[k.toString()] = v);
      if (json['colors'] is List) attrs['Color'] = json['colors'];
      if (json['sizes'] is List) attrs['Size'] = json['sizes'];
      return attrs;
    }

    List<Map<String, dynamic>> _extractVariants() {
      if (json['variants'] is List) {
        return (json['variants'] as List).map((e) {
          if (e is Map<String, dynamic>) {
            final map = Map<String, dynamic>.from(e);
            map['price'] = _parseDouble(map['price']);
            map['stock'] = _parseInt(map['stock']);
            return map;
          }
          return <String, dynamic>{};
        }).toList();
      }
      return [];
    }

    List<String> _extractVideoUrls() {
      if (json['video_urls'] is List) return (json['video_urls'] as List).map((e) => e.toString()).toList();
      return [];
    }

    int? _extractSellerId() {
      if (json['vendor'] is Map) return _parseInt((json['vendor'] as Map)['id']);
      if (json['seller_id'] != null) return _parseInt(json['seller_id']);
      if (json['sellerId'] != null) return _parseInt(json['sellerId']);
      if (json['seller'] is Map) return _parseInt((json['seller'] as Map)['id']);
      if (json['shop'] is Map) return _parseInt((json['shop'] as Map)['id']);
      return null;
    }

    String? _extractSellerName() {
      if (json['vendor'] is Map) return (json['vendor'] as Map)['business_name']?.toString();
      if (json['seller_name'] != null) return json['seller_name'].toString();
      if (json['sellerName'] != null) return json['sellerName'].toString();
      if (json['seller'] is Map) return (json['seller'] as Map)['name']?.toString();
      if (json['shop'] is Map) return (json['shop'] as Map)['name']?.toString();
      return null;
    }

    String? _extractSellerAvatar() {
      if (json['vendor'] is Map) {
        final vendor = json['vendor'] as Map<String, dynamic>;
        return vendor['logo_url']?.toString() ?? vendor['avatar']?.toString();
      }
      if (json['seller_avatar'] != null) return json['seller_avatar'].toString();
      if (json['sellerAvatar'] != null) return json['sellerAvatar'].toString();
      if (json['seller'] is Map) {
        final seller = json['seller'] as Map<String, dynamic>;
        return seller['avatar']?.toString() ?? seller['image']?.toString();
      }
      if (json['shop'] is Map) {
        final shop = json['shop'] as Map<String, dynamic>;
        return shop['avatar']?.toString() ?? shop['image']?.toString();
      }
      return null;
    }

    Map<String, String> _extractSpecifications() {
      final result = <String, String>{};
      if (json['specifications'] is Map) (json['specifications'] as Map).forEach((k, v) => result[k.toString()] = v.toString());
      if (json['specs'] is Map) (json['specs'] as Map).forEach((k, v) => result[k.toString()] = v.toString());
      if (json['product_attributes'] is List) {
        for (var attr in json['product_attributes']) {
          if (attr is Map) {
            final key = attr['name']?.toString() ?? attr['key']?.toString();
            final value = attr['value']?.toString();
            if (key != null && value != null) result[key] = value;
          }
        }
      }
      return result;
    }

    int? _extractStock() => _parseStock(json['stock']);

    int? _extractCategoryId() {
      if (json['category'] is Map) return _parseInt((json['category'] as Map)['id']);
      if (json['category_id'] != null) return _parseInt(json['category_id']);
      return null;
    }

    Map<String, dynamic> _extractProductAttributes() {
      if (json['product_attributes'] is Map)
        return Map<String, dynamic>.from(json['product_attributes'] as Map);
      return {};
    }

    double _computeEffectivePrice() {
      final ep = json['effective_price'];
      if (ep != null) { final parsed = _parseDouble(ep); if (parsed > 0) return parsed; }
      final variantsList = json['variants'];
      if (variantsList is List && variantsList.isNotEmpty) {
        for (final v in variantsList) {
          if (v is Map) { final p = _parseDouble(v['price']); if (p > 0) return p; }
        }
      }
      return _parseDouble(json['price']);
    }

    bool _extractVendorAcceptingOrders() {
      final vendor = json['vendor'];
      if (vendor is Map) {
        final val = vendor['accepting_orders'];
        if (val == null) return true;
        if (val is bool) return val;
        if (val is String) return val.toLowerCase() == 'true';
      }
      return true;
    }

    DateTime? _extractVendorReopenAt() {
      final vendor = json['vendor'];
      if (vendor is Map) {
        final raw = vendor['reopen_at'];
        if (raw != null) return DateTime.tryParse(raw.toString())?.toLocal();
      }
      return null;
    }

    String? _extractVendorBusinessName() {
      final vendor = json['vendor'];
      if (vendor is Map) return vendor['business_name']?.toString();
      return null;
    }

    double _extractVendorRating() {
      final vendor = json['vendor'];
      if (vendor is Map) return _parseDouble(vendor['rating'], defaultValue: 4.5);
      return 4.5;
    }

    int _extractVendorProductsCount() {
      final vendor = json['vendor'];
      if (vendor is Map) return _parseInt(vendor['products_count']);
      return 0;
    }

    double? _extractFlashSalePrice() {
      final val = json['flash_sale_price'];
      if (val == null) return null;
      return _parseDouble(val);
    }

    double? _extractSuperDealPrice() {
      final val = json['super_deal_price'];
      if (val == null) return null;
      return _parseDouble(val);
    }

    int? _extractPackageItemCount() {
      final count = json['item_count'] ?? json['products_count'];
      if (count == null) return null;
      return _parseInt(count);
    }

    bool _extractFreeDelivery() {
      if (json['free_delivery'] is bool) return json['free_delivery'];
      final free = json['free_shipping'] as bool? ?? false;
      final sellerPays = json['seller_pays_shipping'] == true || json['seller_pays_shipping'] == 'true';
      final subsidyType = json['shipping_subsidy_type']?.toString();
      return free || (sellerPays && subsidyType == 'full');
    }

    String? _extractDeliveryLabel() {
      return json['delivery_label']?.toString();
    }

    int? _extractAvailableStock() {
      if (json['available_stock'] != null) {
        return _parseInt(json['available_stock']);
      }
      return _parseStock(json['stock']);
    }

    String? _extractStockDisplay() {
      return json['stock_display']?.toString();
    }

    bool _extractHasVariants() {
      return json['has_variants'] == true || json['has_variants'] == 'true';
    }

    final isFlash = json['is_flash_sale'] == true || json['is_flash_sale'] == 'true';
    DateTime? flashEnds;
    if (json['flash_sale_ends_at'] != null) flashEnds = DateTime.tryParse(json['flash_sale_ends_at'].toString())?.toLocal();

    final isSuper = json['is_super_deal'] == true || json['is_super_deal'] == 'true';
    DateTime? superEnds;
    if (json['super_deal_ends_at'] != null) superEnds = DateTime.tryParse(json['super_deal_ends_at'].toString())?.toLocal();

    final isHot = json['is_hot_deal'] == true || json['is_hot_deal'] == 'true';
    final isTrending = json['is_trending'] == true || json['is_trending'] == 'true';

    final bulkEnabled = json['bulk_enabled'] == true || json['bulk_enabled'] == 'true';
    final int? minBulkQty = json['minimum_bulk_quantity'] != null ? _parseInt(json['minimum_bulk_quantity']) : null;
    final int? maxQtyPerDay = json['max_quantity_per_day'] != null ? _parseInt(json['max_quantity_per_day']) : null;
    final int? remainingDaily = json['remaining_daily_quantity'] != null ? _parseInt(json['remaining_daily_quantity']) : null;

    final orderable = json['orderable'] ?? true;
    final String? unavailableReason = json['unavailable_reason']?.toString();

    final double? weightKg = json['weight_kg'] != null ? _parseDouble(json['weight_kg']) : null;
    final double? lengthCm = json['length_cm'] != null ? _parseDouble(json['length_cm']) : null;
    final double? widthCm = json['width_cm'] != null ? _parseDouble(json['width_cm']) : null;
    final double? heightCm = json['height_cm'] != null ? _parseDouble(json['height_cm']) : null;

    Vendor? parsedVendor;
    if (json['vendor'] != null && json['vendor'] is Map) {
      parsedVendor = Vendor.fromJson(Map<String, dynamic>.from(json['vendor'] as Map));
    }

    final outOfStock = json['out_of_stock'] == true;

    final freeDelivery = _extractFreeDelivery();
    final String? deliveryLabel = _extractDeliveryLabel();
    final int? availableStock = _extractAvailableStock();
    final String? stockDisplay = _extractStockDisplay();
    final bool hasVariants = _extractHasVariants();

    return Product(
      id: _parseInt(json['id']),
      title: json['title'] as String? ?? json['name'] as String? ?? '',
      price: _parseDouble(json['price']),
      originalPrice: _parseOriginalPrice(json['original_price'] ?? json['originalPrice']),
      imageUrl: _extractMainImage(),
      rating: _parseDouble(json['rating']),
      reviewsCount: _parseInt(json['reviews_count'] ?? json['reviewsCount']),
      soldCount: _parseInt(json['sold_count'] ?? json['soldCount']),
      freeShipping: json['free_shipping'] as bool? ?? json['freeShipping'] as bool? ?? false,
      discountPercentage: _parseInt(json['discount_percentage'] ?? json['discountPercentage'] ?? json['discount']),
      sellerId: _extractSellerId(),
      sellerName: _extractSellerName(),
      sellerAvatar: _extractSellerAvatar(),
      thumbnailUrls: _extractThumbnails(),
      images: _extractImageList(),
      taxInfo: json['tax_info']?.toString() ?? json['taxInfo']?.toString(),
      attributes: _extractAttributes(),
      shippingInfo: json['shipping_info']?.toString() ?? json['shippingInfo']?.toString(),
      specifications: _extractSpecifications(),
      description: json['description']?.toString(),
      stock: _extractStock(),
      categoryId: _extractCategoryId(),
      productAttributes: _extractProductAttributes(),
      sellerPaysShipping: json['seller_pays_shipping'] == true || json['seller_pays_shipping'] == 'true',
      shippingSubsidyType: json['shipping_subsidy_type']?.toString(),
      shippingSubsidyValue: _parseDouble(json['shipping_subsidy_value']),
      effectivePrice: _computeEffectivePrice(),
      videoUrls: _extractVideoUrls(),
      variants: _extractVariants(),
      isPackage: json['is_package'] == true || json['isPackage'] == true,
      status: json['status']?.toString() ?? 'active',
      discountType: json['discount_type']?.toString() ?? json['discountType']?.toString(),
      discountValue: _parseDouble(json['discount_value'] ?? json['discountValue']),
      isFlashSale: isFlash,
      flashSaleEndsAt: flashEnds,
      flashSalePrice: _extractFlashSalePrice(),
      isSuperDeal: isSuper,
      superDealEndsAt: superEnds,
      superDealPrice: _extractSuperDealPrice(),
      isHotDeal: isHot,
      isTrending: isTrending,
      vendorAcceptingOrders: _extractVendorAcceptingOrders(),
      vendorReopenAt: _extractVendorReopenAt(),
      vendorBusinessName: _extractVendorBusinessName(),
      vendorRating: _extractVendorRating(),
      vendorProductsCount: _extractVendorProductsCount(),
      bulkEnabled: bulkEnabled,
      minimumBulkQuantity: minBulkQty,
      maxQuantityPerDay: maxQtyPerDay,
      remainingDailyQuantity: remainingDaily,
      orderable: orderable,
      unavailableReason: unavailableReason,
      weightKg: weightKg,
      lengthCm: lengthCm,
      widthCm: widthCm,
      heightCm: heightCm,
      packageItemCount: _extractPackageItemCount(),
      vendor: parsedVendor,
      outOfStock: outOfStock,
      freeDelivery: freeDelivery,
      deliveryLabel: deliveryLabel,
      availableStock: availableStock,
      stockDisplay: stockDisplay,
      hasVariants: hasVariants,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'price': price,
      'original_price': originalPrice,
      'image_url': imageUrl,
      'rating': rating,
      'reviews_count': reviewsCount,
      'sold_count': soldCount,
      'free_shipping': freeShipping,
      'discount_percentage': discountPercentage,
      'seller_id': sellerId,
      'seller_name': sellerName,
      'seller_avatar': sellerAvatar,
      'thumbnail_urls': thumbnailUrls,
      'images': images,
      'tax_info': taxInfo,
      'attributes': attributes,
      'shipping_info': shippingInfo,
      'specifications': specifications,
      'description': description,
      'stock': stock,
      'category_id': categoryId,
      'product_attributes': productAttributes,
      'seller_pays_shipping': sellerPaysShipping,
      'shipping_subsidy_type': shippingSubsidyType,
      'shipping_subsidy_value': shippingSubsidyValue,
      'effective_price': effectivePrice,
      'video_urls': videoUrls,
      'variants': variants,
      'is_package': isPackage,
      'status': status,
      'discount_type': discountType,
      'discount_value': discountValue,
      'is_flash_sale': isFlashSale,
      'flash_sale_ends_at': flashSaleEndsAt?.toIso8601String(),
      'flash_sale_price': flashSalePrice,
      'is_super_deal': isSuperDeal,
      'super_deal_ends_at': superDealEndsAt?.toIso8601String(),
      'super_deal_price': superDealPrice,
      'is_hot_deal': isHotDeal,
      'is_trending': isTrending,
      'vendor_accepting_orders': vendorAcceptingOrders,
      'vendor_reopen_at': vendorReopenAt?.toIso8601String(),
      'vendor_business_name': vendorBusinessName,
      'vendor_rating': vendorRating,
      'vendor_products_count': vendorProductsCount,
      'bulk_enabled': bulkEnabled,
      'minimum_bulk_quantity': minimumBulkQuantity,
      'max_quantity_per_day': maxQuantityPerDay,
      'remaining_daily_quantity': remainingDailyQuantity,
      'orderable': orderable,
      'unavailable_reason': unavailableReason,
      'weight_kg': weightKg,
      'length_cm': lengthCm,
      'width_cm': widthCm,
      'height_cm': heightCm,
      'package_item_count': packageItemCount,
      'vendor': vendor?.toJson(),
      'out_of_stock': outOfStock,
      'free_delivery': freeDelivery,
      'delivery_label': deliveryLabel,
      'available_stock': availableStock,
      'stock_display': stockDisplay,
      'has_variants': hasVariants,
    };
  }

  // ─────────────────────────────────────────────────────────────
  // ★ Professional stock / daily‑limit helpers
  // ─────────────────────────────────────────────────────────────

  /// Returns the maximum purchasable quantity for a given variant selection,
  /// respecting both the variant's physical stock and the product‑level daily limit.
  /// Returns `null` if truly unlimited (no physical cap and no daily limit).
  int? getMaxQuantityForVariant(Map<String, dynamic>? variantAttributes) {
    // 1. Physical limit
    int? physicalLimit;
    if (variantAttributes != null && variantAttributes.isNotEmpty) {
      final variant = _findVariant(variantAttributes);
      if (variant != null && variant['stock'] != null) {
        physicalLimit = (variant['stock'] as num).toInt();
      } else {
        physicalLimit = availableStock;
      }
    } else {
      // No variant – use backend-computed availableStock, which already respects the daily cap
      physicalLimit = availableStock;
    }

    // If physical is truly unlimited, return null
    if (physicalLimit == null) return null;

    // 2. Apply the product‑level daily cap (stronger than variant stock)
    if (remainingDailyQuantity != null && remainingDailyQuantity! < physicalLimit) {
      return remainingDailyQuantity;
    }
    return physicalLimit;
  }

  /// Internal helper – finds a variant by its attributes.
  Map<String, dynamic>? _findVariant(Map<String, dynamic> attributes) {
    if (attributes.isEmpty || variants.isEmpty) return null;
    for (final v in variants) {
      final attrs = v['attributes'] as Map<String, dynamic>? ?? {};
      if (attributes.entries.every((e) => attrs[e.key] == e.value)) {
        return v;
      }
    }
    return null;
  }
}
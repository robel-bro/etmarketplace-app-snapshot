class PackageDetail {
  final int id;
  final String name;
  final String? description;
  final double price;
  final double? originalPrice;
  final String? discountType;
  final double? discountValue;
  final DateTime? discountStart;
  final DateTime? discountEnd;
  final int? itemsCount;
  final List<String> imageUrls;
  final String? shippingType;
  final double? shippingValue;
  final List<String> features;
  final Map<String, dynamic>? vendor;
  final List<Map<String, dynamic>> categories;
  final List<Map<String, dynamic>> products;

  PackageDetail({
    required this.id,
    required this.name,
    this.description,
    required this.price,
    this.originalPrice,
    this.discountType,
    this.discountValue,
    this.discountStart,
    this.discountEnd,
    this.itemsCount,
    required this.imageUrls,
    this.shippingType,
    this.shippingValue,
    this.features = const [],
    this.vendor,
    this.categories = const [],
    this.products = const [],
  });

  static double? _parseDouble(dynamic value) {
    if (value == null) return null;
    if (value is double) return value;
    if (value is int) return value.toDouble();
    if (value is String) return double.tryParse(value);
    return null;
  }

  static int? _parseInt(dynamic value) {
    if (value == null) return null;
    if (value is int) return value;
    if (value is double) return value.toInt();
    if (value is String) return int.tryParse(value);
    return null;
  }

  factory PackageDetail.fromJson(Map<String, dynamic> json) {
    final List<dynamic> images = json['image_urls'] ?? [];
    return PackageDetail(
      id: _parseInt(json['id']) ?? 0,
      name: json['name'] ?? '',
      description: json['description'],
      price: _parseDouble(json['price']) ?? 0.0,
      originalPrice: _parseDouble(json['original_price']),
      discountType: json['discount_type'],
      discountValue: _parseDouble(json['discount_value']),
      discountStart: json['discount_start'] != null ? DateTime.tryParse(json['discount_start'].toString()) : null,
      discountEnd: json['discount_end'] != null ? DateTime.tryParse(json['discount_end'].toString()) : null,
      itemsCount: _parseInt(json['items_count']),
      imageUrls: images.map((e) => e.toString()).toList(),
      shippingType: json['shipping_type'],
      shippingValue: _parseDouble(json['shipping_value']),
      features: (json['features'] as List?)?.map((e) => e.toString()).toList() ?? [],
      vendor: json['vendor'] as Map<String, dynamic>?,
      categories: (json['categories'] as List?)
              ?.map((e) => Map<String, dynamic>.from(e as Map))
              .toList() ??
          [],
      products: (json['products'] as List?)
              ?.map((e) => Map<String, dynamic>.from(e as Map))
              .toList() ??
          [],
    );
  }
}
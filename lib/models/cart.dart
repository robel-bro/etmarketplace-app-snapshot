// lib/models/cart.dart

class Cart {
  final List<CartItem> items;
  final double totalPrice;
  final int itemCount;
  final Map<int, BulkProgress>? minimumBulkProgress;

  Cart({
    required this.items,
    this.totalPrice = 0,
    this.itemCount = 0,
    this.minimumBulkProgress,
  });

  factory Cart.fromJson(Map<String, dynamic> json) {
    final itemsList = (json['items'] as List?) ?? [];
    final progressRaw = json['minimumBulkProgress'] as Map<String, dynamic>?;
    final progress = progressRaw?.map(
      (k, v) => MapEntry(int.parse(k), BulkProgress.fromJson(v as Map<String, dynamic>)),
    );

    return Cart(
      items: itemsList.map((item) => CartItem.fromJson(item)).toList(),
      totalPrice: _parseDouble(json['total']),
      itemCount: _parseInt(json['item_count']),
      minimumBulkProgress: progress,
    );
  }

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
}

class CartItem {
  final int id;
  final int productId;
  final int? packageId;
  final String title;
  final double price;
  final double basePrice;
  final double originalPrice;
  final int quantity;
  final int stock;
  final Map<String, dynamic> variant;
  final String image;
  final bool bulkEnabled;
  final int? minimumBulkQuantity;
  final int? maxQuantityPerDay;
  final int? remainingDailyQuantity;
  final DateTime? expiresAt;
  final int? expiresInSeconds;

  CartItem({
    required this.id,
    required this.productId,
    this.packageId,
    required this.title,
    required this.price,
    this.basePrice = 0.0,
    double? originalPrice,
    required this.quantity,
    this.stock = 0,
    this.variant = const {},
    this.image = '',
    this.bulkEnabled = false,
    this.minimumBulkQuantity,
    this.maxQuantityPerDay,
    this.remainingDailyQuantity,
    this.expiresAt,
    this.expiresInSeconds,
  }) : originalPrice = originalPrice ?? basePrice;

  String get imageUrl => image;
  int get effectiveId => packageId ?? productId;
  bool get isPackage => packageId != null && packageId! > 0;
  bool get hasDiscount => basePrice > 0 && basePrice > price;
  double get unitDiscount => hasDiscount ? basePrice - price : 0.0;
  double get totalDiscount => unitDiscount * quantity;

  factory CartItem.fromJson(Map<String, dynamic> json) {
    final productId = json['productId'] != null ? Cart._parseInt(json['productId']) : 0;
    final packageId = json['packageId'] != null ? Cart._parseInt(json['packageId']) : null;
    final basePrice = Cart._parseDouble(json['base_price'] ?? json['original_price']);
    final originalPrice = Cart._parseDouble(json['original_price'] ?? json['base_price']);

    return CartItem(
      id: Cart._parseInt(json['id']),
      productId: productId,
      packageId: packageId,
      title: json['title'] as String? ?? '',
      price: Cart._parseDouble(json['price']),
      basePrice: basePrice,
      originalPrice: originalPrice,
      quantity: Cart._parseInt(json['quantity']),
      stock: Cart._parseInt(json['stock']),
      variant: (json['variant'] as Map<String, dynamic>?) ?? {},
      image: json['image'] as String? ?? '',
      bulkEnabled: json['bulkEnabled'] == true,
      minimumBulkQuantity: json['minimumBulkQuantity'] != null ? Cart._parseInt(json['minimumBulkQuantity']) : null,
      maxQuantityPerDay: json['maxQuantityPerDay'] != null ? Cart._parseInt(json['maxQuantityPerDay']) : null,
      remainingDailyQuantity: json['remainingDailyQuantity'] != null ? Cart._parseInt(json['remainingDailyQuantity']) : null,
      expiresAt: json['expiresAt'] != null ? DateTime.tryParse(json['expiresAt'].toString()) : null,
      expiresInSeconds: json['expiresInSeconds'] != null ? Cart._parseInt(json['expiresInSeconds']) : null,
    );
  }
}

class BulkProgress {
  final int productId;
  final String productTitle;
  final int minimumRequired;
  final int currentQuantity;
  final bool met;
  final int remaining;

  BulkProgress({
    required this.productId,
    required this.productTitle,
    required this.minimumRequired,
    required this.currentQuantity,
    required this.met,
    required this.remaining,
  });

  factory BulkProgress.fromJson(Map<String, dynamic> json) {
    return BulkProgress(
      productId: json['productId'] ?? 0,
      productTitle: json['productTitle'] ?? '',
      minimumRequired: json['minimumRequired'] ?? 0,
      currentQuantity: json['currentQuantity'] ?? 0,
      met: json['met'] ?? false,
      remaining: json['remaining'] ?? 0,
    );
  }
}
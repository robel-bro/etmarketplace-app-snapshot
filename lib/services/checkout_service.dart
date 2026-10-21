// lib/services/checkout_service.dart
import 'dart:math';
import 'package:flutter/foundation.dart';
import '../api/client.dart';

double _toDouble(dynamic value) {
  if (value == null) return 0.0;
  if (value is num) return value.toDouble();
  if (value is String) return double.tryParse(value) ?? 0.0;
  return 0.0;
}

int _toInt(dynamic value) {
  if (value == null) return 0;
  if (value is num) return value.toInt();
  if (value is String) {
    final d = double.tryParse(value);
    return d?.toInt() ?? 0;
  }
  return 0;
}

String _toString(dynamic value) {
  return value?.toString() ?? '';
}

Map<String, dynamic> _toMap(dynamic value) {
  if (value is Map) return Map<String, dynamic>.from(value);
  return {};
}

List<Map<String, dynamic>> _toMapList(dynamic value) {
  if (value is List) {
    return value
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
  }
  return [];
}

class CheckoutService {
  // ─── Geocoding ──────────────────────────────────────
  static Future<Map<String, dynamic>> reverseGeocode(double lat, double lng) async {
    final response = await ApiClient.instance.get(
      '/geocode/reverse',
      queryParameters: {
        'lat': lat.toString(),
        'lon': lng.toString(),
      },
    );
    return {
      'address': response.data['address'] as String? ?? '',
      'structured': response.data['structured'] as Map<String, dynamic>? ?? {},
    };
  }

  // ─── Cart – atomic batch add ───────────────────────
  static Future<Map<String, dynamic>> addItemsToCart(List<Map<String, dynamic>> items) async {
    final response = await ApiClient.instance.post(
      '/cart/add_items',
      data: {'items': items},
    );
    return response.data as Map<String, dynamic>;
  }

  // ─── Checkout Options ───────────────────────────────
  static Future<List<PaymentGateway>> getPaymentOptions() async {
    final response = await ApiClient.instance.get('/checkout/payment_options');
    return (response.data as List)
        .map((json) => PaymentGateway.fromJson(json))
        .toList();
  }

  static Future<List<ShippingOption>> getShippingOptions(int addressId) async {
    final response = await ApiClient.instance.post(
      '/checkout/shipping_options',
      data: {'address_id': addressId},
    );
    return (response.data as List)
        .map((json) => ShippingOption.fromJson(json))
        .toList();
  }

  // ★ Fetch backend summary
  static Future<CheckoutSummary> getSummary({
    required int addressId,
    int? partnerId,
    String? couponCode,
  }) async {
    final response = await ApiClient.instance.post(
      '/checkout/summary',
      data: {
        'address_id': addressId,
        if (partnerId != null) 'partner_id': partnerId,
        'coupon_code': couponCode,
      },
    );
    return CheckoutSummary.fromJson(response.data as Map<String, dynamic>);
  }

  // ─── Place Order ────────────────────────────────────
  static Future<CheckoutResult> placeOrder({
    required int addressId,
    required String paymentMethod,
    int? partnerId,
    String? partnerName,
    String? couponCode,
    String? idempotencyKey,
  }) async {
    final key = idempotencyKey ?? generateIdempotencyKey();
    final response = await ApiClient.instance.post(
      '/checkout',
      data: {
        'address_id': addressId,
        'payment_method': paymentMethod,
        if (partnerId != null) 'partner_id': partnerId,
        if (partnerId == null && partnerName != null) 'partner_name': partnerName,
        'coupon_code': couponCode,
        'idempotency_key': key,
      },
    );
    return CheckoutResult.fromJson(response.data as Map<String, dynamic>);
  }

  static String generateIdempotencyKey() {
    final now = DateTime.now().microsecondsSinceEpoch.toString();
    final random = Random().nextInt(0x7fffffff).toString();
    return '$now-$random';
  }
}

// ─── Checkout Summary Model ───────────────────────────
class CheckoutSummary {
  final double subtotal;
  final double discount;
  final double shipping;
  final double serviceFee;
  final double vat;
  final double total;
  final double rawCarrierCost;
  final double sellerSubsidy;
  final double platformMarkup;

  // New enriched fields
  final CheckoutSummaryAddress? address;
  final List<CheckoutSummaryItem> items;
  final Map<String, dynamic> delivery;

  CheckoutSummary({
    required this.subtotal,
    required this.discount,
    required this.shipping,
    required this.serviceFee,
    required this.vat,
    required this.total,
    this.rawCarrierCost = 0.0,
    this.sellerSubsidy = 0.0,
    this.platformMarkup = 0.0,
    this.address,
    this.items = const [],
    this.delivery = const {},
  });

  factory CheckoutSummary.fromJson(Map<String, dynamic> json) {
    return CheckoutSummary(
      subtotal: _toDouble(json['subtotal']),
      discount: _toDouble(json['discount']),
      shipping: _toDouble(json['shipping']),
      serviceFee: _toDouble(json['service_fee']),
      vat: _toDouble(json['vat']),
      total: _toDouble(json['total']),
      rawCarrierCost: _toDouble(json['raw_carrier_cost']),
      sellerSubsidy: _toDouble(json['seller_subsidy']),
      platformMarkup: _toDouble(json['platform_markup']),
      address: json['address'] != null
          ? CheckoutSummaryAddress.fromJson(_toMap(json['address']))
          : null,
      items: _toMapList(json['items'])
          .map((e) => CheckoutSummaryItem.fromJson(e))
          .toList(),
      delivery: _toMap(json['delivery']),
    );
  }
}

// ─── Address Model for Summary ────────────────────────
class CheckoutSummaryAddress {
  final int id;
  final String fullAddress;
  final String? street;
  final String? subCity;
  final String? woreda;
  final String? city;
  final String? landmark;
  final String? neighborhood;
  final String? phone;
  final String? deliveryNotes;
  final double? latitude;
  final double? longitude;

  CheckoutSummaryAddress({
    required this.id,
    required this.fullAddress,
    this.street,
    this.subCity,
    this.woreda,
    this.city,
    this.landmark,
    this.neighborhood,
    this.phone,
    this.deliveryNotes,
    this.latitude,
    this.longitude,
  });

  factory CheckoutSummaryAddress.fromJson(Map<String, dynamic> json) {
    return CheckoutSummaryAddress(
      id: _toInt(json['id']),
      fullAddress: _toString(json['full_address']),
      street: json['street']?.toString(),
      subCity: json['sub_city']?.toString(),
      woreda: json['woreda']?.toString(),
      city: json['city']?.toString(),
      landmark: json['landmark']?.toString(),
      neighborhood: json['neighborhood']?.toString(),
      phone: json['phone']?.toString(),
      deliveryNotes: json['delivery_notes']?.toString(),
      latitude: json['latitude'] != null ? _toDouble(json['latitude']) : null,
      longitude: json['longitude'] != null ? _toDouble(json['longitude']) : null,
    );
  }
}

// ─── Item Model for Summary ───────────────────────────
class CheckoutSummaryItem {
  final int cartItemId;
  final String type;
  final int? productId;
  final int? packageId;
  final String title;
  final String? imageUrl;
  final int? vendorId;
  final String? vendorName;
  final Map<String, dynamic> variantAttributes;
  final double basePrice;
  final double price;
  final int quantity;
  final double lineTotal;
  final double discountTotal;
  final bool bulkEnabled;
  final int? minimumBulkQuantity;

  CheckoutSummaryItem({
    required this.cartItemId,
    required this.type,
    this.productId,
    this.packageId,
    required this.title,
    this.imageUrl,
    this.vendorId,
    this.vendorName,
    this.variantAttributes = const {},
    required this.basePrice,
    required this.price,
    required this.quantity,
    required this.lineTotal,
    required this.discountTotal,
    this.bulkEnabled = false,
    this.minimumBulkQuantity,
  });

  factory CheckoutSummaryItem.fromJson(Map<String, dynamic> json) {
    final basePrice = _toDouble(json['base_price']);
    final price = _toDouble(json['price']);
    final quantity = _toInt(json['quantity']);
    return CheckoutSummaryItem(
      cartItemId: _toInt(json['cart_item_id']),
      type: _toString(json['type']),
      productId: json['product_id'] != null ? _toInt(json['product_id']) : null,
      packageId: json['package_id'] != null ? _toInt(json['package_id']) : null,
      title: _toString(json['title']),
      imageUrl: json['image_url']?.toString(),
      vendorId: json['vendor_id'] != null ? _toInt(json['vendor_id']) : null,
      vendorName: json['vendor_name']?.toString(),
      variantAttributes: _toMap(json['variant_attributes']),
      basePrice: basePrice,
      price: price,
      quantity: quantity,
      lineTotal: _toDouble(json['line_total']),
      discountTotal: _toDouble(json['discount_total']),
      bulkEnabled: json['bulk_enabled'] == true,
      minimumBulkQuantity: json['minimum_bulk_quantity'] != null
          ? _toInt(json['minimum_bulk_quantity'])
          : null,
    );
  }

  bool get hasDiscount => discountTotal > 0;
}

// ─── Checkout Result Model ───────────────────────────
class CheckoutResult {
  final List<Map<String, dynamic>> orders;
  final List<Map<String, dynamic>> successful;
  final List<Map<String, dynamic>> failed;
  final double consolidatedShipping;
  final String? redirectUrl;
  final String? message;
  final String? error;

  CheckoutResult({
    required this.orders,
    required this.successful,
    required this.failed,
    required this.consolidatedShipping,
    this.redirectUrl,
    this.message,
    this.error,
  });

  factory CheckoutResult.fromJson(Map<String, dynamic> json) {
    return CheckoutResult(
      orders: _toMapList(json['orders']),
      successful: _toMapList(json['successful']),
      failed: _toMapList(json['failed']),
      consolidatedShipping: _toDouble(json['consolidated_shipping']),
      redirectUrl: json['redirect_url']?.toString(),
      message: json['message']?.toString(),
      error: json['error']?.toString(),
    );
  }

  bool get hasRedirect => redirectUrl != null && redirectUrl!.isNotEmpty;
  bool get hasOrders => orders.isNotEmpty || successful.isNotEmpty;
  bool get hasPartialFailure => failed.isNotEmpty;
}

// ─── Payment Gateway Model ───────────────────────────
class PaymentGateway {
  final int id;
  final String name;
  final String provider;
  final bool active;
  final bool supportsRefunds;

  PaymentGateway({
    required this.id,
    required this.name,
    required this.provider,
    this.active = true,
    this.supportsRefunds = false,
  });

  factory PaymentGateway.fromJson(Map<String, dynamic> json) {
    return PaymentGateway(
      id: _toInt(json['id']),
      name: _toString(json['name']),
      provider: _toString(json['provider']).isEmpty ? 'cash_on_delivery' : json['provider'].toString(),
      active: json['active'] ?? true,
      supportsRefunds: json['supports_refunds'] ?? false,
    );
  }
}

// ─── Shipping Option Model ───────────────────────────
class ShippingOption {
  final int? partnerId;
  final String partnerName;
  final String deliverySpeed;
  final String deliveryLabel;
  final int estimatedDays;
  final String estimatedDelivery;
  final String estimatedDeliveryLabel;
  final double charge;
  final double rawCarrierCost;
  final double sellerSubsidy;
  final double platformMarkup;

  ShippingOption({
    this.partnerId,
    this.partnerName = '',
    required this.deliverySpeed,
    required this.deliveryLabel,
    required this.estimatedDays,
    this.estimatedDelivery = '',
    this.estimatedDeliveryLabel = '',
    required this.charge,
    this.rawCarrierCost = 0.0,
    this.sellerSubsidy = 0.0,
    this.platformMarkup = 0.0,
  });

  factory ShippingOption.fromJson(Map<String, dynamic> json) {
    final dynamic speedRaw = json['delivery_speed'];
    String speedStr;
    if (speedRaw is num) {
      speedStr = speedRaw.toInt().toString();
    } else if (speedRaw is String) {
      speedStr = speedRaw;
    } else {
      speedStr = '';
    }

    final int? partnerId = json['partner_id'] != null ? _toInt(json['partner_id']) : null;
    final String label = json['delivery_label']?.toString() ?? _fallbackLabel(speedStr);
    final String estDelivery = json['estimated_delivery']?.toString() ?? '';
    final String estDeliveryLabel = json['estimated_delivery_label']?.toString() ?? '';

    return ShippingOption(
      partnerId: partnerId,
      partnerName: json['partner_name']?.toString() ?? 'Standard',
      deliverySpeed: speedStr,
      deliveryLabel: label,
      estimatedDays: _toInt(json['estimated_days']),
      estimatedDelivery: estDelivery,
      estimatedDeliveryLabel: estDeliveryLabel,
      charge: _toDouble(json['charge']),
      rawCarrierCost: _toDouble(json['raw_carrier_cost']),
      sellerSubsidy: _toDouble(json['seller_subsidy']),
      platformMarkup: _toDouble(json['platform_markup']),
    );
  }

  String get speedLabel => deliveryLabel.isNotEmpty ? deliveryLabel : 'Standard';

  String get deliveryTimeLabel {
    if (estimatedDeliveryLabel.isNotEmpty) {
      return estimatedDeliveryLabel;
    }
    if (estimatedDays == 0) return 'Today';
    if (estimatedDays == 1) return 'Tomorrow';
    return '$estimatedDays day(s)';
  }

  static String _fallbackLabel(String rawSpeed) {
    switch (rawSpeed) {
      case '0':
        return 'Standard';
      case '1':
        return 'Express';
      case '2':
        return 'Next Day';
      default:
        return 'Standard';
    }
  }
}
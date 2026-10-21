// lib/models/order.dart

class Order {
  final int id;
  final String orderNumber;
  final String status;
  final double total;
  final String date;
  final String? estimatedDelivery;
  final DateTime? acceptanceDeadline;
  final List<OrderItem> items;
  final List<DeliveryRequest> deliveryRequests;
  final String? deliveryPin;
  final String? pickupPin;             // ★ ADDED
  final String? buyerName;
  final Vendor? vendor;
  final Address? address;

  // ★ Financial fields
  final double subtotal;
  final double discountAmount;
  final double serviceFee;
  final double vatAmount;
  final double consolidatedShipping;
  final double shippingCost;

  // ★ Return policy fields
  final DateTime? deliveredAt;
  final int? returnWindowDays;
  final double? restockingFeePercent;
  final String? returnShippingResponsibility;
  final DateTime? returnDeadline;

  // ★ Active return request (id + status) from backend
  final Map<String, dynamic>? activeReturnRequest;

  Order({
    required this.id,
    required this.orderNumber,
    required this.status,
    required this.total,
    required this.date,
    this.estimatedDelivery,
    this.acceptanceDeadline,
    required this.items,
    this.deliveryRequests = const [],
    this.deliveryPin,
    this.pickupPin,                     // ★ ADDED
    this.buyerName,
    this.vendor,
    this.address,
    this.subtotal = 0.0,
    this.discountAmount = 0.0,
    this.serviceFee = 0.0,
    this.vatAmount = 0.0,
    this.consolidatedShipping = 0.0,
    this.shippingCost = 0.0,
    this.deliveredAt,
    this.returnWindowDays,
    this.restockingFeePercent,
    this.returnShippingResponsibility,
    this.returnDeadline,
    this.activeReturnRequest,
  });

  // ── Safe numeric parsers ──────────────────
  static double _parseDouble(dynamic value, {double defaultValue = 0.0}) {
    if (value == null) return defaultValue;
    if (value is num) return value.toDouble();
    if (value is String) return double.tryParse(value) ?? defaultValue;
    return defaultValue;
  }

  static int _parseInt(dynamic value, {int defaultValue = 0}) {
    if (value == null) return defaultValue;
    if (value is num) return value.toInt();
    if (value is String) {
      final d = double.tryParse(value);
      return d?.toInt() ?? defaultValue;
    }
    return defaultValue;
  }

  factory Order.fromJson(Map<String, dynamic> json) {
    return Order(
      id: _parseInt(json['id']),
      orderNumber: json['order_number']?.toString() ?? json['id']?.toString() ?? '',
      status: json['status']?.toString() ?? '',
      total: _parseDouble(json['total']),
      date: json['created_at']?.toString() ?? '',
      estimatedDelivery: json['estimated_delivery']?.toString(),
      acceptanceDeadline: json['acceptance_deadline'] != null
          ? DateTime.tryParse(json['acceptance_deadline'].toString())
          : null,
      items: (json['items'] as List?)
              ?.map((i) => OrderItem.fromJson(i))
              .toList() ?? [],
      deliveryRequests: (json['delivery_requests'] as List?)
              ?.map((dr) => DeliveryRequest.fromJson(dr))
              .toList() ?? [],
      deliveryPin: json['delivery_pin']?.toString(),
      pickupPin: json['pickup_pin']?.toString(),   // ★ ADDED
      buyerName: json['buyer_name']?.toString(),
      vendor: json['vendor'] != null ? Vendor.fromJson(json['vendor']) : null,
      address: json['address'] != null ? Address.fromJson(json['address']) : null,
      subtotal: _parseDouble(json['subtotal']),
      discountAmount: _parseDouble(json['discount_amount']),
      serviceFee: _parseDouble(json['service_fee']),
      vatAmount: _parseDouble(json['vat_amount']),
      consolidatedShipping: _parseDouble(json['consolidated_shipping']),
      shippingCost: _parseDouble(json['shipping_cost']),
      deliveredAt: json['delivered_at'] != null
          ? DateTime.tryParse(json['delivered_at'].toString())
          : null,
      returnWindowDays: _parseInt(json['return_window_days']),
      restockingFeePercent: json['restocking_fee_percent'] != null
          ? _parseDouble(json['restocking_fee_percent'])
          : null,
      returnShippingResponsibility: json['return_shipping_responsibility']?.toString(),
      returnDeadline: json['return_deadline'] != null
          ? DateTime.tryParse(json['return_deadline'].toString())
          : null,
      activeReturnRequest: json['active_return_request'] is Map
          ? Map<String, dynamic>.from(json['active_return_request'])
          : null,
    );
  }

  bool get isReturnEligible {
    if (status != 'delivered' || returnWindowDays == null) return false;
    final deadline = returnDeadline ??
        (deliveredAt != null ? deliveredAt!.add(Duration(days: returnWindowDays!)) : null);
    if (deadline == null) return false;
    return DateTime.now().isBefore(deadline);
  }

  int? get returnDaysLeft {
    if (!isReturnEligible) return null;
    final deadline = returnDeadline ??
        (deliveredAt!.add(Duration(days: returnWindowDays!)));
    return deadline.difference(DateTime.now()).inDays;
  }

  bool get hasActiveReturnRequest => activeReturnRequest != null;
}

// ── OrderItem (updated for packages & variants) ──
class OrderItem {
  final int? productId;
  final int? packageId;
  final String title;
  final int quantity;
  final double price;
  final String? imageUrl;
  final Map<String, dynamic> variantAttributes;

  OrderItem({
    this.productId,
    this.packageId,
    required this.title,
    required this.quantity,
    required this.price,
    this.imageUrl,
    this.variantAttributes = const {},
  });

  factory OrderItem.fromJson(Map<String, dynamic> json) {
    return OrderItem(
      productId: json['product_id'] != null
          ? Order._parseInt(json['product_id'])
          : null,
      packageId: json['package_id'] != null
          ? Order._parseInt(json['package_id'])
          : null,
      title: json['title']?.toString() ?? '',
      quantity: Order._parseInt(json['quantity']),
      price: Order._parseDouble(json['price']),
      imageUrl: json['image']?.toString(),
      variantAttributes: json['variant_attributes'] is Map
          ? Map<String, dynamic>.from(json['variant_attributes'])
          : const {},
    );
  }

  bool get isPackage => packageId != null;
  bool get isProduct => productId != null;
}

// ── DeliveryRequest ───────────────────────────────
class DeliveryRequest {
  final int id;
  final String status;
  final String? vehicleType;
  final double? estimatedCost;
  final String? pickupAddress;
  final String? deliveryAddress;
  final DateTime? acceptedAt;
  final DateTime? pickedUpAt;
  final DateTime? deliveredAt;
  final List<DeliveryEvent> events;
  final LogisticsPartner? logisticsPartner;
  final double? currentLat;
  final double? currentLng;

  DeliveryRequest({
    required this.id,
    required this.status,
    this.vehicleType,
    this.estimatedCost,
    this.pickupAddress,
    this.deliveryAddress,
    this.acceptedAt,
    this.pickedUpAt,
    this.deliveredAt,
    required this.events,
    this.logisticsPartner,
    this.currentLat,
    this.currentLng,
  });

  factory DeliveryRequest.fromJson(Map<String, dynamic> json) {
    return DeliveryRequest(
      id: Order._parseInt(json['id']),
      status: json['status']?.toString() ?? 'pending',
      vehicleType: json['vehicle_type']?.toString(),
      estimatedCost: json['estimated_cost'] != null
          ? Order._parseDouble(json['estimated_cost'])
          : null,
      pickupAddress: json['pickup_address']?.toString(),
      deliveryAddress: json['delivery_address']?.toString(),
      acceptedAt: json['accepted_at'] != null
          ? DateTime.tryParse(json['accepted_at'].toString())
          : null,
      pickedUpAt: json['picked_up_at'] != null
          ? DateTime.tryParse(json['picked_up_at'].toString())
          : null,
      deliveredAt: json['delivered_at'] != null
          ? DateTime.tryParse(json['delivered_at'].toString())
          : null,
      events: (json['events'] as List?)
              ?.map((e) => DeliveryEvent.fromJson(e))
              .toList() ?? [],
      logisticsPartner: json['logistics_partner'] != null
          ? LogisticsPartner.fromJson(json['logistics_partner'])
          : null,
      currentLat: json['current_lat'] != null
          ? Order._parseDouble(json['current_lat'])
          : null,
      currentLng: json['current_lng'] != null
          ? Order._parseDouble(json['current_lng'])
          : null,
    );
  }
}

class DeliveryEvent {
  final String timestamp;
  final String status;
  final String? location;
  final String? note;

  DeliveryEvent({
    required this.timestamp,
    required this.status,
    this.location,
    this.note,
  });

  factory DeliveryEvent.fromJson(Map<String, dynamic> json) {
    return DeliveryEvent(
      timestamp: json['timestamp']?.toString() ?? '',
      status: json['status']?.toString() ?? '',
      location: json['location']?.toString(),
      note: json['note']?.toString(),
    );
  }
}

class LogisticsPartner {
  final int id;
  final String name;
  final String? phone;

  LogisticsPartner({required this.id, required this.name, this.phone});

  factory LogisticsPartner.fromJson(Map<String, dynamic> json) {
    return LogisticsPartner(
      id: Order._parseInt(json['id']),
      name: json['name']?.toString() ?? '',
      phone: json['phone']?.toString(),
    );
  }
}

class Vendor {
  final String? shopName;
  final String? businessAddress;
  final String? phone;
  final double? businessLat;
  final double? businessLng;
  final bool acceptingOrders;
  final String? reopenAt;

  Vendor({
    this.shopName,
    this.businessAddress,
    this.phone,
    this.businessLat,
    this.businessLng,
    this.acceptingOrders = true,
    this.reopenAt,
  });

  factory Vendor.fromJson(Map<String, dynamic> json) {
    return Vendor(
      shopName: json['shop_name']?.toString(),
      businessAddress: json['business_address']?.toString(),
      phone: json['phone']?.toString(),
      businessLat: json['business_lat'] != null
          ? Order._parseDouble(json['business_lat'])
          : null,
      businessLng: json['business_lng'] != null
          ? Order._parseDouble(json['business_lng'])
          : null,
      acceptingOrders: json['accepting_orders'] ?? true,
      reopenAt: json['reopen_at']?.toString(),
    );
  }
}

class Address {
  final double? latitude;
  final double? longitude;
  final String? fullAddress;
  final String? phone;
  final String? deliveryNotes;

  Address({
    this.latitude,
    this.longitude,
    this.fullAddress,
    this.phone,
    this.deliveryNotes,
  });

  factory Address.fromJson(Map<String, dynamic> json) {
    return Address(
      latitude: json['latitude'] != null
          ? Order._parseDouble(json['latitude'])
          : null,
      longitude: json['longitude'] != null
          ? Order._parseDouble(json['longitude'])
          : null,
      fullAddress: json['full_address']?.toString(),
      phone: json['phone']?.toString(),
      deliveryNotes: json['delivery_notes']?.toString(),
    );
  }
}
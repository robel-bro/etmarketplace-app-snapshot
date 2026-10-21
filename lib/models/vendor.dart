// lib/models/vendor.dart

class Vendor {
  final int id;
  final String businessName;
  final String? businessAddress;
  final String? logo;            // logo_url from API
  final String? banner;          // banner_url from API
  final double rating;
  final int reviewsCount;
  final String? description;
  final bool isVerified;
  final bool acceptingOrders;
  final DateTime? reopenAt;

  // ★ Membership fields (added from backend)
  final String? membershipTier;  // 'silver', 'gold', 'platinum', etc.
  final String? badge;           // custom badge text (e.g., "Gold Seller")
  final int totalSales;          // total products sold across all products
  final int productsCount;       // total number of products
  final bool isCompany;          // true for enterprise/bulk suppliers

  // ★ Featured seller fields (NEW)
  final bool featured;           // vendor is currently featured
  final DateTime? featuredUntil; // when the featured status expires

  Vendor({
    required this.id,
    required this.businessName,
    this.businessAddress,
    this.logo,
    this.banner,
    required this.rating,
    required this.reviewsCount,
    this.description,
    this.isVerified = false,
    this.acceptingOrders = true,
    this.reopenAt,
    this.membershipTier,
    this.badge,
    this.totalSales = 0,
    this.productsCount = 0,
    this.isCompany = false,
    this.featured = false,
    this.featuredUntil,
  });

  factory Vendor.fromJson(Map<String, dynamic> json) {
    double parseDouble(dynamic value) {
      if (value == null) return 0.0;
      if (value is num) return value.toDouble();
      if (value is String) return double.tryParse(value) ?? 0.0;
      return 0.0;
    }

    DateTime? parseDateTime(dynamic value) {
      if (value == null) return null;
      if (value is String) return DateTime.tryParse(value);
      return null;
    }

    return Vendor(
      id: json['id'] is int ? json['id'] : int.tryParse(json['id'].toString()) ?? 0,
      businessName: json['business_name'] ?? '',
      businessAddress: json['business_address'],
      logo: json['logo_url'],
      banner: json['banner_url'],
      rating: parseDouble(json['average_rating'] ?? json['rating']),
      reviewsCount: (json['total_reviews_count'] as num?)?.toInt() ??
          (json['reviews_count'] as num?)?.toInt() ??
          0,
      description: json['description'],
      isVerified: json['status'] == 'approved' || json['is_verified'] == true,
      acceptingOrders: json['accepting_orders'] ?? true,
      reopenAt: parseDateTime(json['reopen_at']),
      membershipTier: json['membership_tier']?.toString(),
      badge: (json['badge'] ?? json['membership_tier'])?.toString(),   // ★ fallback to membership_tier
      totalSales: (json['total_sales'] as num?)?.toInt() ?? 0,
      productsCount: (json['products_count'] as num?)?.toInt() ?? 0,
      isCompany: json['is_company'] == true,
      featured: json['featured'] == true,
      featuredUntil: parseDateTime(json['featured_until']),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'business_name': businessName,
      'business_address': businessAddress,
      'logo_url': logo,
      'banner_url': banner,
      'rating': rating,
      'reviews_count': reviewsCount,
      'description': description,
      'is_verified': isVerified,
      'accepting_orders': acceptingOrders,
      'reopen_at': reopenAt?.toIso8601String(),
      'membership_tier': membershipTier,
      'badge': badge,
      'total_sales': totalSales,
      'products_count': productsCount,
      'is_company': isCompany,
      'featured': featured,
      'featured_until': featuredUntil?.toIso8601String(),
    };
  }
}
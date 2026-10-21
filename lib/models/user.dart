// lib/models/user.dart
class User {
  final int id;
  final String phone;
  final String? fullName;
  final String? email;
  final List<String> roles;
  final bool isCompany;
  final String? companyName;
  final String? avatarUrl;

  // ★ Seller identity fields (from /api/v1/profile)
  final String? nationalId;
  final String? faydaId;
  final String? shopName;
  final String? shopLocation;
  final String? tin;
  final bool phoneVerified;
  final String? fcmToken;
  final String? businessLicenseUrl;

  User({
    required this.id,
    required this.phone,
    this.fullName,
    this.email,
    required this.roles,
    this.isCompany = false,
    this.companyName,
    this.avatarUrl,
    this.nationalId,
    this.faydaId,
    this.shopName,
    this.shopLocation,
    this.tin,
    this.phoneVerified = false,
    this.fcmToken,
    this.businessLicenseUrl,
  });

  factory User.fromJson(Map<String, dynamic> json) {
    return User(
      id: (json['id'] as num).toInt(),
      phone: json['phone']?.toString() ?? '',
      fullName: json['full_name']?.toString() ?? json['name']?.toString(),
      email: json['email']?.toString(),
      roles: (json['roles'] as List?)
              ?.map((e) => e.toString())
              .toList() ??
          [],
      isCompany: json['is_company'] == true || json['is_company'] == 'true',
      companyName: json['company_name']?.toString(),
      avatarUrl: json['avatar_url']?.toString() ?? json['profile_picture_url']?.toString(),

      // ★ New identity fields
      nationalId: json['national_id']?.toString(),
      faydaId: json['fayda_id']?.toString(),
      shopName: json['shop_name']?.toString(),
      shopLocation: json['shop_location']?.toString(),
      tin: json['tin']?.toString(),
      phoneVerified: json['phone_verified'] == true || json['phone_verified'] == 'true',
      fcmToken: json['fcm_token']?.toString(),
      businessLicenseUrl: json['business_license_url']?.toString(),
    );
  }

  String get displayName {
    if (fullName != null && fullName!.isNotEmpty) return fullName!;
    if (phone.isNotEmpty) return phone;
    return 'User';
  }

  String get initial => displayName.isNotEmpty ? displayName[0].toUpperCase() : 'U';
}
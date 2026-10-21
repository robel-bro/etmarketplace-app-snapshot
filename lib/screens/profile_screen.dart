// lib/screens/profile_screen.dart
import 'dart:io';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:dio/dio.dart';
import 'package:flutter_svg/flutter_svg.dart';
import '../api/client.dart';
import '../providers/auth_provider.dart';
import '../providers/cart_provider.dart';
import '../providers/wishlist_provider.dart';
import '../providers/compare_provider.dart';
import '../providers/locale_provider.dart';
import '../l10n/app_localizations.dart';
import '../theme/app_theme.dart';
import '../models/user.dart';
import 'login_screen.dart';
import 'orders_screen.dart';
import 'order_tracking_screen.dart';
import 'wishlist_screen.dart';
import 'compare_screen.dart';
import 'address_book_screen.dart';
import 'account_details_screen.dart';
import 'settings_screen.dart';
import 'help_center_screen.dart';
import 'seller_dashboard_screen.dart';
import 'seller_setup_screen.dart';
import '../widgets/notification_bell.dart';
import 'home_screen.dart';
import 'category_products_screen.dart';
import 'find_shop_screen.dart';
import 'cart_screen.dart';
import 'legal_page_viewer.dart';

// ★ Changed: provider now depends on userId (int?) for automatic refresh
final vendorDataProvider = FutureProvider.family<Map<String, dynamic>?, int?>((ref, userId) async {
  if (userId == null || !ApiClient.hasToken) return null;
  try {
    final response = await ApiClient.instance.get('/api/v1/vendors/me');
    return response.data != null ? Map<String, dynamic>.from(response.data) : null;
  } catch (_) {
    return null;
  }
});

// ─── Local AppTheme (same as before) ──────────────────────────
class AppTheme {
  static const Color primaryOrange = Color(0xFFFF4400);
  static const Color strongRed = Color(0xFFEF4444);
  static const Color premiumBlack = Color(0xFF000000);
  static const Color whiteBackground = Color(0xFFFFFFFF);
  static const Color cardWhite = Color(0xFFFFFFFF);
  static const Color subtleGrey = Color(0xFF555555);
  static const Color dividerColor = Color(0xFFEEEEEE);

  static BoxDecoration cardDecoration = BoxDecoration(
    color: cardWhite,
    borderRadius: BorderRadius.circular(16),
    boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 12, offset: const Offset(0, 4))],
    border: Border.all(color: dividerColor, width: 1),
  );
}

// ─── Full‑screen image viewer ─────────────────────────────────
class _FullScreenImagePage extends StatelessWidget {
  final String? imageUrl;
  final String? name;
  const _FullScreenImagePage({this.imageUrl, this.name});

  @override
  Widget build(BuildContext context) {
    final initial = (name != null && name!.isNotEmpty) ? name![0].toUpperCase() : 'U';
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.close, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: Center(
        child: InteractiveViewer(
          child: imageUrl != null && imageUrl!.isNotEmpty
              ? Image.network(imageUrl!, fit: BoxFit.contain)
              : CircleAvatar(
                  radius: 100,
                  backgroundColor: Colors.grey.shade800,
                  child: Text(initial, style: const TextStyle(fontSize: 80, color: Colors.white)),
                ),
        ),
      ),
    );
  }
}

// ─── Main Profile Screen ──────────────────────────────────────
class ProfileScreen extends ConsumerStatefulWidget {
  const ProfileScreen({Key? key}) : super(key: key);

  @override
  ConsumerState<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends ConsumerState<ProfileScreen> with SingleTickerProviderStateMixin {
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;
  final ImagePicker _picker = ImagePicker();
  final ScrollController _scrollController = ScrollController();
  double _bellOpacity = 1.0;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(vsync: this, duration: const Duration(seconds: 2))..repeat(reverse: true);
    _pulseAnimation = Tween<double>(begin: 0.9, end: 1.0).animate(CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut));
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    final offset = _scrollController.offset;
    final targetOpacity = (offset > 60) ? 0.0 : 1.0;
    if ((_bellOpacity - targetOpacity).abs() > 0.01) {
      setState(() {
        _bellOpacity = targetOpacity;
      });
    }
  }

  // ─── Edit profile sheet (unchanged) ───────────────────────
  void _showEditProfileSheet(User? user) {
    final l10n = AppLocalizations.of(context);
    final nameCtrl = TextEditingController(text: user?.fullName ?? '');
    XFile? pickedImage;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModalState) {
          return Container(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 40),
            decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(2))),
                const SizedBox(height: 16),
                Text(l10n.translate('edit_profile'), style: Theme.of(ctx).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                const SizedBox(height: 20),
                GestureDetector(
                  onTap: () async {
                    final file = await _picker.pickImage(source: ImageSource.gallery, imageQuality: 85, maxWidth: 600);
                    if (file != null) setModalState(() => pickedImage = file);
                  },
                  child: Stack(
                    children: [
                      CircleAvatar(
                        radius: 50,
                        backgroundColor: Colors.grey.shade200,
                        backgroundImage: pickedImage != null
                            ? (kIsWeb ? NetworkImage(pickedImage!.path) : FileImage(File(pickedImage!.path)) as ImageProvider)
                            : (user?.avatarUrl != null && user!.avatarUrl!.isNotEmpty
                                ? NetworkImage(user.avatarUrl!)
                                : null),
                        child: (pickedImage == null && (user?.avatarUrl == null || user!.avatarUrl!.isEmpty))
                            ? Icon(PhosphorIcons.user(PhosphorIconsStyle.fill), size: 50, color: AppTheme.subtleGrey)
                            : null,
                      ),
                      Positioned(
                        bottom: 0, right: 0,
                        child: Container(
                          padding: const EdgeInsets.all(6),
                          decoration: const BoxDecoration(color: AppTheme.primaryOrange, shape: BoxShape.circle),
                          child: Icon(PhosphorIcons.camera(PhosphorIconsStyle.fill), size: 16, color: Colors.white),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                TextField(
                  controller: nameCtrl,
                  decoration: InputDecoration(
                    labelText: l10n.translate('full_name'),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    filled: true,
                    fillColor: Colors.grey.shade50,
                  ),
                ),
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () async {
                      await _saveProfile(nameCtrl.text.trim(), pickedImage, user);
                      if (mounted) Navigator.pop(ctx);
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.primaryOrange,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    child: Text(l10n.translate('save'), style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Future<void> _saveProfile(String name, XFile? image, User? user) async {
    final l10n = AppLocalizations.of(context);
    if (!ApiClient.hasToken) return;
    if (name.isEmpty && image == null) return;
    try {
      final formFields = <String, dynamic>{};
      if (name.isNotEmpty) formFields['full_name'] = name;
      if (image != null) {
        if (kIsWeb) {
          final bytes = await image.readAsBytes();
          formFields['avatar'] = MultipartFile.fromBytes(bytes, filename: image.name);
        } else {
          formFields['avatar'] = await MultipartFile.fromFile(image.path, filename: image.name);
        }
      }
      await ApiClient.instance.patch('/api/v1/profile', data: FormData.fromMap(formFields));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l10n.translate('profile_updated')), backgroundColor: AppTheme.primaryOrange),
        );
        ref.read(authProvider.notifier).checkSession();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l10n.translate('profile_update_failed')), backgroundColor: AppTheme.strongRed),
        );
      }
    }
  }

  Future<void> _deleteAccount() async {
    final l10n = AppLocalizations.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.translate('delete_account')),
        content: Text(l10n.translate('delete_account_confirmation')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(l10n.translate('cancel'))),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.strongRed),
            child: Text(l10n.translate('yes_delete'), style: const TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirmed != true) return;
    try {
      await ApiClient.instance.delete('/account');
      await ref.read(authProvider.notifier).logout();
      if (mounted) {
        Navigator.pushAndRemoveUntil(
          context,
          MaterialPageRoute(builder: (_) => const LoginScreen()),
          (route) => false,
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l10n.translate('delete_account_failed')), backgroundColor: AppTheme.strongRed),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final textTheme = Theme.of(context).textTheme;
    final authState = ref.watch(authProvider);
    final user = authState.valueOrNull;
    final isLoggedIn = user != null;
    final userId = user?.id;   // ★ used as parameter for vendor provider

    final wishlist = ref.watch(wishlistProvider);
    final wishlistCount = wishlist is List ? wishlist.length : 0;
    final compare = ref.watch(compareProvider);
    final compareCount = compare is List ? compare.length : 0;

    // ★ Fetch vendor data using userId (auto refreshes on user change)
    final vendorDataAsync = ref.watch(vendorDataProvider(userId));
    final vendorData = vendorDataAsync.valueOrNull;
    final vendorLogoUrl = vendorData?['logo_url']?.toString();
    final shopDescription = vendorData?['description']?.toString();

    // ★ Dual check: user has the seller role OR vendor is approved
    final isApprovedSeller = (user?.roles.contains('seller') ?? false) ||
        (vendorData != null && vendorData['status'] == 'approved');

    return Scaffold(
      backgroundColor: AppTheme.whiteBackground,
      body: Stack(
        children: [
          SafeArea(
            child: CustomScrollView(
              controller: _scrollController,
              slivers: [
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 80, 20, 8),
                    child: Column(
                      children: [
                        GestureDetector(
                          onTap: () {
                            final image = vendorLogoUrl ?? user?.avatarUrl;
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => _FullScreenImagePage(
                                  imageUrl: image,
                                  name: user?.fullName,
                                ),
                              ),
                            );
                          },
                          child: _buildPremiumAvatar(user, vendorLogoUrl: vendorLogoUrl),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          user?.fullName ?? l10n.translate('guest_user'),
                          style: textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700, fontSize: 18),
                        ),
                        if (user?.phone != null) ...[
                          const SizedBox(height: 4),
                          Text(
                            user!.phone!,
                            style: textTheme.bodySmall?.copyWith(fontSize: 13, color: AppTheme.subtleGrey),
                          ),
                        ],
                        if (isApprovedSeller && shopDescription != null && shopDescription.isNotEmpty) ...[
                          const SizedBox(height: 8),
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 24),
                            child: Text(
                              shopDescription,
                              textAlign: TextAlign.center,
                              style: textTheme.bodySmall?.copyWith(
                                fontSize: 13,
                                color: AppTheme.subtleGrey,
                                height: 1.4,
                              ),
                              maxLines: 3,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                        const SizedBox(height: 16),
                        _buildPremiumTabRow(
                          wishlistCount: wishlistCount,
                          compareCount: compareCount,
                          isSeller: isApprovedSeller,
                        ),
                      ],
                    ),
                  ),
                ),
                SliverList(
                  delegate: SliverChildListDelegate([
                    const SizedBox(height: 8),
                    if (isLoggedIn && !isApprovedSeller) _buildSellOnETItem(),
                    if (isLoggedIn && isApprovedSeller) _buildSellerDashboardItem(),
                    const SizedBox(height: 6),
                    _buildMenuCard([
                      _buildMenuItem(icon: PhosphorIcons.user(PhosphorIconsStyle.regular), title: l10n.translate('account_details'), onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => AccountDetailsScreen(user: user)))),
                      _buildMenuItem(icon: PhosphorIcons.mapPin(PhosphorIconsStyle.regular), title: l10n.translate('address_book'), onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const AddressBookScreen()))),
                      _buildMenuItem(icon: PhosphorIcons.gear(PhosphorIconsStyle.regular), title: l10n.translate('settings'), onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const SettingsScreen()))),
                      _buildMenuItem(icon: PhosphorIcons.bellRinging(PhosphorIconsStyle.regular), title: l10n.translate('price_alerts'), onTap: () => Navigator.pushNamed(context, '/price-alerts')),
                    ]),
                    const SizedBox(height: 6),
                    _buildMenuCard([
                      _buildMenuItem(icon: PhosphorIcons.truck(PhosphorIconsStyle.regular), title: l10n.translate('track_order'), onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const OrderTrackingScreen()))),
                    ]),
                    const SizedBox(height: 6),
                    _buildMenuCard([
                      _buildMenuItem(icon: PhosphorIcons.question(PhosphorIconsStyle.regular), title: l10n.translate('help_center'), onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const HelpCenterScreen()))),
                      _buildMenuItem(icon: PhosphorIcons.info(PhosphorIconsStyle.regular), title: l10n.translate('about_et'), onTap: () => _navigateToPlaceholder('About')),
                      _buildMenuItem(icon: PhosphorIcons.article(PhosphorIconsStyle.regular), title: l10n.translate('terms_of_service'), onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => LegalPageViewer(keyName: 'terms')))),
                      _buildMenuItem(icon: PhosphorIcons.shieldCheck(PhosphorIconsStyle.regular), title: l10n.translate('privacy_policy'), onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => LegalPageViewer(keyName: 'privacy')))),
                      _buildMenuItem(icon: PhosphorIcons.cookie(PhosphorIconsStyle.regular), title: l10n.translate('cookie_policy'), onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => LegalPageViewer(keyName: 'cookies')))),
                      _buildMenuItem(icon: PhosphorIcons.shieldCheckered(PhosphorIconsStyle.regular), title: l10n.translate('buyer_protection'), onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => LegalPageViewer(keyName: 'buyer-protection')))),
                      _buildMenuItem(icon: PhosphorIcons.article(PhosphorIconsStyle.regular), title: l10n.translate('ip_policy'), onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => LegalPageViewer(keyName: 'ip-policy')))),
                      _buildMenuItem(icon: PhosphorIcons.truck(PhosphorIconsStyle.regular), title: l10n.translate('shipping_delivery'), onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => LegalPageViewer(keyName: 'shipping-returns')))),
                    ]),
                    const SizedBox(height: 6),
                    _buildMenuCard([
                      _buildLanguageSwitcher(),
                    ]),
                    const SizedBox(height: 6),
                    _buildMenuCard([
                      isLoggedIn
                          ? _buildMenuItem(
                              icon: PhosphorIcons.signOut(PhosphorIconsStyle.regular),
                              title: l10n.translate('logout'),
                              onTap: () async {
                                await ref.read(authProvider.notifier).logout();
                                if (mounted) Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const LoginScreen()));
                              },
                              isDestructive: true,
                            )
                          : _buildMenuItem(
                              icon: PhosphorIcons.signIn(PhosphorIconsStyle.regular),
                              title: l10n.translate('sign_in'),
                              onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const LoginScreen())),
                            ),
                    ]),
                    if (isLoggedIn) ...[
                      const SizedBox(height: 6),
                      _buildMenuCard([
                        _buildMenuItem(
                          icon: PhosphorIcons.trash(PhosphorIconsStyle.regular),
                          title: l10n.translate('delete_account'),
                          onTap: _deleteAccount,
                          isDestructive: true,
                        ),
                      ]),
                    ],
                    const SizedBox(height: 16),
                  ]),
                ),
              ],
            ),
          ),
          Positioned(
            top: MediaQuery.of(context).padding.top + 12,
            right: 12,
            child: AnimatedOpacity(
              opacity: _bellOpacity,
              duration: const Duration(milliseconds: 200),
              child: const NotificationBell(),
            ),
          ),
        ],
      ),
    );
  }

  // Helper widgets (unchanged)
  Widget _buildSellerDashboardItem() {
    final l10n = AppLocalizations.of(context);
    return _buildMenuCard([
      _buildMenuItem(
        icon: PhosphorIcons.storefront(PhosphorIconsStyle.regular),
        title: l10n.translate('seller_dashboard'),
        onTap: () => Navigator.pushNamed(context, '/seller-dashboard'),
      ),
    ]);
  }

  Widget _buildLanguageSwitcher() {
    final l10n = AppLocalizations.of(context);
    final currentLocale = ref.watch(localeProvider) ?? const Locale('en');
    final String currentLabel;
    switch (currentLocale.languageCode) {
      case 'am': currentLabel = l10n.translate('amharic'); break;
      case 'om': currentLabel = l10n.translate('oromo'); break;
      case 'ti': currentLabel = l10n.translate('tigrinya'); break;
      default: currentLabel = l10n.translate('english');
    }

    return ListTile(
      leading: Icon(PhosphorIcons.translate(PhosphorIconsStyle.regular),
          color: AppTheme.premiumBlack.withOpacity(0.65), size: 20),
      title: Text(
        l10n.translate('settings_language'),
        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.w600,
              color: AppTheme.premiumBlack,
              fontSize: 14,
            ),
      ),
      subtitle: Text(
        currentLabel,
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: AppTheme.subtleGrey,
              fontSize: 12,
            ),
      ),
      trailing: Icon(PhosphorIcons.caretRight(PhosphorIconsStyle.regular),
          color: Colors.grey.shade400, size: 18),
      onTap: () {
        showModalBottomSheet(
          context: context,
          shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          builder: (ctx) => SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    l10n.translate('choose_language'),
                    style: Theme.of(ctx).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 12),
                  RadioListTile<Locale>(
                    title: Text(l10n.translate('english')),
                    value: const Locale('en'),
                    groupValue: currentLocale,
                    onChanged: (locale) {
                      if (locale != null) {
                        ref.read(localeProvider.notifier).setLocale(locale);
                        Navigator.pop(ctx);
                      }
                    },
                  ),
                  RadioListTile<Locale>(
                    title: Text(l10n.translate('amharic')),
                    value: const Locale('am'),
                    groupValue: currentLocale,
                    onChanged: (locale) {
                      if (locale != null) {
                        ref.read(localeProvider.notifier).setLocale(locale);
                        Navigator.pop(ctx);
                      }
                    },
                  ),
                  RadioListTile<Locale>(
                    title: Text(l10n.translate('oromo')),
                    value: const Locale('om'),
                    groupValue: currentLocale,
                    onChanged: (locale) {
                      if (locale != null) {
                        ref.read(localeProvider.notifier).setLocale(locale);
                        Navigator.pop(ctx);
                      }
                    },
                  ),
                  RadioListTile<Locale>(
                    title: Text(l10n.translate('tigrinya')),
                    value: const Locale('ti'),
                    groupValue: currentLocale,
                    onChanged: (locale) {
                      if (locale != null) {
                        ref.read(localeProvider.notifier).setLocale(locale);
                        Navigator.pop(ctx);
                      }
                    },
                  ),
                ],
              ),
            ),
          ),
        );
      },
      contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 2),
      minLeadingWidth: 24,
      dense: true,
      visualDensity: VisualDensity.compact,
      hoverColor: AppTheme.primaryOrange.withOpacity(0.04),
      splashColor: AppTheme.primaryOrange.withOpacity(0.08),
    );
  }

  Widget _buildPremiumAvatar(User? user, {String? vendorLogoUrl}) {
    final imageProvider = (vendorLogoUrl != null && vendorLogoUrl.isNotEmpty)
        ? NetworkImage(vendorLogoUrl)
        : (user?.avatarUrl != null && user!.avatarUrl!.isNotEmpty)
            ? NetworkImage(user.avatarUrl!)
            : null;

    final initial = (user?.fullName != null && user!.fullName!.isNotEmpty)
        ? user.fullName![0].toUpperCase()
        : 'U';

    return Container(
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: const LinearGradient(
          colors: [AppTheme.primaryOrange, Color(0xFFFFA559)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        boxShadow: [
          BoxShadow(
            color: AppTheme.primaryOrange.withOpacity(0.15),
            blurRadius: 16,
            offset: const Offset(0, 4),
            spreadRadius: 1,
          ),
        ],
      ),
      padding: const EdgeInsets.all(3),
      child: CircleAvatar(
        radius: 42,
        backgroundColor: Colors.white,
        backgroundImage: imageProvider,
        child: imageProvider == null
            ? Text(initial, style: const TextStyle(fontSize: 32, fontWeight: FontWeight.w700, color: AppTheme.primaryOrange))
            : null,
      ),
    );
  }

  Widget _buildPremiumTabRow({
    required int wishlistCount,
    required int compareCount,
    required bool isSeller,
  }) {
    final l10n = AppLocalizations.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppTheme.primaryOrange.withOpacity(0.12), width: 1.2),
        boxShadow: [BoxShadow(color: AppTheme.primaryOrange.withOpacity(0.04), blurRadius: 16, offset: const Offset(0, 3))],
      ),
      child: Row(
        mainAxisAlignment: isSeller ? MainAxisAlignment.spaceBetween : MainAxisAlignment.spaceAround,
        children: [
          _buildTabButton(icon: PhosphorIcons.receipt(PhosphorIconsStyle.regular), label: l10n.translate('orders'), onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const OrdersScreen()))),
          _buildTabButton(icon: PhosphorIcons.heart(PhosphorIconsStyle.regular), label: l10n.translate('wishlist'), count: wishlistCount, onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const WishlistScreen())), isWishlist: true),
          _buildTabButton(icon: PhosphorIcons.arrowsLeftRight(PhosphorIconsStyle.regular), label: l10n.translate('compare'), count: compareCount, onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const CompareScreen()))),
          if (isSeller)
            _buildTabButton(icon: PhosphorIcons.storefront(PhosphorIconsStyle.regular), label: l10n.translate('my_shop'), onTap: () => Navigator.of(context, rootNavigator: true).push(MaterialPageRoute(builder: (_) => const SellerDashboardScreen()))),
        ],
      ),
    );
  }

  Widget _buildTabButton({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    int? count,
    bool isWishlist = false,
  }) {
    final textTheme = Theme.of(context).textTheme;
    final baseColor = isWishlist ? AppTheme.strongRed : AppTheme.premiumBlack;
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
        decoration: BoxDecoration(color: Colors.transparent, borderRadius: BorderRadius.circular(14)),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Stack(clipBehavior: Clip.none, children: [
            Container(width: 40, height: 40, decoration: BoxDecoration(color: baseColor.withOpacity(0.06), borderRadius: BorderRadius.circular(12)), child: Icon(icon, size: 22, color: baseColor)),
            if (count != null && count > 0) Positioned(right: -4, top: -4, child: Container(padding: const EdgeInsets.all(3), decoration: const BoxDecoration(color: AppTheme.strongRed, shape: BoxShape.circle), constraints: const BoxConstraints(minWidth: 16, minHeight: 16), child: Text(count > 9 ? '9+' : '$count', style: const TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.w800), textAlign: TextAlign.center))),
          ]),
          const SizedBox(height: 4),
          Text(label, style: textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w600, fontSize: 12, color: AppTheme.premiumBlack)),
        ]),
      ),
    );
  }

  Widget _buildSellOnETItem() {
    final l10n = AppLocalizations.of(context);
    return Padding(
      padding: const EdgeInsets.only(left: 12, right: 12),
      child: GestureDetector(
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const SellerSetupScreen()),
          );
        },
        child: Container(
          height: 100,
          decoration: const BoxDecoration(),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                flex: 40,
                child: SvgPicture.asset(
                  'assets/images/shop_graphic.svg',
                  fit: BoxFit.contain,
                  placeholderBuilder: (ctx) => Icon(
                    PhosphorIcons.storefront(PhosphorIconsStyle.regular),
                    color: AppTheme.primaryOrange,
                    size: 40,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                flex: 60,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      l10n.translate('sell_on_et'),
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        color: AppTheme.primaryOrange,
                        fontSize: 15,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      l10n.translate('sell_marquee'),
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w500,
                        color: AppTheme.subtleGrey,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMenuCard(List<Widget> children) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Container(decoration: AppTheme.cardDecoration, child: Column(children: children)),
    );
  }

  Widget _buildMenuItem({required IconData icon, required String title, required VoidCallback onTap, bool isDestructive = false}) {
    final textTheme = Theme.of(context).textTheme;
    final iconColor = isDestructive ? AppTheme.strongRed : AppTheme.premiumBlack.withOpacity(0.65);
    final textStyle = isDestructive
        ? textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600, color: AppTheme.strongRed, fontSize: 14)
        : textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600, color: AppTheme.premiumBlack, fontSize: 14);
    return ListTile(
      leading: Icon(icon, color: iconColor, size: 20),
      title: Text(title, style: textStyle),
      trailing: Icon(PhosphorIcons.caretRight(PhosphorIconsStyle.regular), color: Colors.grey.shade400, size: 18),
      onTap: onTap,
      contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 2),
      minLeadingWidth: 24,
      dense: true,
      visualDensity: VisualDensity.compact,
      hoverColor: AppTheme.primaryOrange.withOpacity(0.04),
      splashColor: AppTheme.primaryOrange.withOpacity(0.08),
    );
  }

  void _navigateToPlaceholder(String title) {
    Navigator.push(context, MaterialPageRoute(builder: (_) => Scaffold(appBar: AppBar(title: Text(title)), body: Center(child: Text('$title Screen\nComing Soon')))));
  }
}
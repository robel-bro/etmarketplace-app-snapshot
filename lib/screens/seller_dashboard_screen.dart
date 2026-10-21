// 📁 lib/screens/seller_dashboard_screen.dart
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:intl/intl.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import '../api/client.dart';
import '../theme/app_theme.dart';
import '../l10n/app_localizations.dart';
import 'add_product_screen.dart';
import 'create_package_screen.dart';
import 'seller_products_screen.dart';
import 'seller_orders_screen.dart';
import 'seller_packages_screen.dart';
import 'seller_analytics_screen.dart';
import 'seller/membership_page.dart';
import 'seller/payouts_page.dart';
import 'seller/settings_screen.dart';
import 'all_reviews_page.dart';

final RouteObserver<ModalRoute<void>> routeObserver =
    RouteObserver<ModalRoute<void>>();

class SellerDashboardScreen extends StatefulWidget {
  const SellerDashboardScreen({Key? key}) : super(key: key);
  @override
  State<SellerDashboardScreen> createState() => _SellerDashboardScreenState();
}

class _SellerDashboardScreenState extends State<SellerDashboardScreen> {
  int _currentIndex = 0;

  Map<String, dynamic>? _stats;
  List<Map<String, dynamic>> _recentOrders = [];
  Map<String, dynamic> _payoutSummary = {};

  bool _isLoading = true;
  String? _error;
  String? _dashboardError;   // ★ separate dashboard error

  String _vendorLogo = '';
  String _vendorName = 'My Shop';
  String _vendorEmail = '';
  String _vendorPhone = '';
  bool _vendorVerified = false;
  int? _vendorId;

  bool _isOpen = true;
  DateTime? _reopenAt;

  bool _isToggling = false;

  double _commissionRate = 0;
  double _totalCommissions = 0;
  List<Map<String, dynamic>> _categoryRates = [];

  double _returnShippingPenalties = 0;
  int _refundedOrdersCount = 0;
  double _totalRefundedAmount = 0;

  static String get _apiBaseUrl => kIsWeb
      ? 'http://localhost:3000'
      : (dotenv.env['API_BASE_URL'] ?? 'http://10.0.2.2:3000');

  @override
  void initState() {
    super.initState();
    _fetchAllData();
    Future.delayed(const Duration(seconds: 1), () {
      if (mounted) _fetchVendorProfile();
    });
  }

  // ── helpers ──
  String _safeString(dynamic val) => val?.toString() ?? '';
  int _safeInt(dynamic val) => (val as num?)?.toInt() ?? 0;
  double _safeDouble(dynamic val) {
    if (val == null) return 0.0;
    if (val is num) return val.toDouble();
    if (val is String) return double.tryParse(val) ?? 0.0;
    return 0.0;
  }
  bool _safeBool(dynamic val) => val == true || val == 'true';

  String _formatCurrency(dynamic value) {
    final amount = _safeDouble(value);
    final formatter = NumberFormat('#,##0.00', 'en_US');
    return 'ETB ${formatter.format(amount)}';
  }

  String _formatInteger(dynamic value) {
    final number = _safeInt(value);
    final formatter = NumberFormat('#,###', 'en_US');
    return formatter.format(number);
  }

  Future<void> _fetchVendorProfile() async {
    if (!ApiClient.hasToken) return;
    try {
      final res = await ApiClient.instance.get('/api/v1/vendors/me');
      final v = res.data;
      if (mounted) {
        setState(() {
          _vendorName = _safeString(v['business_name']);
          _vendorEmail = _safeString(v['email']);
          _vendorPhone = _safeString(v['phone']);
          _vendorLogo = _safeString(v['logo_url']);
          _vendorVerified = _safeBool(v['verified']);
          _vendorId = _safeInt(v['id']);
        });
      }
    } catch (_) {}
  }

  Future<void> _toggleShop() async {
    if (_isToggling) return;
    setState(() => _isToggling = true);
    try {
      final payload = <String, dynamic>{};
      if (!_isOpen && _reopenAt != null) {
        payload['reopen_at'] = _reopenAt!.toIso8601String();
      }
      final res = await ApiClient.instance.post('/seller/toggle_shop', data: payload);
      if (mounted) {
        setState(() {
          _isOpen = _safeBool(res.data['is_open']);
          _reopenAt = res.data['reopen_at'] != null ? DateTime.tryParse(_safeString(res.data['reopen_at'])) : null;
        });
        _fetchAllData();
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to toggle shop.')),
        );
      }
    } finally {
      if (mounted) setState(() => _isToggling = false);
    }
  }

  Future<void> _pickReopenDateTime() async {
    final date = await showDatePicker(
      context: context,
      initialDate: _reopenAt ?? DateTime.now().add(const Duration(days: 1)),
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (date == null) return;
    if (!mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: _reopenAt != null ? TimeOfDay.fromDateTime(_reopenAt!) : const TimeOfDay(hour: 9, minute: 0),
    );
    if (time == null) return;
    setState(() {
      _reopenAt = DateTime(date.year, date.month, date.day, time.hour, time.minute);
    });
  }

  Future<void> _fetchAllData() async {
    setState(() {
      _isLoading = true;
      _error = null;
      _dashboardError = null;
    });

    // ── Dashboard data ──
    try {
      final dashRes = await ApiClient.instance.get('/seller/dashboard');
      final dash = dashRes.data;
      debugPrint('Dashboard response: $dash');

      final isOpen = _safeBool(dash['is_open']);
      final reopenAt = dash['reopen_at'] != null
          ? DateTime.tryParse(_safeString(dash['reopen_at']))
          : null;

      final rawRecentOrders = (dash['recent_orders'] as List?)
              ?.cast<Map<String, dynamic>>() ?? [];

      // Fetch images for recent orders (optional)
      final List<Future<Map<String, dynamic>?>> detailFutures = [];
      for (final o in rawRecentOrders) {
        final orderId = _safeInt(o['id']);
        detailFutures.add(
          ApiClient.instance.get('/orders/$orderId').then((res) => res.data as Map<String, dynamic>).catchError((_) => null),
        );
      }
      final details = await Future.wait(detailFutures);

      final recentWithImages = <Map<String, dynamic>>[];
      for (int i = 0; i < rawRecentOrders.length; i++) {
        final o = rawRecentOrders[i];
        final orderId = _safeInt(o['id']);
        final price = _safeDouble(o['total']);
        final detail = details[i];
        String imageUrl = '';
        if (detail != null) {
          final items = detail['items'] as List? ?? [];
          imageUrl = items.isNotEmpty ? (items.first['image'] ?? '') : '';
        }
        if (imageUrl.isNotEmpty && imageUrl.startsWith('/')) {
          imageUrl = '$_apiBaseUrl$imageUrl';
        }
        if (imageUrl.isEmpty) imageUrl = 'https://placehold.co/100x100?text=No+Image';

        recentWithImages.add({
          'id': '#ORD-$orderId',
          'name': 'Order $orderId',
          'price': _formatCurrency(price),
          'status': _safeString(o['status']),
          'payment_status': _safeString(o['payment_status']),
          'image': imageUrl,
        });
      }

      if (mounted) {
        setState(() {
          _stats = dash;
          _isOpen = isOpen;
          _reopenAt = reopenAt;
          _recentOrders = recentWithImages;
          _commissionRate = _safeDouble(dash['commission_rate']);
          _totalCommissions = _safeDouble(dash['total_commissions']);
          _categoryRates = (dash['category_commission_rates'] as List?)
                  ?.map((e) => Map<String, dynamic>.from(e as Map))
                  .toList() ?? [];
          _returnShippingPenalties = _safeDouble(dash['total_return_shipping_penalties']);
          _refundedOrdersCount = _safeInt(dash['refunded_orders_count']);
          _totalRefundedAmount = _safeDouble(dash['total_refunded_amount']);
          _dashboardError = null;
        });
      }
    } catch (e) {
      debugPrint('Dashboard error: $e');
      if (mounted) {
        setState(() {
          _stats = null;
          _dashboardError = 'Failed to load dashboard data. Please try again.';
        });
      }
    }

    // ── Payout summary (independent) ──
    try {
      final payoutRes = await ApiClient.instance.get('/seller/payouts');
      if (mounted) {
        setState(() {
          _payoutSummary = payoutRes.data['summary'] ?? {};
        });
      }
    } catch (_) {}

    if (mounted) {
      setState(() => _isLoading = false);
    }
  }

  void _exitShop() {
    Navigator.pop(context);
    Navigator.of(context).pushNamedAndRemoveUntil('/main', (route) => false);
  }

  Color _statusColor(String status) {
    switch (status.toLowerCase()) {
      case 'delivered':
      case 'completed':
        return AppColors.success;
      case 'shipped':
        return AppColors.info;
      case 'accepted':
      case 'processing':
        return AppColors.primary;
      case 'pending':
      case 'pending_acceptance':
        return AppColors.warning;
      case 'cancelled':
        return AppColors.error;
      default:
        return AppColors.textSecondary;
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final textTheme = Theme.of(context).textTheme;

    if (_isLoading) {
      return Scaffold(
        backgroundColor: AppColors.pageBackground,
        appBar: _buildAppBar(textTheme, l10n),
        drawer: _buildDrawer(textTheme, l10n),
        body: const Center(child: CircularProgressIndicator(color: AppColors.primary)),
      );
    }

    return Scaffold(
      backgroundColor: AppColors.pageBackground,
      appBar: _buildAppBar(textTheme, l10n),
      drawer: _buildDrawer(textTheme, l10n),
      body: AnimatedSwitcher(
        duration: const Duration(milliseconds: 300),
        child: IndexedStack(
          key: ValueKey(_currentIndex),
          index: _currentIndex,
          children: [
            _buildOverviewTab(textTheme, l10n),
            const SellerProductsScreen(),
            const SellerOrdersScreen(),
            const SellerPackagesScreen(),
            const SellerSettingsScreen(),
          ],
        ),
      ),
      bottomNavigationBar: SafeArea(child: _buildBottomNav(textTheme, l10n)),
    );
  }

  AppBar _buildAppBar(TextTheme textTheme, AppLocalizations l10n) {
    return AppBar(
      backgroundColor: AppColors.cardBackground,
      elevation: 0,
      leading: Builder(
        builder: (context) => IconButton(
          icon: const Icon(Icons.menu_rounded, color: AppColors.textPrimary),
          onPressed: () => Scaffold.of(context).openDrawer(),
        ),
      ),
      title: Row(
        children: [
          CircleAvatar(
            radius: 16,
            backgroundColor: Colors.grey.shade200,
            backgroundImage: _vendorLogo.isNotEmpty ? NetworkImage(_vendorLogo) : null,
            child: _vendorLogo.isEmpty
                ? Text(
                    _vendorName.isNotEmpty ? _vendorName[0].toUpperCase() : 'S',
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: AppColors.textMuted),
                  )
                : null,
          ),
          const SizedBox(width: 10),
          Flexible(child: Text(_vendorName, style: textTheme.titleMedium?.copyWith(color: AppColors.textPrimary, fontWeight: FontWeight.w700), overflow: TextOverflow.ellipsis)),
          if (_vendorVerified) ...[const SizedBox(width: 6), Icon(Icons.verified, size: 18, color: Colors.blue.shade600)],
        ],
      ),
      actions: [
        Stack(children: [
          IconButton(icon: const Icon(Icons.notifications_outlined, color: AppColors.textPrimary), onPressed: () => Navigator.pushNamed(context, '/notifications')),
          Positioned(right: 10, top: 10, child: Container(width: 8, height: 8, decoration: const BoxDecoration(color: AppColors.error, shape: BoxShape.circle))),
        ]),
      ],
    );
  }

  Widget _buildDrawer(TextTheme textTheme, AppLocalizations l10n) {
    final formattedPhone = _vendorPhone.replaceAll(RegExp(r'\D'), '').length == 10 ? '+251 ${_vendorPhone.substring(1,3)} ${_vendorPhone.substring(3,6)} ${_vendorPhone.substring(6)}' : _vendorPhone;
    return Drawer(
      backgroundColor: AppColors.pageBackground,
      child: SafeArea(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Padding(padding: const EdgeInsets.only(left: AppSpacing.xs, top: AppSpacing.xs), child: IconButton(icon: const Icon(Icons.arrow_back_rounded, color: AppColors.textPrimary), onPressed: () => Navigator.pop(context))),
          const SizedBox(height: AppSpacing.xs),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(children: [
              CircleAvatar(
                radius: 30,
                backgroundColor: Colors.grey.shade200,
                backgroundImage: _vendorLogo.isNotEmpty ? NetworkImage(_vendorLogo) : null,
                child: _vendorLogo.isEmpty
                    ? Text(
                        _vendorName.isNotEmpty ? _vendorName[0].toUpperCase() : 'S',
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 22, color: AppColors.textMuted),
                      )
                    : null,
              ),
              const SizedBox(width: 16),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [Flexible(child: Text(_vendorName, style: textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700, color: AppColors.textPrimary), overflow: TextOverflow.ellipsis, maxLines: 1)), if (_vendorVerified) ...[const SizedBox(width: 6), Icon(Icons.verified, size: 18, color: Colors.blue.shade600)]]),
                const SizedBox(height: 4),
                if (_vendorEmail.isNotEmpty) Text(_vendorEmail, style: textTheme.bodySmall?.copyWith(color: AppColors.textMuted), overflow: TextOverflow.ellipsis),
                if (formattedPhone.isNotEmpty) ...[const SizedBox(height: 2), Text(formattedPhone, style: textTheme.bodySmall?.copyWith(color: AppColors.textMuted, fontWeight: FontWeight.w500))],
              ])),
            ]),
          ),
          const SizedBox(height: 20), const Divider(height: 1, color: AppColors.borderLight), const SizedBox(height: 8),
          _drawerItem(icon: Icons.add_circle_outlined, text: l10n.translate('add_product'), onTap: () { Navigator.pop(context); Navigator.push(context, MaterialPageRoute(builder: (_) => const AddProductScreen())); }, textTheme: textTheme),
          _drawerItem(icon: Icons.inventory_2_outlined, text: l10n.translate('create_package'), onTap: () { Navigator.pop(context); Navigator.push(context, MaterialPageRoute(builder: (_) => const CreatePackageScreen())); }, textTheme: textTheme),
          _drawerItem(icon: Icons.receipt_long_outlined, text: l10n.translate('view_orders'), onTap: () { Navigator.pop(context); setState(() => _currentIndex = 2); }, textTheme: textTheme),
          _drawerItem(icon: Icons.account_balance_wallet_outlined, text: l10n.translate('payouts'), onTap: () { Navigator.pop(context); Navigator.push(context, MaterialPageRoute(builder: (_) => const SellerPayoutsScreen())); }, textTheme: textTheme),
          _drawerItem(icon: Icons.bar_chart_outlined, text: l10n.translate('analytics'), onTap: () { Navigator.pop(context); Navigator.push(context, MaterialPageRoute(builder: (_) => const SellerAnalyticsScreen())); }, textTheme: textTheme),
          _drawerItem(icon: Icons.card_membership_outlined, text: l10n.translate('membership'), onTap: () { Navigator.pop(context); Navigator.push(context, MaterialPageRoute(builder: (_) => const MembershipPage())); }, textTheme: textTheme),
          _drawerItem(icon: Icons.settings_outlined, text: l10n.translate('store_settings'), onTap: () { Navigator.pop(context); Navigator.push(context, MaterialPageRoute(builder: (_) => const SellerSettingsScreen())); }, textTheme: textTheme),
          const Spacer(),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
            child: InkWell(
              onTap: _exitShop,
              borderRadius: BorderRadius.circular(AppShapes.radiusMd),
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
                decoration: BoxDecoration(color: AppColors.hoverState, borderRadius: BorderRadius.circular(AppShapes.radiusMd)),
                child: Row(children: [Icon(Icons.exit_to_app, color: AppColors.error, size: 22), const SizedBox(width: 16), Text(l10n.translate('exit_shop'), style: textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w600, color: AppColors.error))]),
              ),
            ),
          ),
          const SizedBox(height: 16),
        ]),
      ),
    );
  }

  Widget _drawerItem({required IconData icon, required String text, required VoidCallback onTap, required TextTheme textTheme}) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
      child: InkWell(onTap: onTap, borderRadius: BorderRadius.circular(AppShapes.radiusMd), child: Container(padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16), decoration: BoxDecoration(color: AppColors.hoverState, borderRadius: BorderRadius.circular(AppShapes.radiusMd)), child: Row(children: [Icon(icon, color: AppColors.textPrimary.withOpacity(0.7), size: 22), const SizedBox(width: 16), Flexible(child: Text(text, style: textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w600, color: AppColors.textPrimary), maxLines: 1, overflow: TextOverflow.ellipsis))]))),
    );
  }

  Widget _buildBottomNav(TextTheme textTheme, AppLocalizations l10n) {
    return Container(
      decoration: BoxDecoration(color: AppColors.cardBackground, boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.06), blurRadius: 16, offset: const Offset(0, -2))]),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: [
          _navItem(icon: PhosphorIcons.squaresFour(PhosphorIconsStyle.regular), activeIcon: PhosphorIcons.squaresFour(PhosphorIconsStyle.fill), label: l10n.translate('seller_dashboard'), index: 0, textTheme: textTheme),
          _navItem(icon: PhosphorIcons.shoppingBag(PhosphorIconsStyle.regular), activeIcon: PhosphorIcons.shoppingBag(PhosphorIconsStyle.fill), label: l10n.translate('seller_products'), index: 1, textTheme: textTheme),
          _navItem(icon: PhosphorIcons.receipt(PhosphorIconsStyle.regular), activeIcon: PhosphorIcons.receipt(PhosphorIconsStyle.fill), label: l10n.translate('seller_orders'), index: 2, textTheme: textTheme),
          _navItem(icon: PhosphorIcons.gift(PhosphorIconsStyle.regular), activeIcon: PhosphorIcons.gift(PhosphorIconsStyle.fill), label: l10n.translate('seller_packages'), index: 3, textTheme: textTheme),
          _navItem(icon: PhosphorIcons.gear(PhosphorIconsStyle.regular), activeIcon: PhosphorIcons.gear(PhosphorIconsStyle.fill), label: l10n.translate('seller_settings'), index: 4, textTheme: textTheme),
        ]),
      ),
    );
  }

  Widget _navItem({required PhosphorIconData icon, required PhosphorIconData activeIcon, required String label, required int index, required TextTheme textTheme}) {
    final isActive = _currentIndex == index;
    return GestureDetector(
      onTap: () => setState(() => _currentIndex = index),
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(color: isActive ? AppColors.primary.withOpacity(0.08) : Colors.transparent, borderRadius: BorderRadius.circular(AppShapes.radiusSm)),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          PhosphorIcon(isActive ? activeIcon : icon, color: isActive ? AppColors.primary : AppColors.textPrimary, size: 20),
          const SizedBox(height: 2),
          Text(label, style: textTheme.bodySmall?.copyWith(fontSize: 10, fontWeight: isActive ? FontWeight.w700 : FontWeight.w500, color: isActive ? AppColors.primary : AppColors.textPrimary)),
        ]),
      ),
    );
  }

  Widget _quickActionCard({required IconData icon, required String title, required VoidCallback onTap, required Color iconBgColor, required TextTheme textTheme}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
        decoration: BoxDecoration(
          color: AppColors.cardBackground,
          borderRadius: BorderRadius.circular(AppShapes.radiusMd),
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 8, offset: const Offset(0, 2))],
        ),
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          Container(width: 44, height: 44, decoration: BoxDecoration(color: iconBgColor.withOpacity(0.1), shape: BoxShape.circle), child: Icon(icon, color: iconBgColor, size: 22)),
          const SizedBox(height: 8),
          Text(title, style: textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w600, color: AppColors.textPrimary), textAlign: TextAlign.center, maxLines: 2, overflow: TextOverflow.ellipsis),
        ]),
      ),
    );
  }

  bool _showCategoryRates = false;

  Widget _buildOverviewTab(TextTheme textTheme, AppLocalizations l10n) {
    // If dashboard data failed, show error with retry
    if (_dashboardError != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.error_outline, size: 48, color: AppColors.error),
              const SizedBox(height: 16),
              Text(_dashboardError!, textAlign: TextAlign.center,
                  style: textTheme.bodyLarge?.copyWith(color: AppColors.error)),
              const SizedBox(height: 24),
              ElevatedButton.icon(
                onPressed: _fetchAllData,
                icon: const Icon(Icons.refresh),
                label: Text(l10n.translate('retry')),
              ),
            ],
          ),
        ),
      );
    }

    final totalOrders = _formatInteger(_stats?['total_orders']);
    final totalRevenue = _formatCurrency(_stats?['total_revenue']);
    final earnings = _formatCurrency(_stats?['total_earnings']);
    final avgOrder = _formatCurrency(_stats?['average_order_value']);
    final availablePayout = _formatCurrency(_payoutSummary['available']);
    final revenueByMonth = _stats?['revenue_by_month'] as Map<String, dynamic>? ?? {};
    final recent = _recentOrders.take(5).toList();

    return RefreshIndicator(
      onRefresh: _fetchAllData,
      color: AppColors.primary,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(AppSpacing.md, AppSpacing.xs, AppSpacing.md, 24),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          // Shop status card
          Container(
            padding: const EdgeInsets.all(AppSpacing.md),
            decoration: BoxDecoration(
              color: AppColors.cardBackground,
              borderRadius: BorderRadius.circular(AppShapes.radiusMd),
              boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 8, offset: const Offset(0, 2))],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(l10n.translate('shop_status'), style: textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
                    GestureDetector(
                      onTap: _isToggling ? null : _toggleShop,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                        decoration: BoxDecoration(
                          color: _isOpen ? const Color(0xFF16A34A) : Colors.transparent,
                          borderRadius: BorderRadius.circular(AppShapes.radiusSm),
                          border: Border.all(
                            color: _isOpen ? const Color(0xFF16A34A) : AppColors.borderLight,
                            width: 1.5,
                          ),
                        ),
                        child: _isToggling
                            ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.primary))
                            : Text(
                                _isOpen ? l10n.translate('shop_open') : l10n.translate('shop_closed'),
                                style: TextStyle(
                                  color: _isOpen ? Colors.white : AppColors.textSecondary,
                                  fontWeight: FontWeight.w700,
                                  fontSize: 13,
                                ),
                              ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  _isOpen
                      ? 'Your shop is open — customers can place orders.'
                      : 'Your shop is on a break — products remain visible and can be added to cart, but checkout is paused until you reopen.',
                  style: textTheme.bodySmall?.copyWith(color: AppColors.textMuted),
                ),
                if (!_isOpen && _reopenAt != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    l10n.translate('reopens_at').replaceAll('{datetime}', DateFormat('MMM d, yyyy – hh:mm a').format(_reopenAt!)),
                    style: textTheme.bodySmall?.copyWith(color: AppColors.textSecondary, fontWeight: FontWeight.w600),
                  ),
                ],
                if (!_isOpen)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: _pickReopenDateTime,
                        icon: const Icon(Icons.schedule, size: 18),
                        label: Text(l10n.translate('set_reopen_time')),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppColors.primary,
                          side: const BorderSide(color: AppColors.primary, width: 1.5),
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppShapes.radiusSm)),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.md),

          // Commission rate cards
          Row(children: [
            Expanded(child: _statCard('Commission Rate', '$_commissionRate%', Icons.percent, AppColors.primary, textTheme)),
            const SizedBox(width: AppSpacing.xs),
            Expanded(child: _statCard('Total Commissions Paid', _formatCurrency(_totalCommissions), Icons.money_off, AppColors.primary, textTheme)),
          ]),
          const SizedBox(height: AppSpacing.sm),

          // Deduction/Refund cards
          Row(children: [
            Expanded(child: _statCard('Return Shipping Penalties', _formatCurrency(_returnShippingPenalties), Icons.warning_amber_rounded, AppColors.error, textTheme)),
            const SizedBox(width: AppSpacing.xs),
            Expanded(child: _statCard('Refunded Orders', '$_refundedOrdersCount', Icons.assignment_return, AppColors.primary, textTheme)),
            const SizedBox(width: AppSpacing.xs),
            Expanded(child: _statCard('Total Refunded', _formatCurrency(_totalRefundedAmount), Icons.money_off, AppColors.primary, textTheme)),
          ]),
          const SizedBox(height: AppSpacing.sm),

          // Collapsible category commission list
          if (_categoryRates.isNotEmpty)
            Container(
              decoration: BoxDecoration(
                color: AppColors.cardBackground,
                borderRadius: BorderRadius.circular(AppShapes.radiusMd),
                boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 8, offset: const Offset(0, 2))],
              ),
              child: Column(
                children: [
                  InkWell(
                    onTap: () => setState(() => _showCategoryRates = !_showCategoryRates),
                    borderRadius: BorderRadius.circular(AppShapes.radiusMd),
                    child: Padding(
                      padding: const EdgeInsets.all(AppSpacing.md),
                      child: Row(
                        children: [
                          const Icon(Icons.percent, size: 18, color: Colors.purple),
                          const SizedBox(width: 8),
                          Expanded(child: Text('Commission by Category', style: textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600, color: AppColors.textPrimary))),
                          Icon(_showCategoryRates ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down, color: AppColors.textMuted),
                        ],
                      ),
                    ),
                  ),
                  AnimatedCrossFade(
                    firstChild: const SizedBox.shrink(),
                    secondChild: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                      child: Column(
                        children: _categoryRates.map((cat) => Padding(
                          padding: const EdgeInsets.symmetric(vertical: 4),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Flexible(child: Text(_safeString(cat['category_name']), style: textTheme.bodySmall?.copyWith(color: AppColors.textSecondary))),
                              Text('${_safeDouble(cat['commission_rate'])}%', style: textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
                            ],
                          ),
                        )).toList(),
                      ),
                    ),
                    crossFadeState: _showCategoryRates ? CrossFadeState.showSecond : CrossFadeState.showFirst,
                    duration: const Duration(milliseconds: 200),
                  ),
                ],
              ),
            ),

          const SizedBox(height: AppSpacing.sm),

          // Stats row 1
          Row(children: [
            Expanded(child: _statCard(l10n.translate('orders_label'), totalOrders, Icons.shopping_bag_outlined, AppColors.primary, textTheme)),
            const SizedBox(width: AppSpacing.xs),
            Expanded(child: _statCard(l10n.translate('revenue_label'), totalRevenue, Icons.attach_money, AppColors.primary, textTheme)),
            const SizedBox(width: AppSpacing.xs),
            Expanded(child: _statCard(l10n.translate('earnings_label'), earnings, Icons.wallet, AppColors.primary, textTheme)),
          ]),
          const SizedBox(height: AppSpacing.sm),
          Row(children: [
            Expanded(child: _statCard(l10n.translate('avg_order_label'), avgOrder, Icons.trending_up, AppColors.success, textTheme)),
            const SizedBox(width: AppSpacing.xs),
            Expanded(child: _statCard(l10n.translate('available_label'), availablePayout, Icons.account_balance_wallet, AppColors.info, textTheme)),
          ]),
          const SizedBox(height: AppSpacing.lg),
          Text(l10n.translate('revenue_overview'), style: textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
          const SizedBox(height: AppSpacing.sm),
          Container(
            padding: const EdgeInsets.all(AppSpacing.md),
            decoration: BoxDecoration(
              color: AppColors.cardBackground,
              borderRadius: BorderRadius.circular(AppShapes.radiusMd),
              boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 8, offset: const Offset(0, 2))],
            ),
            height: 240,
            child: _buildRevenueLineChart(revenueByMonth, l10n),
          ),
          const SizedBox(height: AppSpacing.lg),
          Text(l10n.translate('quick_actions'), style: textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
          const SizedBox(height: AppSpacing.sm),
          Row(children: [
            Expanded(child: _quickActionCard(icon: Icons.add_circle_outline, title: l10n.translate('add_product'), onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const AddProductScreen())), iconBgColor: AppColors.primary, textTheme: textTheme)),
            const SizedBox(width: AppSpacing.xs),
            Expanded(child: _quickActionCard(icon: Icons.inventory_2_outlined, title: l10n.translate('create_package'), onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const CreatePackageScreen())), iconBgColor: AppColors.info, textTheme: textTheme)),
            const SizedBox(width: AppSpacing.xs),
            Expanded(child: _quickActionCard(icon: Icons.receipt_long_outlined, title: l10n.translate('view_orders'), onTap: () => setState(() => _currentIndex = 2), iconBgColor: AppColors.warning, textTheme: textTheme)),
            const SizedBox(width: AppSpacing.xs),
            Expanded(child: _quickActionCard(icon: Icons.account_balance_wallet_outlined, title: l10n.translate('payouts'), onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const SellerPayoutsScreen())), iconBgColor: const Color(0xFFEC4899), textTheme: textTheme)),
          ]),
          const SizedBox(height: AppSpacing.md),
          Row(children: [
            Expanded(child: _quickActionCard(icon: Icons.bar_chart_outlined, title: l10n.translate('analytics'), onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const SellerAnalyticsScreen())), iconBgColor: AppColors.warning, textTheme: textTheme)),
            const SizedBox(width: AppSpacing.xs),
            Expanded(child: _quickActionCard(icon: Icons.card_membership_outlined, title: l10n.translate('membership'), onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const MembershipPage())), iconBgColor: AppColors.success, textTheme: textTheme)),
            const SizedBox(width: AppSpacing.xs),
            Expanded(child: _quickActionCard(icon: Icons.list_alt_outlined, title: l10n.translate('manage_products'), onTap: () => setState(() => _currentIndex = 1), iconBgColor: const Color(0xFF8B5CF6), textTheme: textTheme)),
            const SizedBox(width: AppSpacing.xs),
            Expanded(child: _quickActionCard(icon: Icons.settings_outlined, title: l10n.translate('store_settings'), onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const SellerSettingsScreen())), iconBgColor: AppColors.textMuted, textTheme: textTheme)),
          ]),
          const SizedBox(height: AppSpacing.md),
          Row(children: [
            Expanded(child: _quickActionCard(
              icon: Icons.reviews_outlined,
              title: l10n.translate('shop_reviews'),
              onTap: () {
                if (_vendorId != null) {
                  Navigator.push(context, MaterialPageRoute(builder: (_) => AllReviewsPage(vendorId: _vendorId!)));
                } else {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text(l10n.translate('vendor_profile_not_loaded'))),
                  );
                }
              },
              iconBgColor: AppColors.starGold,
              textTheme: textTheme,
            )),
            const SizedBox(width: AppSpacing.xs),
            const Expanded(child: SizedBox()),
            const SizedBox(width: AppSpacing.xs),
            const Expanded(child: SizedBox()),
            const SizedBox(width: AppSpacing.xs),
            const Expanded(child: SizedBox()),
          ]),
          const SizedBox(height: AppSpacing.lg),
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            Text(l10n.translate('recent_orders'), style: textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
            TextButton(onPressed: () => setState(() => _currentIndex = 2), child: Text(l10n.translate('see_all'), style: textTheme.bodyMedium?.copyWith(color: AppColors.primary, fontWeight: FontWeight.w600))),
          ]),
          const SizedBox(height: AppSpacing.xs),
          ...recent.map((o) => _orderCard(o, textTheme, l10n)),
        ]),
      ),
    );
  }

  Widget _statCard(String label, String value, IconData icon, Color color, TextTheme textTheme) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.sm),
      decoration: BoxDecoration(
        color: AppColors.cardBackground,
        borderRadius: BorderRadius.circular(AppShapes.radiusMd),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 8, offset: const Offset(0, 2))],
      ),
      child: Column(children: [
        Icon(icon, color: color, size: 22),
        const SizedBox(height: AppSpacing.xs),
        Text(value, style: textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700, color: AppColors.textPrimary, fontSize: 14), maxLines: 1, overflow: TextOverflow.ellipsis),
        const SizedBox(height: 2),
        Text(label, style: textTheme.bodySmall?.copyWith(color: AppColors.textMuted, fontSize: 11)),
      ]),
    );
  }

  Widget _buildRevenueLineChart(Map<String, dynamic> data, AppLocalizations l10n) {
    if (data.isEmpty)
      return Center(child: Text(l10n.translate('no_revenue_data'), style: const TextStyle(color: AppColors.textMuted, fontSize: 13)));

    final entries = data.entries.toList()..sort((a, b) => a.key.compareTo(b.key));
    final spots = <FlSpot>[];
    double maxVal = 0;
    for (int i = 0; i < entries.length; i++) {
      final val = entries[i].value;
      final y = val is double ? val : val is int ? val.toDouble() : double.tryParse(val.toString()) ?? 0.0;
      if (y > maxVal) maxVal = y;
      spots.add(FlSpot(i.toDouble(), y));
    }

    final niceMaxY = maxVal == 0 ? 1000.0 : ((maxVal * 1.2) / 500).ceil() * 500.0;

    return LineChart(
      LineChartData(
        gridData: FlGridData(
          show: true,
          drawVerticalLine: false,
          getDrawingHorizontalLine: (value) => FlLine(color: AppColors.borderLight.withOpacity(0.6), strokeWidth: 0.5),
        ),
        titlesData: FlTitlesData(
          rightTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
          topTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 28,
              getTitlesWidget: (value, meta) {
                final idx = value.toInt();
                if (idx >= 0 && idx < entries.length) {
                  final key = entries[idx].key;
                  final label = key.length >= 7 ? key.substring(5) : key;
                  return Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(label, style: const TextStyle(fontSize: 10, color: AppColors.textMuted, fontWeight: FontWeight.w500)),
                  );
                }
                return const SizedBox.shrink();
              },
            ),
          ),
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 56,
              getTitlesWidget: (value, meta) => Text('${value.toInt()}', style: const TextStyle(fontSize: 10, color: AppColors.textMuted)),
            ),
          ),
        ),
        borderData: FlBorderData(show: false),
        minY: 0,
        maxY: niceMaxY,
        lineBarsData: [
          LineChartBarData(
            spots: spots,
            isCurved: true,
            gradient: const LinearGradient(colors: [AppColors.primary, AppColors.primaryActive]),
            barWidth: 3,
            isStrokeCapRound: true,
            dotData: FlDotData(
              show: true,
              getDotPainter: (spot, percent, barData, index) => FlDotCirclePainter(
                radius: 4,
                color: AppColors.primary,
                strokeWidth: 2,
                strokeColor: Colors.white,
              ),
            ),
            belowBarData: BarAreaData(
              show: true,
              gradient: LinearGradient(
                colors: [
                  AppColors.primary.withOpacity(0.3),
                  AppColors.primary.withOpacity(0.05),
                ],
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
              ),
            ),
          ),
        ],
        lineTouchData: LineTouchData(
          touchTooltipData: LineTouchTooltipData(
            getTooltipItems: (touchedSpots) => touchedSpots.map((spot) {
              final idx = spot.spotIndex;
              final month = entries[idx].key;
              return LineTooltipItem(
                '$month\n${_formatCurrency(spot.y)}',
                const TextStyle(color: Colors.white, fontSize: 12),
              );
            }).toList(),
          ),
        ),
      ),
    );
  }

  Widget _orderCard(Map<String, dynamic> o, TextTheme textTheme, AppLocalizations l10n) {
    final status = _safeString(o['status']);
    final name = _safeString(o['name']);
    final price = _safeString(o['price']);
    final image = _safeString(o['image']);
    final paymentStatus = _safeString(o['payment_status']);
    final statusColor = _statusColor(status);

    return Container(
      margin: const EdgeInsets.only(bottom: AppSpacing.xs),
      padding: const EdgeInsets.all(AppSpacing.sm),
      decoration: BoxDecoration(
        color: AppColors.cardBackground,
        borderRadius: BorderRadius.circular(AppShapes.radiusMd),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 6, offset: const Offset(0, 2))],
      ),
      child: Row(children: [
        ClipRRect(borderRadius: BorderRadius.circular(AppShapes.radiusSm), child: Image.network(image, width: 48, height: 48, fit: BoxFit.cover, errorBuilder: (_, __, ___) => Container(width: 48, height: 48, decoration: BoxDecoration(color: AppColors.hoverState, borderRadius: BorderRadius.circular(AppShapes.radiusSm)), child: const Icon(Icons.image, size: 24)))),
        const SizedBox(width: AppSpacing.sm),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(name, style: textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600, color: AppColors.textPrimary), maxLines: 1, overflow: TextOverflow.ellipsis),
          const SizedBox(height: 2),
          Row(children: [
            Text(price, style: textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700, color: AppColors.textPrimary, fontSize: 14)),
            const SizedBox(width: 8),
            if (paymentStatus == 'refunded')
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: AppColors.error.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(AppShapes.radiusSm),
                ),
                child: const Text('Refunded', style: TextStyle(fontSize: 10, color: AppColors.error, fontWeight: FontWeight.w700)),
              ),
          ]),
        ])),
        const SizedBox(width: AppSpacing.xs),
        Text(
          status,
          style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: statusColor),
        ),
      ]),
    );
  }
}
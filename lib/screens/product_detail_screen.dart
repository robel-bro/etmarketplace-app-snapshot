// lib/screens/product_detail_screen.dart
import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:shimmer/shimmer.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:collection/collection.dart';
import 'package:flutter_staggered_grid_view/flutter_staggered_grid_view.dart';
import 'package:video_player/video_player.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../api/client.dart';
import '../models/product.dart';
import '../models/cart.dart';
import '../providers/cart_provider.dart';
import '../providers/wishlist_provider.dart';
import '../providers/compare_provider.dart';
import '../providers/bottom_bar_visibility.dart';
import '../providers/auth_provider.dart';
import '../theme/app_theme.dart';
import '../widgets/product_card.dart';
import '../utils/format_utils.dart';
import '../utils/url_utils.dart';
import '../services/checkout_service.dart';
import '../l10n/app_localizations.dart';
import 'checkout_screen.dart';
import 'search_screen.dart';
import 'cart_screen.dart';
import 'wishlist_screen.dart';
import 'compare_screen.dart';
import '../widgets/review_list_widget.dart';
import 'all_reviews_page.dart';

final vendorDetailsProvider = FutureProvider.family<Map<String, dynamic>?, int>((ref, vendorId) async {
  try {
    final res = await ApiClient.instance.get('/api/v1/vendors/$vendorId');
    return res.data as Map<String, dynamic>;
  } catch (_) {
    return null;
  }
});

final productProvider = FutureProvider.family<Product, int>((ref, id) async {
  final response = await ApiClient.instance.get('/products/$id');
  return Product.fromJson(response.data);
});

const Map<String, String> colorMap = {
  'red': '#EF4444', 'blue': '#3B82F6', 'green': '#10B981', 'black': '#1F2937',
  'white': '#F9FAFB', 'yellow': '#F59E0B', 'purple': '#8B5CF6', 'pink': '#EC4899',
  'orange': '#F97316', 'grey': '#6B7280', 'gray': '#6B7280', 'brown': '#92400E',
  'navy': '#1E3A8A', 'beige': '#F5F5DC', 'gold': '#D97706', 'silver': '#9CA3AF',
};
Color getColorFromName(String name) {
  final clean = name.trim().toLowerCase();
  if (colorMap.containsKey(clean)) {
    final hex = colorMap[clean]!;
    return Color(int.parse('FF${hex.substring(1)}', radix: 16));
  }
  if (clean.startsWith('#') && (clean.length == 7 || clean.length == 4)) {
    try { return Color(int.parse('FF${clean.substring(1)}', radix: 16)); } catch (_) {}
  }
  int hash = 0;
  for (int i = 0; i < clean.length; i++) { hash = clean.codeUnitAt(i) + ((hash << 5) - hash); }
  final h = (hash % 360).toDouble();
  return HSLColor.fromAHSL(1.0, h, 0.6, 0.7).toColor();
}

class _AnimatedDeliveryLabel extends StatefulWidget {
  final String label;
  final Color textColor;
  final double fontSize;
  final FontWeight fontWeight;
  const _AnimatedDeliveryLabel({
    required this.label,
    this.textColor = Colors.white,
    this.fontSize = 12,
    this.fontWeight = FontWeight.w700,
  });
  @override State<_AnimatedDeliveryLabel> createState() => _AnimatedDeliveryLabelState();
}
class _AnimatedDeliveryLabelState extends State<_AnimatedDeliveryLabel>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<Offset> _animation;
  bool _needsAnimation = false;
  double _textWidth = 0;
  double _containerWidth = 0;

  @override void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: const Duration(seconds: 6));
    WidgetsBinding.instance.addPostFrameCallback((_) => _measure());
  }

  void _measure() {
    if (!mounted) return;
    final textStyle = TextStyle(
      color: widget.textColor,
      fontSize: widget.fontSize,
      fontWeight: widget.fontWeight,
    );
    final painter = TextPainter(
      text: TextSpan(text: widget.label, style: textStyle),
      maxLines: 1,
      textDirection: TextDirection.ltr,
    )..layout();

    final containerWidth = (context.findRenderObject() as RenderBox?)?.size.width ?? double.infinity;
    final textWidth = painter.width;

    if (textWidth > containerWidth) {
      setState(() {
        _needsAnimation = true;
        _textWidth = textWidth;
        _containerWidth = containerWidth;
      });
      _animation = Tween<Offset>(
        begin: Offset(containerWidth / textWidth, 0),
        end: const Offset(-1.0, 0),
      ).animate(_controller)
        ..addStatusListener((status) {
          if (status == AnimationStatus.completed) {
            _controller.reset();
            _controller.forward();
          }
        });
      _controller.forward();
    }
  }

  @override void dispose() { _controller.dispose(); super.dispose(); }

  @override Widget build(BuildContext context) {
    if (!_needsAnimation) {
      return Text(widget.label, style: TextStyle(color: widget.textColor, fontSize: widget.fontSize, fontWeight: widget.fontWeight));
    }
    return ClipRect(
      child: SizedBox(
        height: 20,
        child: Align(
          alignment: Alignment.centerLeft,
          child: SlideTransition(
            position: _animation,
            child: Text(
              widget.label,
              style: TextStyle(color: widget.textColor, fontSize: widget.fontSize, fontWeight: widget.fontWeight),
            ),
          ),
        ),
      ),
    );
  }
}

class _MediaItem {
  final String url;
  final String type;
  const _MediaItem({required this.url, required this.type});
}

class _DealCountdown extends StatefulWidget {
  final DateTime endsAt;
  const _DealCountdown({required this.endsAt});
  @override State<_DealCountdown> createState() => _DealCountdownState();
}
class _DealCountdownState extends State<_DealCountdown> {
  late Timer _timer;
  Duration _remaining = Duration.zero;

  @override void initState() {
    super.initState();
    _updateRemaining();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) => _updateRemaining());
  }
  @override void dispose() { _timer.cancel(); super.dispose(); }
  void _updateRemaining() {
    final diff = widget.endsAt.difference(DateTime.now());
    if (mounted) setState(() => _remaining = diff.isNegative ? Duration.zero : diff);
  }
  @override Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    if (_remaining == Duration.zero)
      return Text(l10n.translate('product_expired'), style: const TextStyle(color: Colors.red, fontSize: 12));
    final h = _remaining.inHours;
    final m = _remaining.inMinutes.remainder(60);
    final s = _remaining.inSeconds.remainder(60);
    return Text(
      l10n.translate('product_time_left')
          .replaceAll('{hours}', h.toString())
          .replaceAll('{minutes}', m.toString())
          .replaceAll('{seconds}', s.toString()),
      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Colors.red),
    );
  }
}

class ProductDetailScreen extends ConsumerStatefulWidget {
  final int productId;
  final bool fromCompany;
  final int? companyId;

  const ProductDetailScreen({
    Key? key,
    required this.productId,
    this.fromCompany = false,
    this.companyId,
  }) : super(key: key);

  @override
  ConsumerState<ProductDetailScreen> createState() => _ProductDetailScreenState();
}

class _ProductDetailScreenState extends ConsumerState<ProductDetailScreen>
    with TickerProviderStateMixin, WidgetsBindingObserver {
  int _currentImageIndex = 0;
  String _selectedTab = 'overview';
  final ScrollController _scrollController = ScrollController();
  bool _isCartActionInProgress = false;
  bool _isProgrammaticScroll = false;
  static const List<String> _tabKeys = ['overview', 'description', 'reviews', 'recommendations'];
  late AnimationController _searchBarFadeController, _heartAnimationController;
  late Animation<double> _searchBarFadeAnimation, _imageIconsFadeAnimation, _heartScaleAnimation;
  bool _showTabs = false;
  late TabController _tabController;
  final PageController _mediaPageController = PageController();
  static const double _searchBarStartFade = 30.0, _searchBarFullFade = 100.0, _imageHeight = 420.0, _tabsAppearThreshold = 250.0;
  List<Product> _similarProducts = []; bool _isLoadingSimilar = true;
  String? _vendorLogoUrl; Map<String, dynamic>? _vendorDetails;
  bool _hasPriceAlert = false; double? _existingAlertTarget;
  double? _sellerLat, _sellerLng, _buyerLat, _buyerLng; String? _deliveryEstimateText;

  String? _shippingEstimateText;
  bool _isShippingEstimateLoading = false;

  Map<String, String> _selectedVariant = {};
  List<String> _selectionOrder = [];
  int _quantity = 1;

  int _reviewRefreshCounter = 0;

  VideoPlayerController? _activeVideoController;
  int? _activeVideoIndex;
  bool _videoInitialized = false;

  bool _showSkipOverlay = false;
  bool _skipForward = true;
  Timer? _skipOverlayTimer;
  bool _longPressActive = false;
  double _normalSpeed = 1.0;

  List<_MediaItem> _mediaItems = [];

  bool _hasTrackedView = false;

  int get _minOrderQuantity {
    final p = product;
    if (p != null && p.bulkEnabled && p.minimumBulkQuantity != null) {
      return p.minimumBulkQuantity!;
    }
    return 1;
  }

  bool get _isUnlimitedStock {
    final p = product;
    if (p == null) return false;
    if (_hasVariants && _isCompleteSelection) {
      final v = _findVariant(p);
      if (v != null) {
        return v['unlimited_stock'] == true || v['stock'] == null || v['stock'] == '';
      }
    }
    return p.availableStock == null;
  }

  int get _maxOrderQuantity {
    final p = product;
    if (p == null) return 0;

    int physicalLimit;
    if (_hasVariants && _isCompleteSelection) {
      final v = _findVariant(p);
      if (v != null) {
        if (v['unlimited_stock'] == true || v['stock'] == null || v['stock'] == '') {
          physicalLimit = 999999;
        } else {
          final rawStock = v['stock'];
          physicalLimit = rawStock is num ? rawStock.toInt() : int.tryParse(rawStock?.toString() ?? '') ?? 0;
        }
      } else {
        physicalLimit = 0;
      }
    } else if (_isUnlimitedStock) {
      physicalLimit = 999999;
    } else {
      physicalLimit = p.availableStock ?? 0;
    }

    final dailyCap = p.remainingDailyQuantity;
    if (dailyCap != null) {
      return min(physicalLimit, dailyCap);
    }
    return physicalLimit;
  }

  bool get _isBulk => product?.bulkEnabled ?? false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    bottomBarVisibility.value = false;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) ref.invalidate(productProvider(widget.productId));
    });
    _searchBarFadeController = AnimationController(vsync: this, duration: const Duration(milliseconds: 150));
    _heartAnimationController = AnimationController(vsync: this, duration: const Duration(milliseconds: 300));
    _searchBarFadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(CurvedAnimation(parent: _searchBarFadeController, curve: Curves.easeOut));
    _imageIconsFadeAnimation = Tween<double>(begin: 1.0, end: 0.0).animate(CurvedAnimation(parent: _searchBarFadeController, curve: Curves.easeOut));
    _heartScaleAnimation = Tween<double>(begin: 1.0, end: 1.4).animate(CurvedAnimation(parent: _heartAnimationController, curve: Curves.elasticOut));
    _tabController = TabController(length: _tabKeys.length, vsync: this); _tabController.addListener(_onTabChanged); _scrollController.addListener(_onScroll);
    _checkPriceAlert();
    WidgetsBinding.instance.addPostFrameCallback((_) { _syncCartState(); _loadSimilarProducts(); });
  }

  @override void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {}
  }

  @override void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    bottomBarVisibility.value = true;
    _disposeVideoPlayer();
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    _searchBarFadeController.dispose();
    _heartAnimationController.dispose();
    _tabController.removeListener(_onTabChanged);
    _tabController.dispose();
    _mediaPageController.dispose();
    super.dispose();
  }

  void _buildMediaItems(Product p) {
    _mediaItems = [];
    for (final url in p.videoUrls) {
      _mediaItems.add(_MediaItem(url: resolveUrl(url), type: 'video'));
    }
    for (final url in p.images) {
      _mediaItems.add(_MediaItem(url: resolveUrl(url), type: 'image'));
    }
    if (_mediaItems.isEmpty) {
      _mediaItems.add(_MediaItem(url: 'https://placehold.co/600x400?text=No+Image', type: 'image'));
    }
  }

  Future<void> _checkPriceAlert() async {
    try {
      final res = await ApiClient.instance.get('/price_alerts');
      final List data = res.data is List ? res.data : (res.data['data'] ?? []);
      final alert = data.cast<Map<String,dynamic>>().firstWhereOrNull((a) => a['product_id'] == widget.productId);
      if (mounted) {
        setState(() {
          _hasPriceAlert = alert != null;
          _existingAlertTarget = alert?['target_price']?.toDouble();
        });
      }
    } catch (_) {}
  }

  Future<void> _showPriceAlertSheet(Product product) async {
    final l10n = AppLocalizations.of(context);
    final controller = TextEditingController(text: _existingAlertTarget?.toStringAsFixed(0) ?? '');
    final emailController = TextEditingController();
    final formKey = GlobalKey<FormState>();
    final result = await showModalBottomSheet<String?>(
      context: context, backgroundColor: Colors.transparent, isScrollControlled: true,
      builder: (ctx) {
        return Container(
          padding: EdgeInsets.only(left: 24, right: 24, top: 24, bottom: MediaQuery.of(ctx).viewInsets.bottom + 24),
          decoration: const BoxDecoration(color: AppColors.cardBackground, borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
          child: Form(
            key: formKey,
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              Center(child: Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.grey.shade400, borderRadius: BorderRadius.circular(2)))),
              const SizedBox(height: 20),
              Text(_hasPriceAlert ? l10n.translate('product_price_alert_update_title') : l10n.translate('product_price_alert_title'), style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
              const SizedBox(height: 6),
              Text(_hasPriceAlert ? l10n.translate('product_price_alert_update_desc') : l10n.translate('product_price_alert_desc'), style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AppColors.textMuted)),
              const SizedBox(height: 20),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(color: AppColors.primary.withOpacity(0.05), borderRadius: BorderRadius.circular(12), border: Border.all(color: AppColors.primary.withOpacity(0.2))),
                child: Row(children: [
                  const Icon(Icons.info_outline, size: 18, color: AppColors.primary),
                  const SizedBox(width: 8),
                  Expanded(child: Text(l10n.translate('product_price_alert_current_price').replaceAll('{price}', (product.effectivePrice ?? product.price).toStringAsFixed(2)), style: Theme.of(context).textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w600))),
                ]),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: controller, keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  labelText: l10n.translate('product_price_alert_target_label'), hintText: 'e.g. 1,500', prefixText: 'ETB ',
                  filled: true, fillColor: const Color(0xFFF9F9F9),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppColors.borderLight)),
                  enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppColors.borderLight)),
                  focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppColors.primary, width: 2)),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                ),
                validator: (v) {
                  if (v == null || v.trim().isEmpty) return l10n.translate('product_price_alert_invalid_price');
                  final price = double.tryParse(v.trim());
                  if (price == null || price <= 0) return l10n.translate('product_price_alert_invalid_price');
                  return null;
                },
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: emailController, keyboardType: TextInputType.emailAddress,
                decoration: InputDecoration(
                  labelText: l10n.translate('product_price_alert_email_label'), hintText: 'you@example.com',
                  filled: true, fillColor: const Color(0xFFF9F9F9),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppColors.borderLight)),
                  enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppColors.borderLight)),
                  focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppColors.primary, width: 2)),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                ),
                validator: (v) {
                  if (v == null || v.trim().isEmpty || !v.contains('@')) return l10n.translate('product_price_alert_invalid_email');
                  return null;
                },
              ),
              const SizedBox(height: 24),
              Row(children: [
                if (_hasPriceAlert) Expanded(child: OutlinedButton.icon(
                  onPressed: () => Navigator.pop(ctx, 'delete'),
                  icon: const Icon(Icons.delete_outline, size: 18), label: Text(l10n.translate('product_price_alert_remove')),
                  style: OutlinedButton.styleFrom(foregroundColor: AppColors.error, side: BorderSide(color: AppColors.error, width: 1.5), padding: const EdgeInsets.symmetric(vertical: 14), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                )),
                if (_hasPriceAlert) const SizedBox(width: 12),
                Expanded(child: ElevatedButton.icon(
                  onPressed: () { if (formKey.currentState!.validate()) Navigator.pop(ctx, controller.text.trim() + '|' + emailController.text.trim()); },
                  icon: Icon(_hasPriceAlert ? Icons.update : Icons.notifications_active, size: 18),
                  label: Text(_hasPriceAlert ? l10n.translate('product_price_alert_update') : l10n.translate('product_price_alert_set')),
                  style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary, foregroundColor: Colors.white, elevation: 2, shadowColor: AppColors.primary.withOpacity(0.3), padding: const EdgeInsets.symmetric(vertical: 14), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)), textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800)),
                )),
              ]),
            ]),
          ),
        );
      },
    );
    if (result == 'delete') { await _deletePriceAlert(); }
    else if (result != null) {
      final parts = result.split('|');
      final targetPrice = double.tryParse(parts[0]);
      final email = parts.length > 1 ? parts[1] : '';
      if (targetPrice != null && targetPrice > 0 && email.isNotEmpty) {
        await _setPriceAlert(targetPrice, email);
      }
    }
  }

  Future<void> _setPriceAlert(double targetPrice, String email) async {
    final l10n = AppLocalizations.of(context);
    try {
      await ApiClient.instance.post('/price_alerts', data: {'product_id': widget.productId, 'target_price': targetPrice, 'email': email});
      _checkPriceAlert();
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(l10n.translate('product_price_alert_set_success')), backgroundColor: AppColors.primary));
    } catch (_) {}
  }

  Future<void> _deletePriceAlert() async {
    final l10n = AppLocalizations.of(context);
    try {
      final res = await ApiClient.instance.get('/price_alerts');
      final List data = res.data is List ? res.data : (res.data['data'] ?? []);
      final alert = data.cast<Map<String, dynamic>>().firstWhereOrNull((a) => a['product_id'] == widget.productId);
      if (alert != null) {
        await ApiClient.instance.delete('/price_alerts/${alert['id']}');
        _checkPriceAlert();
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(l10n.translate('product_price_alert_removed')), backgroundColor: Colors.grey));
      }
    } catch (_) {}
  }

  Future<void> _loadSimilarProducts() async {
    try {
      final response = await ApiClient.instance.get('/products/${widget.productId}/similar');
      final List data = response.data is List ? response.data : [];
      final List<Product> newProducts = data
          .map((json) => Product.fromJson(json))
          .where((p) => p.id != widget.productId)
          .toList();
      if (mounted) {
        setState(() {
          _similarProducts = newProducts;
          _isLoadingSimilar = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isLoadingSimilar = false);
    }
  }

  Future<void> _trackRecentlyViewed() async {
    if (_hasTrackedView) return;
    _hasTrackedView = true;
    try {
      final auth = ref.read(authProvider);
      if (auth != null) {
        await ApiClient.instance.post('/api/v1/recently_vieweds', data: {'product_id': widget.productId});
      } else {
        final prefs = await SharedPreferences.getInstance();
        const key = 'recently_viewed_product_ids';
        final productIdStr = widget.productId.toString();
        final existing = prefs.getStringList(key) ?? [];
        existing.remove(productIdStr);
        existing.insert(0, productIdStr);
        if (existing.length > 20) existing.removeRange(20, existing.length);
        await prefs.setStringList(key, existing);
      }
    } catch (_) {}
  }

  Future<void> _calculateDeliveryEstimate() async {
    final l10n = AppLocalizations.of(context);
    if (_vendorDetails != null) {
      _sellerLat = _vendorDetails!['latitude']?.toDouble();
      _sellerLng = _vendorDetails!['longitude']?.toDouble();
    }
    try {
      final res = await ApiClient.instance.get('/addresses');
      final List addresses = res.data is List ? res.data : [];
      if (addresses.isNotEmpty) {
        final addr = addresses.first;
        _buyerLat = addr['latitude']?.toDouble();
        _buyerLng = addr['longitude']?.toDouble();
      }
    } catch (_) {}
    if (_sellerLat != null && _sellerLng != null && _buyerLat != null && _buyerLng != null) {
      final distance = _haversine(_sellerLat!, _sellerLng!, _buyerLat!, _buyerLng!);
      if (distance < 1) {
        _deliveryEstimateText = l10n.translate('product_delivery_less_1km');
      } else {
        final minutes = (distance / 30.0 * 60).round();
        _deliveryEstimateText = l10n.translate('product_delivery_estimate_label')
            .replaceAll('{distance}', distance.toStringAsFixed(1))
            .replaceAll('{minutes}', minutes.toString());
      }
    } else if (_vendorDetails != null && _vendorDetails!['delivery_days'] != null) {
      _deliveryEstimateText = l10n.translate('product_delivery_estimate_days')
          .replaceAll('{days}', _vendorDetails!['delivery_days'].toString());
    } else {
      _deliveryEstimateText = l10n.translate('product_delivery_not_available');
    }
    if (mounted) setState(() {});
  }

  Future<void> _fetchShippingEstimate(int vendorId) async {
    final user = ref.read(authProvider);
    if (user == null) return;

    if (mounted) setState(() => _isShippingEstimateLoading = true);
    try {
      final addrRes = await ApiClient.instance.get('/addresses');
      final List addresses = addrRes.data is List ? addrRes.data : [];
      final defaultAddr = addresses.cast<Map<String,dynamic>?>().firstWhereOrNull((a) => a?['is_default'] == true)
          ?? addresses.firstOrNull;
      if (defaultAddr == null) return;

      final estimateRes = await ApiClient.instance.get('/shipping_estimate', queryParameters: {
        'vendor_id': vendorId,
        'address_id': defaultAddr['id'],
      });
      final options = estimateRes.data['options'] as List? ?? [];
      if (options.isNotEmpty) {
        final fastest = options.first;
        if (mounted) {
          setState(() {
            _shippingEstimateText = 'Est. delivery: ${fastest['partner_name']} – ${fastest['estimated_days']} day(s)';
          });
        }
      }
    } catch (_) {
    } finally {
      if (mounted) setState(() => _isShippingEstimateLoading = false);
    }
  }

  double _haversine(double lat1, double lon1, double lat2, double lon2) {
    const R = 6371.0;
    final dLat = _toRadians(lat2 - lat1);
    final dLon = _toRadians(lon2 - lon1);
    final a = sin(dLat / 2) * sin(dLat / 2) + cos(_toRadians(lat1)) * cos(_toRadians(lat2)) * sin(dLon / 2) * sin(dLon / 2);
    final c = 2 * atan2(sqrt(a), sqrt(1 - a));
    return R * c;
  }
  double _toRadians(double degree) => degree * pi / 180.0;

  void _onTabChanged() {
    if (!_tabController.indexIsChanging) return;
    final newTab = _tabKeys[_tabController.index];
    if (_selectedTab != newTab) {
      if (mounted) setState(() => _selectedTab = newTab);
      _scrollToTabSection(_tabController.index);
    }
  }

  void _onScroll() {
    final currentOffset = _scrollController.offset;
    _searchBarFadeController.value = ((currentOffset - _searchBarStartFade) / (_searchBarFullFade - _searchBarStartFade)).clamp(0.0, 1.0);
    final showTabs = currentOffset >= _tabsAppearThreshold;
    if (showTabs != _showTabs) {
      if (mounted) setState(() => _showTabs = showTabs);
    }
    if (!_isProgrammaticScroll) _updateSelectedTabByScrollPosition();
  }

  void _updateSelectedTabByScrollPosition() {}

  void _scrollToTabSection(int index) async {
    final offset = index * 500.0;
    await _scrollController.animateTo(offset, duration: const Duration(milliseconds: 350), curve: Curves.easeOutCubic);
  }

  void _navigateToSearch() => Navigator.push(context, MaterialPageRoute(builder: (_) => const SearchScreen()));

  void _showShareSheet() {
    final l10n = AppLocalizations.of(context);
    final productLink = 'https://yourapp.com/product/${widget.productId}';
    Share.share(
      l10n.translate('product_share_subject').replaceAll('{link}', productLink),
      subject: product?.title ?? 'Product',
    );
  }

  void _animateHeart() => _heartAnimationController.forward().then((_) => _heartAnimationController.reverse());

  void _openImageZoom(List<String> images, int index, int productId) {
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => _FullScreenImageViewer(images: images, initialIndex: index, productId: productId)));
  }

  void _initializeVideo(int index, String url) {
    _disposeVideoPlayer();
    final controller = VideoPlayerController.networkUrl(Uri.parse(url));
    _activeVideoController = controller;
    _activeVideoIndex = index;
    _videoInitialized = false;
    _normalSpeed = 1.0;
    controller.addListener(() {
      if (!mounted) return;
      final value = controller.value;
      if (value.hasError) {
        _disposeVideoPlayer();
        return;
      }
      if (!_videoInitialized && value.isInitialized) {
        if (mounted) setState(() => _videoInitialized = true);
        controller.play();
      } else if (value.isPlaying || value.isBuffering) {
        if (mounted) setState(() {});
      }
    });
    controller.initialize().then((_) {
      if (mounted) {
        setState(() => _videoInitialized = true);
        controller.play();
      }
    }).catchError((_) {
      if (mounted) _disposeVideoPlayer();
    });
  }

  void _disposeVideoPlayer() {
    _activeVideoController?.removeListener(() {});
    _activeVideoController?.dispose();
    _activeVideoController = null;
    _activeVideoIndex = null;
    _videoInitialized = false;
    _longPressActive = false;
    if (mounted) setState(() {});
  }

  void _togglePlayPause() {
    if (_activeVideoController == null) return;
    if (mounted) {
      setState(() {
        if (_activeVideoController!.value.isPlaying) {
          _activeVideoController!.pause();
        } else {
          _activeVideoController!.play();
        }
      });
    }
  }

  void _seekRelative(int seconds) {
    if (_activeVideoController != null && _activeVideoController!.value.isInitialized) {
      final newPos = _activeVideoController!.value.position + Duration(seconds: seconds);
      final target = newPos < Duration.zero ? Duration.zero : newPos > _activeVideoController!.value.duration ? _activeVideoController!.value.duration : newPos;
      _activeVideoController!.seekTo(target);
    }
  }

  void _startLongPress() {
    if (_activeVideoController != null && _activeVideoController!.value.isPlaying) {
      if (mounted) setState(() => _longPressActive = true);
      _activeVideoController!.setPlaybackSpeed(2.0);
    }
  }

  void _endLongPress() {
    if (_activeVideoController != null && _longPressActive) {
      _activeVideoController!.setPlaybackSpeed(_normalSpeed);
      if (mounted) setState(() => _longPressActive = false);
    }
  }

  void _triggerSkipOverlay(bool forward) {
    if (mounted) {
      setState(() {
        _skipForward = forward;
        _showSkipOverlay = true;
      });
    }
    _skipOverlayTimer?.cancel();
    _skipOverlayTimer = Timer(const Duration(milliseconds: 800), () {
      if (mounted) setState(() => _showSkipOverlay = false);
    });
  }

  String _formatDuration(Duration d) {
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    final hours = twoDigits(d.inHours), minutes = twoDigits(d.inMinutes.remainder(60)), seconds = twoDigits(d.inSeconds.remainder(60));
    return d.inHours > 0 ? '$hours:$minutes:$seconds' : '$minutes:$seconds';
  }

  Widget _buildInlineVideoControls() {
    if (_activeVideoController == null) return const SizedBox.shrink();
    final video = _activeVideoController!.value;
    return Positioned(
      left: 0, right: 0, bottom: 0,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.bottomCenter, end: Alignment.topCenter,
            colors: [Colors.black.withOpacity(0.8), Colors.transparent],
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            if (_mediaItems.length > 1)
              Container(
                margin: const EdgeInsets.only(right: 8),
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(12)),
                child: Text('${_currentImageIndex + 1}/${_mediaItems.length}',
                    style: const TextStyle(color: Colors.white, fontSize: 11)),
              ),
            Text(_formatDuration(video.position),
                style: const TextStyle(color: Colors.white, fontSize: 11)),
            Expanded(
              child: SliderTheme(
                data: SliderTheme.of(context).copyWith(
                  trackHeight: 4,
                  thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 8),
                  overlayShape: const RoundSliderOverlayShape(overlayRadius: 16),
                  activeTrackColor: AppColors.primary,
                  inactiveTrackColor: Colors.white30,
                  thumbColor: AppColors.primary,
                  overlayColor: AppColors.primary.withOpacity(0.3),
                ),
                child: Slider(
                  value: video.position.inMilliseconds.clamp(0, video.duration.inMilliseconds).toDouble(),
                  max: video.duration.inMilliseconds.toDouble().clamp(1.0, double.infinity),
                  onChanged: (v) { _activeVideoController?.seekTo(Duration(milliseconds: v.toInt())); },
                ),
              ),
            ),
            Text(_formatDuration(video.duration),
                style: const TextStyle(color: Colors.white, fontSize: 11)),
            const SizedBox(width: 4),
            IconButton(
              padding: EdgeInsets.zero, constraints: const BoxConstraints(),
              icon: const Icon(Icons.fullscreen, color: Colors.white, size: 24),
              onPressed: () async {
                if (_activeVideoController == null) return;
                final url = _mediaItems[_activeVideoIndex!].url;
                final position = _activeVideoController!.value.position;
                _disposeVideoPlayer();
                if (!mounted) return;
                await Navigator.push(context, MaterialPageRoute(builder: (_) => _VideoPlayerScreen(url: url)));
                if (mounted) {
                  _initializeVideoAtPosition(_activeVideoIndex!, url, position);
                }
              },
            ),
            Consumer(builder: (_, ref, __) {
              final wishlist = ref.watch(wishlistProvider);
              final isWishlisted = wishlist.any((item) => item.productId == widget.productId);
              return IconButton(
                padding: EdgeInsets.zero, constraints: const BoxConstraints(),
                icon: Icon(
                  isWishlisted ? Icons.favorite_rounded : Icons.favorite_border_rounded,
                  color: isWishlisted ? AppColors.error : Colors.white,
                  size: 22,
                ),
                onPressed: () async {
                  _animateHeart();
                  final notifier = ref.read(wishlistProvider.notifier);
                  if (isWishlisted) {
                    await notifier.removeItem(widget.productId);
                  } else {
                    final active = _findVariant(product!);
                    final Map<String, String>? variantMap;
                    if (active != null && active['attributes'] is Map) {
                      variantMap = (active['attributes'] as Map).map((k, v) => MapEntry(k.toString(), v.toString()));
                    } else {
                      variantMap = null;
                    }
                    await notifier.addItem(product!, variant: variantMap);
                  }
                },
              );
            }),
          ],
        ),
      ),
    );
  }

  void _initializeVideoAtPosition(int index, String url, Duration position) {
    _disposeVideoPlayer();
    final controller = VideoPlayerController.networkUrl(Uri.parse(url));
    _activeVideoController = controller;
    _activeVideoIndex = index;
    _videoInitialized = false;
    _normalSpeed = 1.0;
    controller.addListener(() {
      if (!mounted) return;
      final value = controller.value;
      if (value.hasError) {
        _disposeVideoPlayer();
        return;
      }
      if (!_videoInitialized && value.isInitialized) {
        if (mounted) setState(() => _videoInitialized = true);
        controller.seekTo(position);
        controller.play();
      }
    });
    controller.initialize().then((_) {
      if (mounted) {
        setState(() => _videoInitialized = true);
        controller.seekTo(position);
        controller.play();
      }
    }).catchError((_) {
      if (mounted) _disposeVideoPlayer();
    });
  }

  Widget _buildMediaCarousel() {
    if (_mediaItems.isEmpty) return const SizedBox.shrink();
    return Column(children: [
      SizedBox(
        height: _imageHeight,
        child: Stack(children: [
          PageView.builder(
            controller: _mediaPageController,
            physics: _activeVideoController != null
                ? const NeverScrollableScrollPhysics()
                : const PageScrollPhysics(),
            onPageChanged: (index) {
              if (mounted) setState(() => _currentImageIndex = index);
              if (_activeVideoIndex != null && _activeVideoIndex != index) {
                _disposeVideoPlayer();
              }
            },
            itemCount: _mediaItems.length,
            itemBuilder: (context, index) {
              final item = _mediaItems[index];
              if (item.type == 'image') {
                return GestureDetector(
                  onTap: () => _openImageZoom(
                    _mediaItems.where((m) => m.type == 'image').map((m) => m.url).toList(),
                    _mediaItems.where((m) => m.type == 'image').toList().indexOf(item),
                    widget.productId,
                  ),
                  child: CachedNetworkImage(
                    imageUrl: item.url, fit: BoxFit.cover, width: double.infinity,
                    placeholder: (_, __) => Shimmer.fromColors(baseColor: Colors.grey.shade200, highlightColor: Colors.grey.shade100, child: Container(color: Colors.white)),
                    errorWidget: (_, __, ___) => Container(color: Colors.grey.shade100, child: Icon(Icons.broken_image, color: AppColors.textMuted)),
                  ),
                );
              } else {
                final isPlaying = _activeVideoIndex == index && _activeVideoController != null;
                if (isPlaying && _videoInitialized) {
                  return Stack(fit: StackFit.expand, children: [
                    Positioned.fill(
                      child: AspectRatio(
                        aspectRatio: _activeVideoController!.value.aspectRatio,
                        child: VideoPlayer(_activeVideoController!),
                      ),
                    ),
                    Positioned.fill(
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: _togglePlayPause,
                        onDoubleTapDown: (details) {
                          final halfWidth = (context.size?.width ?? 0) / 2;
                          final tapX = details.localPosition.dx;
                          if (tapX < halfWidth) {
                            _seekRelative(-10);
                            _triggerSkipOverlay(false);
                          } else {
                            _seekRelative(10);
                            _triggerSkipOverlay(true);
                          }
                        },
                        onLongPressStart: (_) => _startLongPress(),
                        onLongPressEnd: (_) => _endLongPress(),
                        child: Container(color: Colors.transparent),
                      ),
                    ),
                    _buildInlineVideoControls(),
                    if (_showSkipOverlay)
                      Align(
                        alignment: _skipForward ? Alignment.centerRight : Alignment.centerLeft,
                        child: Container(
                          margin: const EdgeInsets.symmetric(horizontal: 24),
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(12)),
                          child: Row(mainAxisSize: MainAxisSize.min, children: [
                            Icon(_skipForward ? Icons.fast_forward_rounded : Icons.fast_rewind_rounded, color: Colors.white, size: 32),
                            const SizedBox(width: 6),
                            const Text('10 s', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18)),
                          ]),
                        ),
                      ),
                  ]);
                } else if (isPlaying && !_videoInitialized) {
                  return const Center(child: CircularProgressIndicator(color: Colors.white));
                } else {
                  return GestureDetector(
                    onTap: () => _initializeVideo(index, item.url),
                    child: Container(
                      color: Colors.black,
                      child: Stack(fit: StackFit.expand, children: [
                        if (_mediaItems.any((m) => m.type == 'image'))
                          CachedNetworkImage(imageUrl: _mediaItems.firstWhere((m) => m.type == 'image').url, fit: BoxFit.cover),
                        Center(
                          child: Container(width: 64, height: 64, decoration: BoxDecoration(color: Colors.white.withOpacity(0.9), shape: BoxShape.circle),
                            child: const Icon(Icons.play_arrow, size: 40, color: AppColors.primary),
                          ),
                        ),
                      ]),
                    ),
                  );
                }
              }
            },
          ),
          if (_activeVideoController == null)
            Positioned(
              bottom: 12, right: AppSpacing.xs,
              child: FadeTransition(
                opacity: _imageIconsFadeAnimation,
                child: Consumer(builder: (_, ref, __) {
                  final wishlist = ref.watch(wishlistProvider);
                  final isWishlisted = wishlist.any((item) => item.productId == widget.productId);
                  return _TransparentIcon(
                    icon: isWishlisted ? Icons.favorite_rounded : Icons.favorite_border_rounded,
                    onTap: () async {
                      _animateHeart();
                      final notifier = ref.read(wishlistProvider.notifier);
                      if (isWishlisted) {
                        await notifier.removeItem(widget.productId);
                      } else {
                        final active = _findVariant(product!);
                        final Map<String, String>? variantMap;
                        if (active != null && active['attributes'] is Map) {
                          variantMap = (active['attributes'] as Map).map((k, v) => MapEntry(k.toString(), v.toString()));
                        } else {
                          variantMap = null;
                        }
                        await notifier.addItem(product!, variant: variantMap);
                      }
                    },
                    iconColor: isWishlisted ? AppColors.error : Colors.white,
                  );
                }),
              ),
            ),
          if (_activeVideoController == null && _mediaItems.length > 1)
            Positioned(
              bottom: 12, left: AppSpacing.xs,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(20)),
                child: Text('${_currentImageIndex + 1}/${_mediaItems.length}', style: const TextStyle(color: Colors.white, fontSize: 12)),
              ),
            ),
        ]),
      ),
      if (_mediaItems.length > 1)
        Container(
          height: 60, margin: const EdgeInsets.only(top: 8),
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs),
            itemCount: _mediaItems.length,
            itemBuilder: (ctx, i) {
              final item = _mediaItems[i];
              final isSelected = i == _currentImageIndex;
              return GestureDetector(
                onTap: () {
                  _mediaPageController.animateToPage(i, duration: const Duration(milliseconds: 300), curve: Curves.easeOut);
                  if (_activeVideoIndex != null && _activeVideoIndex != i) _disposeVideoPlayer();
                },
                child: Container(
                  width: 56, height: 56, margin: const EdgeInsets.symmetric(horizontal: 2),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(AppShapes.radiusSm),
                    border: Border.all(color: isSelected ? AppColors.primary : AppColors.borderLight, width: isSelected ? 2 : 1),
                  ),
                  child: Stack(fit: StackFit.expand, children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(AppShapes.radiusSm - 1),
                      child: item.type == 'image'
                          ? CachedNetworkImage(imageUrl: item.url, fit: BoxFit.cover, errorWidget: (_, __, ___) => Container(color: Colors.grey.shade200))
                          : Container(color: Colors.grey.shade300),
                    ),
                    if (item.type == 'video')
                      Center(child: Icon(Icons.play_arrow, size: 20, color: Colors.white.withOpacity(0.8))),
                  ]),
                ),
              );
            },
          ),
        ),
    ]);
  }

  List<String> get _variantKeys {
    if (product == null || product!.variants.isEmpty) return [];
    final keys = <String>{};
    for (final v in product!.variants) {
      final attrs = v['attributes'] as Map<String, dynamic>? ?? {};
      for (final entry in attrs.entries) {
        if (entry.value.toString().isNotEmpty) {
          keys.add(entry.key);
        }
      }
    }
    return keys.toList();
  }

  Map<String, List<String>> _allValuesMap(Product p) {
    final map = <String, List<String>>{};
    for (final key in _variantKeys) {
      map[key] = p.variants
          .map((v) => ((v['attributes'] as Map<String, dynamic>?)?[key]?.toString() ?? ''))
          .where((v) => v.isNotEmpty)
          .toSet()
          .toList();
    }
    return map;
  }

  List<Map<String, dynamic>> _availableVariants(Product p) {
    if (p.variants.isEmpty) return [];
    return p.variants.where((v) {
      final attrs = v['attributes'] as Map<String, dynamic>? ?? {};
      return _selectedVariant.entries.every((e) => e.value.isEmpty || attrs[e.key] == e.value);
    }).toList();
  }

  Map<String, List<String>> _allowedValuesMap(Product p) {
    final available = _availableVariants(p);
    final map = <String, List<String>>{};
    for (final key in _variantKeys) {
      map[key] = available
          .map((v) => ((v['attributes'] as Map<String, dynamic>?)?[key]?.toString() ?? ''))
          .where((v) => v.isNotEmpty)
          .toSet()
          .toList();
    }
    return map;
  }

  Map<String, dynamic>? _findVariant(Product p) {
    if (p.variants.isEmpty || _selectedVariant.isEmpty) return null;
    for (final v in p.variants) {
      final attrs = v['attributes'] as Map<String, dynamic>? ?? {};
      if (_selectedVariant.entries.every((e) => attrs[e.key] == e.value)) return v;
    }
    return null;
  }

  bool get _hasVariants => _variantKeys.isNotEmpty;
  bool get _isCompleteSelection => _hasVariants ? _findVariant(product!) != null : true;

  double? get _dealPrice {
    final p = product;
    if (p == null) return null;
    if (p.isFlashSale && p.flashSalePrice != null && p.flashSaleEndsAt != null && p.flashSaleEndsAt!.isAfter(DateTime.now())) {
      return p.flashSalePrice;
    }
    if (p.isSuperDeal && p.superDealPrice != null && p.superDealEndsAt != null && p.superDealEndsAt!.isAfter(DateTime.now())) {
      return p.superDealPrice;
    }
    return null;
  }

  DateTime? get _dealEndsAt {
    final p = product;
    if (p == null) return null;
    if (p.isFlashSale && p.flashSaleEndsAt != null && p.flashSaleEndsAt!.isAfter(DateTime.now())) {
      return p.flashSaleEndsAt;
    }
    if (p.isSuperDeal && p.superDealEndsAt != null && p.superDealEndsAt!.isAfter(DateTime.now())) {
      return p.superDealEndsAt;
    }
    return null;
  }

  bool get _isDealActive => _dealPrice != null;

  double _displayPrice(Product p) {
    final v = _findVariant(p);
    if (v != null) {
      final eff = v['effective_price'];
      final pr = v['price'];
      if (eff != null) {
        final parsed = eff is num ? eff.toDouble() : double.tryParse(eff.toString());
        if (parsed != null) return parsed;
      }
      if (pr != null) {
        final parsed = pr is num ? pr.toDouble() : double.tryParse(pr.toString());
        if (parsed != null) return parsed;
      }
    }
    return p.effectivePrice;
  }

  Product? get product {
    final async = ref.read(productProvider(widget.productId));
    return async.whenOrNull(data: (p) => p);
  }

  void _syncCartState() {
    final cart = ref.read(cartProvider);
    if (cart == null || product == null) return;
    final active = _findVariant(product!);
    final inCart = cart.items.any((item) {
      if (item.productId != product!.id) return false;
      final itemVar = item.variant;
      if (active == null) return itemVar.isEmpty;
      final attrs = active['attributes'] as Map<String, dynamic>? ?? {};
      if (itemVar.length != attrs.length) return false;
      return attrs.entries.every((e) => itemVar[e.key] == e.value);
    });
    if (mounted) setState(() => _isInCart = inCart);
  }

  bool _isInCart = false;

  Future<void> _toggleCart(Product p) async {
    if (_isCartActionInProgress || !p.vendorAcceptingOrders || !p.orderable) return;
    if (!_isUnlimitedStock && _maxOrderQuantity <= 0) return;
    if (mounted) setState(() => _isCartActionInProgress = true);
    try {
      final notifier = ref.read(cartProvider.notifier);
      final active = _findVariant(p);
      final cart = ref.read(cartProvider);
      final existingItem = cart?.items.firstWhereOrNull((item) {
        if (item.productId != p.id) return false;
        final itemVar = item.variant;
        if (active == null) return itemVar.isEmpty;
        final attrs = active['attributes'] as Map<String, dynamic>? ?? {};
        if (itemVar.length != attrs.length) return false;
        return attrs.entries.every((e) => itemVar[e.key] == e.value);
      });
      if (existingItem != null) {
        await notifier.removeItem(existingItem.id);
      } else {
        final variant = active != null ? Map<String, String>.from(active['attributes'] as Map<String, dynamic>? ?? {}) : null;
        await notifier.addItem(p, quantity: _quantity, variant: variant);
      }
      _syncCartState();
    } catch (_) {} finally {
      if (mounted) setState(() => _isCartActionInProgress = false);
    }
  }

  void _showMultiVariantSheet(Product p, {bool buyNow = false}) {
    final l10n = AppLocalizations.of(context);
    final allVariants = p.variants.where((v) {
      final attrs = v['attributes'] as Map<String, dynamic>? ?? {};
      return attrs.isNotEmpty;
    }).toList();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        var quantities = <int, int>{};
        int totalQty = 0;
        String? errorMsg;

        return StatefulBuilder(
          builder: (context, setSheetState) {
            final cart = ref.read(cartProvider);
            final moqInfo = cart?.minimumBulkProgress?[p.id];
            final moq = (p.bulkEnabled && p.minimumBulkQuantity != null) ? p.minimumBulkQuantity! : 1;
            final currentCartQty = moqInfo?.currentQuantity ?? 0;
            final isLoggedIn = ApiClient.hasToken;

            Map<int, int> maxPerVariant = {};
            for (int i = 0; i < allVariants.length; i++) {
              final variant = allVariants[i];
              int physical = variant['unlimited_stock'] == true ? 999999 : ((variant['stock'] as num?)?.toInt() ?? 0);
              int dailyCap = p.remainingDailyQuantity ?? 999999;
              maxPerVariant[i] = min(physical, dailyCap);
            }

            return Container(
              constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.85),
              decoration: const BoxDecoration(
                color: AppColors.cardBackground,
                borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            l10n.translate('product_select_variants'),
                            style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.close),
                          onPressed: () => Navigator.pop(context),
                        ),
                      ],
                    ),
                  ),
                  const Divider(),
                  Flexible(
                    fit: FlexFit.loose,
                    child: ListView.builder(
                      shrinkWrap: true,
                      itemCount: allVariants.length,
                      itemBuilder: (_, idx) {
                        final variant = allVariants[idx];
                        final label = (variant['attributes'] as Map<String, dynamic>? ?? {})
                            .entries.map((e) => '${e.key}: ${e.value}').join(', ');
                        final price = _variantPriceSafe(variant, p.price);
                        final disabled = maxPerVariant[idx]! <= 0;
                        final currentQty = quantities[idx] ?? 0;

                        return Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                          child: Row(
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
                                    Text(
                                      'ETB ${price.toStringAsFixed(2)}',
                                      style: const TextStyle(fontSize: 13, color: AppColors.textMuted),
                                    ),
                                    if (disabled)
                                      const Text('Unavailable today', style: TextStyle(color: Colors.red, fontSize: 12))
                                    else
                                      Text(
                                        variant['unlimited_stock'] == true
                                            ? l10n.translate('unlimited_stock')
                                            : 'Stock: ${variant['stock']}',
                                        style: const TextStyle(fontSize: 12, color: AppColors.textMuted),
                                      ),
                                  ],
                                ),
                              ),
                              Row(
                                children: [
                                  IconButton(
                                    icon: const Icon(Icons.remove),
                                    onPressed: disabled || currentQty <= 0
                                        ? null
                                        : () => setSheetState(() {
                                              quantities[idx] = (currentQty - 1).clamp(0, maxPerVariant[idx]!);
                                              totalQty = quantities.values.fold(0, (a, b) => a + b);
                                              errorMsg = null;
                                            }),
                                  ),
                                  SizedBox(
                                    width: 40,
                                    child: Text(
                                      '$currentQty',
                                      textAlign: TextAlign.center,
                                      style: const TextStyle(fontWeight: FontWeight.w600),
                                    ),
                                  ),
                                  IconButton(
                                    icon: const Icon(Icons.add),
                                    onPressed: disabled || currentQty >= maxPerVariant[idx]!
                                        ? null
                                        : () => setSheetState(() {
                                              quantities[idx] = (currentQty + 1).clamp(0, maxPerVariant[idx]!);
                                              totalQty = quantities.values.fold(0, (a, b) => a + b);
                                              errorMsg = null;
                                            }),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      children: [
                        if (p.bulkEnabled && moq > 1) ...[
                          Text(
                            (currentCartQty + totalQty) >= moq
                                ? '? Minimum order of $moq units met'
                                : '?? Add ${moq - currentCartQty - totalQty} more to reach $moq minimum.',
                            style: TextStyle(
                              color: (currentCartQty + totalQty) >= moq ? Colors.green : Colors.orange,
                              fontSize: 13,
                            ),
                          ),
                          const SizedBox(height: 8),
                        ],
                        if (errorMsg != null)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: Text(
                              errorMsg!,
                              style: const TextStyle(color: Colors.red, fontSize: 13),
                              textAlign: TextAlign.center,
                            ),
                          ),
                        if (!isLoggedIn)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: Text(
                              'Please log in to add items.',
                              style: TextStyle(color: AppColors.error, fontSize: 13),
                              textAlign: TextAlign.center,
                            ),
                          ),
                        Row(
                          children: [
                            Expanded(
                              child: OutlinedButton(
                                onPressed: (totalQty == 0 || !p.orderable || !p.vendorAcceptingOrders || !isLoggedIn)
                                    ? null
                                    : () async {
                                        final items = <Map<String, dynamic>>[];
                                        for (int i = 0; i < allVariants.length; i++) {
                                          if ((quantities[i] ?? 0) > 0) {
                                            items.add({
                                              'product_id': p.id,
                                              'variant': allVariants[i]['attributes'],
                                              'quantity': quantities[i]!,
                                            });
                                          }
                                        }
                                        if (items.isNotEmpty) {
                                          try {
                                            await ref.read(cartProvider.notifier).batchAddItems(items);
                                            if (mounted) {
                                              Navigator.pop(context);
                                            }
                                          } catch (e) {
                                            setSheetState(() => errorMsg = e.toString());
                                          }
                                        }
                                      },
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: AppColors.textPrimary,
                                  side: BorderSide(color: AppColors.textPrimary, width: 1.5),
                                  padding: const EdgeInsets.symmetric(vertical: 14),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppShapes.radiusSm)),
                                  backgroundColor: AppColors.cardBackground,
                                ),
                                child: Text(
                                  l10n.translate('product_add_to_cart'),
                                  style: const TextStyle(fontWeight: FontWeight.w700, color: AppColors.textPrimary),
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: ElevatedButton(
                                onPressed: (totalQty == 0 || !p.orderable || !p.vendorAcceptingOrders || !isLoggedIn)
                                    ? null
                                    : () async {
                                        final items = <Map<String, dynamic>>[];
                                        for (int i = 0; i < allVariants.length; i++) {
                                          if ((quantities[i] ?? 0) > 0) {
                                            items.add({
                                              'product_id': p.id,
                                              'variant': allVariants[i]['attributes'],
                                              'quantity': quantities[i]!,
                                            });
                                          }
                                        }
                                        if (items.isNotEmpty) {
                                          try {
                                            await ref.read(cartProvider.notifier).batchAddItems(items);
                                            if (mounted) {
                                              Navigator.pop(context);
                                              Navigator.push(context, MaterialPageRoute(builder: (_) => const CheckoutScreen()));
                                            }
                                          } catch (e) {
                                            setSheetState(() => errorMsg = e.toString());
                                          }
                                        }
                                      },
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: AppColors.primary,
                                  foregroundColor: Colors.white,
                                  padding: const EdgeInsets.symmetric(vertical: 14),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppShapes.radiusSm)),
                                  elevation: 3,
                                  shadowColor: AppColors.primary.withOpacity(0.4),
                                ),
                                child: Text(
                                  buyNow ? l10n.translate('product_buy_now') : l10n.translate('product_buy_now'),
                                  style: const TextStyle(fontWeight: FontWeight.w800, color: Colors.white),
                                ),
                              ),
                            ),
                          ],
                        ),
                        if (totalQty == 0 && errorMsg == null && isLoggedIn)
                          const Padding(
                            padding: EdgeInsets.only(top: 8),
                            child: Text(
                              'Select quantities for the variants you want',
                              style: TextStyle(color: AppColors.textMuted),
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  double _variantPriceSafe(Map<String, dynamic> variant, double fallback) {
    final raw = variant['effective_price'] ?? variant['price'];
    if (raw == null) return fallback;
    if (raw is num) return raw.toDouble();
    return double.tryParse(raw.toString()) ?? fallback;
  }

  void _showVariantSelectionSheet(Product p, {bool buyNow = false}) {
    if (p.variants.length > 1 && _variantKeys.length > 1) {
      _showMultiVariantSheet(p, buyNow: buyNow);
      return;
    }

    final l10n = AppLocalizations.of(context);
    final variantKeys = <String>[];
    for (final v in p.variants) {
      final attrs = v['attributes'] as Map<String, dynamic>? ?? {};
      for (final entry in attrs.entries) {
        if (entry.value.toString().isNotEmpty && !variantKeys.contains(entry.key)) {
          variantKeys.add(entry.key);
        }
      }
    }

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        Map<String, String> localVariant = Map<String, String>.from(_selectedVariant);
        List<String> localOrder = List<String>.from(_selectionOrder);
        int sheetQuantity = _quantity;

        return StatefulBuilder(
          builder: (context, setSheetState) {
            final cart = ref.read(cartProvider);
            bool isSheetVariantInCart = false;
            if (cart != null) {
              final active = _findVariantForSelection(p, localVariant);
              if (active != null) {
                final attrs = active['attributes'] as Map<String, dynamic>? ?? {};
                isSheetVariantInCart = cart.items.any((item) {
                  if (item.productId != p.id) return false;
                  final itemVar = item.variant;
                  if (itemVar.length != attrs.length) return false;
                  return attrs.entries.every((e) => itemVar[e.key] == e.value.toString());
                });
              }
            }

            final allMap = <String, List<String>>{};
            for (final key in variantKeys) {
              allMap[key] = p.variants
                  .map((v) => ((v['attributes'] as Map<String, dynamic>?)?[key]?.toString() ?? ''))
                  .where((v) => v.isNotEmpty)
                  .toSet()
                  .toList();
            }

            final available = p.variants.where((v) {
              final attrs = v['attributes'] as Map<String, dynamic>? ?? {};
              return localVariant.entries.every(
                (e) => e.value.isEmpty || attrs[e.key] == e.value);
            }).toList();

            final allowedMap = <String, List<String>>{};
            for (final key in variantKeys) {
              allowedMap[key] = available
                  .map((v) => ((v['attributes'] as Map<String, dynamic>?)?[key]?.toString() ?? ''))
                  .where((v) => v.isNotEmpty)
                  .toSet()
                  .toList();
            }

            final active = _findVariantForSelection(p, localVariant);
            final complete = active != null;

            final bool selectedVariantUnlimited = complete &&
                (active!['unlimited_stock'] == true ||
                    active['stock'] == null ||
                    active['stock'] == '');

            final int physicalLimit;
            if (selectedVariantUnlimited) {
              physicalLimit = 999999;
            } else if (complete) {
              final stockRaw = active['stock'];
              physicalLimit = stockRaw is num ? stockRaw.toInt() : int.tryParse(stockRaw?.toString() ?? '') ?? 0;
            } else {
              physicalLimit = 0;
            }

            int maxAvailable = physicalLimit;
            if (p.remainingDailyQuantity != null) {
              maxAvailable = min(maxAvailable, p.remainingDailyQuantity!);
            }

            if (sheetQuantity > maxAvailable) sheetQuantity = maxAvailable;

            final minQty = (p.bulkEnabled && p.minimumBulkQuantity != null) ? p.minimumBulkQuantity! : 1;
            if (sheetQuantity < minQty) sheetQuantity = minQty;

            final bool canAddToCart = complete && p.orderable && maxAvailable > 0;

            return Container(
              constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.8),
              decoration: const BoxDecoration(
                color: AppColors.cardBackground,
                borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
              ),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Center(child: Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.grey.shade400, borderRadius: BorderRadius.circular(2)))),
                    const SizedBox(height: 16),
                    Text(l10n.translate('product_select_options_title'), style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
                    const SizedBox(height: 16),
                    ...variantKeys.map((key) {
                      final allValues = allMap[key] ?? [];
                      final allowed = allowedMap[key] ?? [];
                      final isColorAttr = key.toLowerCase().contains('color');
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Text(key, style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
                            const SizedBox(height: 6),
                            Wrap(
                              alignment: WrapAlignment.start,
                              spacing: 8,
                              runSpacing: 4,
                              children: allValues.map((val) {
                                final isSelected = localVariant[key] == val;
                                final isAvailable = allowed.contains(val);
                                if (isColorAttr) {
                                  final color = getColorFromName(val);
                                  return GestureDetector(
                                    onTap: isAvailable
                                        ? () => setSheetState(() => _handleOptionTap(localVariant, localOrder, key, val, variantKeys))
                                        : null,
                                    child: Container(
                                      width: 32, height: 32,
                                      margin: const EdgeInsets.only(right: 6),
                                      decoration: BoxDecoration(
                                        color: color,
                                        borderRadius: BorderRadius.circular(6),
                                        border: Border.all(
                                          color: !isAvailable ? Colors.grey.shade200 : isSelected ? Colors.blue.shade400 : Colors.grey.shade300,
                                          width: 2,
                                        ),
                                      ),
                                      child: !isAvailable
                                          ? Icon(Icons.close, size: 12, color: Colors.grey.shade400)
                                          : isSelected
                                              ? Icon(Icons.check, size: 14, color: Colors.white)
                                              : null,
                                    ),
                                  );
                                } else {
                                  return GestureDetector(
                                    onTap: isAvailable
                                        ? () => setSheetState(() => _handleOptionTap(localVariant, localOrder, key, val, variantKeys))
                                        : null,
                                    child: Container(
                                      margin: const EdgeInsets.only(right: 6),
                                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                      decoration: BoxDecoration(
                                        color: !isAvailable ? Colors.grey.shade100 : isSelected ? Colors.blue.shade50 : AppColors.cardBackground,
                                        borderRadius: BorderRadius.circular(AppShapes.radiusSm),
                                        border: Border.all(
                                          color: !isAvailable ? Colors.grey.shade200 : isSelected ? Colors.blue.shade400 : AppColors.borderLight,
                                        ),
                                      ),
                                      child: Text(
                                        val,
                                        style: TextStyle(
                                          fontSize: 13,
                                          fontWeight: FontWeight.w500,
                                          color: !isAvailable
                                              ? Colors.grey.shade400
                                              : isSelected
                                                  ? Colors.blue.shade800
                                                  : AppColors.textPrimary,
                                        ),
                                      ),
                                    ),
                                  );
                                }
                              }).toList(),
                            ),
                          ],
                        ),
                      );
                    }).toList(),
                    const SizedBox(height: 8),
                    if (complete) ...[
                      Text(
                        'ETB ${_variantPriceSafe(active!, p.effectivePrice).toStringAsFixed(2)}',
                        style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: AppColors.primary),
                      ),
                      const SizedBox(height: 8),
                      Row(children: [
                        Text(l10n.translate('product_qty'), style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
                        const SizedBox(width: 8),
                        Container(
                          decoration: BoxDecoration(border: Border.all(color: AppColors.borderLight), borderRadius: BorderRadius.circular(AppShapes.radiusSm)),
                          child: Row(children: [
                            InkWell(
                              onTap: () {
                                if (sheetQuantity > minQty)
                                  setSheetState(() => sheetQuantity--);
                              },
                              child: const Padding(padding: EdgeInsets.all(8), child: Icon(Icons.remove, size: 16)),
                            ),
                            Container(padding: const EdgeInsets.symmetric(horizontal: 12), child: Text('$sheetQuantity', style: const TextStyle(fontWeight: FontWeight.w600))),
                            InkWell(
                              onTap: () {
                                if (sheetQuantity < maxAvailable)
                                  setSheetState(() => sheetQuantity++);
                              },
                              child: const Padding(padding: EdgeInsets.all(8), child: Icon(Icons.add, size: 16)),
                            ),
                          ]),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            selectedVariantUnlimited
                                ? l10n.translate('unlimited_stock')
                                : l10n.translate('product_available').replaceAll('{stock}', maxAvailable.toString()),
                            style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AppColors.textMuted),
                          ),
                        ),
                      ]),
                    ] else
                      Text(l10n.translate('product_select_all_options'), style: const TextStyle(color: AppColors.textMuted)),
                    const SizedBox(height: 20),
                    Row(
                      children: [
                        Expanded(
                          child: ElevatedButton(
                            onPressed: () => Navigator.pop(context),
                            child: Text(l10n.translate('product_cancel')),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.grey.shade300,
                              foregroundColor: AppColors.textPrimary,
                              elevation: 0,
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppShapes.radiusSm)),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: ElevatedButton(
                            onPressed: canAddToCart
                                ? () async {
                                    setState(() {
                                      _selectedVariant = localVariant;
                                      _selectionOrder = localOrder;
                                      _quantity = sheetQuantity;
                                    });
                                    Navigator.pop(context);

                                    if (!isSheetVariantInCart) {
                                      await ref.read(cartProvider.notifier).addItem(
                                        p,
                                        quantity: sheetQuantity,
                                        variant: Map<String, String>.from(active!['attributes'] as Map<String, dynamic>? ?? {}),
                                      );
                                    } else {
                                      final cart = ref.read(cartProvider)!;
                                      final attrs = active!['attributes'] as Map<String, dynamic>? ?? {};
                                      final existingItem = cart.items.firstWhere((item) {
                                        if (item.productId != p.id) return false;
                                        final itemVar = item.variant;
                                        if (itemVar.length != attrs.length) return false;
                                        return attrs.entries.every((e) => itemVar[e.key] == e.value.toString());
                                      });
                                      await ref.read(cartProvider.notifier).removeItem(existingItem.id);
                                    }

                                    if (buyNow && mounted) {
                                      Navigator.push(context, MaterialPageRoute(builder: (_) => const CheckoutScreen()));
                                    }
                                  }
                                : null,
                            child: Text(
                              buyNow
                                  ? l10n.translate('product_buy_now')
                                  : (isSheetVariantInCart
                                      ? l10n.translate('product_remove')
                                      : l10n.translate('product_add_to_cart')),
                            ),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: canAddToCart ? AppColors.primary : Colors.grey.shade300,
                              foregroundColor: canAddToCart ? Colors.white : AppColors.textMuted,
                              elevation: 2,
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppShapes.radiusSm)),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  void _handleOptionTap(Map<String, String> localVariant, List<String> localOrder, String key, String value, List<String> variantKeys) {
    if (localVariant[key] == value) {
      final idx = localOrder.indexOf(key);
      if (idx != -1) {
        final keysToRemove = localOrder.sublist(idx);
        keysToRemove.forEach((k) => localVariant.remove(k));
        localOrder.removeRange(idx, localOrder.length);
      }
    } else {
      if (localVariant.containsKey(key)) {
        final idx = localOrder.indexOf(key);
        if (idx != -1) {
          final keysToRemove = localOrder.sublist(idx);
          keysToRemove.forEach((k) => localVariant.remove(k));
          localOrder.removeRange(idx, localOrder.length);
        }
      }
      localVariant[key] = value;
      localOrder.remove(key);
      localOrder.add(key);
      for (final k in variantKeys) {
        if (localVariant[k] != null && localVariant[k]!.isNotEmpty) {
          final newAllowed = _allowedValuesForSelection(product!, localVariant, k);
          if (!newAllowed.contains(localVariant[k])) {
            localVariant.remove(k);
            localOrder.remove(k);
          }
        }
      }
    }
  }

  Map<String, dynamic>? _findVariantForSelection(Product p, Map<String, String> selection) {
    if (p.variants.isEmpty || selection.isEmpty) return null;
    for (final v in p.variants) {
      final attrs = v['attributes'] as Map<String, dynamic>? ?? {};
      if (selection.entries.every((e) => attrs[e.key] == e.value)) return v;
    }
    return null;
  }

  List<String> _allowedValuesForSelection(Product p, Map<String, String> selection, String key) {
    final available = p.variants.where((v) {
      final attrs = v['attributes'] as Map<String, dynamic>? ?? {};
      return selection.entries.every((e) => e.key == key || e.value.isEmpty || attrs[e.key] == e.value);
    }).toList();
    return available
        .map((v) => ((v['attributes'] as Map<String, dynamic>?)?[key]?.toString() ?? ''))
        .where((v) => v.isNotEmpty)
        .toSet()
        .toList();
  }

  Widget _pulsingIcon(IconData icon, {double size = 20, Color? color}) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0.8, end: 1.0),
      duration: const Duration(milliseconds: 800),
      curve: Curves.easeInOut,
      builder: (context, value, child) {
        return Transform.scale(scale: value, child: child);
      },
      child: Icon(icon, size: size, color: color),
      onEnd: () {
        setState(() {});
      },
    );
  }

  Widget _buildVariantsInCart(Product p) {
    final l10n = AppLocalizations.of(context);
    final cart = ref.watch(cartProvider);
    if (cart == null) return const SizedBox.shrink();
    final items = cart.items.where((item) => item.productId == p.id).toList();
    if (items.isEmpty) return const SizedBox.shrink();

    final moqProgress = cart.minimumBulkProgress?[p.id];
    final isBulkProduct = p.bulkEnabled && moqProgress != null;
    final moq = moqProgress?.minimumRequired ?? 0;
    final currentTotal = moqProgress?.currentQuantity ?? 0;

    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(AppShapes.radiusMd),
        border: Border(
          left: BorderSide(color: AppColors.primary.withOpacity(0.6), width: 3),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.03),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                _pulsingIcon(Icons.shopping_cart_checkout, size: 18, color: AppColors.primary),
                const SizedBox(width: 6),
                Text(
                  l10n.translate('product_variants_in_cart').replaceAll('{count}', items.length.toString()),
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                    color: AppColors.textPrimary,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            ...items.map((item) {
              final variantAttrs = item.variant;
              final summary = variantAttrs.entries.map((e) => '${e.key}: ${e.value}').join(', ');
              final canRemove = !isBulkProduct || (currentTotal - item.quantity) >= moq;

              return Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            summary.isNotEmpty ? summary : 'Base',
                            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.textPrimary),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'ETB ${item.price.toStringAsFixed(2)} × ${item.quantity}',
                            style: const TextStyle(fontSize: 12, color: AppColors.textMuted),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: Icon(
                        Icons.delete_outline,
                        size: 20,
                        color: canRemove ? AppColors.error : Colors.grey,
                      ),
                      onPressed: canRemove
                          ? () => ref.read(cartProvider.notifier).removeItem(item.id)
                          : null,
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                    ),
                  ],
                ),
              );
            }),
          ],
        ),
      ),
    );
  }

  Widget _buildBulkInfoCard(Product p) {
    final l10n = AppLocalizations.of(context);
    if (!_isBulk) return const SizedBox.shrink();

    final moq = p.minimumBulkQuantity ?? 1;
    final maxQtyPerDay = p.maxQuantityPerDay;
    final isUnlimited = _isUnlimitedStock;

    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(AppShapes.radiusMd),
        border: Border(
          left: BorderSide(color: const Color(0xFFFF7A00), width: 3),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFF7A00).withOpacity(0.1),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: const Icon(Icons.verified, size: 16, color: Color(0xFFFF7A00)),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    l10n.translate('product_bulk_badge'),
                    style: const TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFF7A00),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Text(
                    'BULK',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.8,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            const Divider(height: 1, color: Color(0xFFE5E5EA)),
            const SizedBox(height: 10),
            _buildDetailRow(Icons.shopping_cart_outlined,
                '${l10n.translate("minimum_order_quantity_label")}: $moq ${l10n.translate("units")}'),
            const SizedBox(height: 6),
            _buildDetailRow(Icons.inventory_2_outlined,
                '${l10n.translate("stock_label")}: ${isUnlimited ? l10n.translate("unlimited_stock") : "${p.availableStock ?? 'N/A'} ${l10n.translate("units_available")}"}'),
            if (maxQtyPerDay != null) ...[
              const SizedBox(height: 6),
              _buildDetailRow(Icons.speed,
                  '${l10n.translate("max_quantity_per_day_label")}: $maxQtyPerDay ${l10n.translate("units")}'),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildDetailRow(IconData icon, String text) {
    return Row(
      children: [
        Icon(icon, size: 14, color: AppColors.textMuted),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            text,
            style: const TextStyle(
              fontSize: 13,
              color: AppColors.textSecondary,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildPriceBlock(Product p) {
    final l10n = AppLocalizations.of(context);
    final dealPrice = _dealPrice;
    final bool isDeal = dealPrice != null;
    final double displayPrice = dealPrice ?? _displayPrice(p);
    final double? originalPrice = isDeal ? p.price : (p.originalPrice);
    final discount = p.discountPercentage > 0 || isDeal;
    final hasFreeShipping = p.freeShipping || (p.sellerPaysShipping && p.shippingSubsidyType == 'full');
    final hasDiscountedDelivery = p.sellerPaysShipping && p.shippingSubsidyType == 'percent' && p.shippingSubsidyValue != null && p.shippingSubsidyValue! > 0;
    final showDeliveryBadge = hasFreeShipping || hasDiscountedDelivery;
    String deliveryLabel = '';
    if (hasFreeShipping) deliveryLabel = l10n.translate('product_free_delivery_label');
    else if (hasDiscountedDelivery) deliveryLabel = l10n.translate('product_discount_delivery_label')
        .replaceAll('{discount}', p.shippingSubsidyValue!.round().toString());

    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      decoration: BoxDecoration(
        color: AppColors.cardBackground,
        borderRadius: BorderRadius.circular(AppShapes.radiusMd),
        border: showDeliveryBadge ? Border.all(color: const Color(0xFFFF7A00), width: 1.5) : null,
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
        if (showDeliveryBadge) Container(
          width: double.infinity, padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: 6),
          decoration: const BoxDecoration(gradient: LinearGradient(colors: [Color(0xFFFF7A00), Color(0xFFD84315)], begin: Alignment.centerLeft, end: Alignment.centerRight)),
          child: Row(children: [const Icon(Icons.local_shipping, size: 14, color: Colors.white), const SizedBox(width: 6), Expanded(child: _AnimatedDeliveryLabel(label: deliveryLabel, textColor: Colors.white, fontSize: 12, fontWeight: FontWeight.w700))]),
        ),
        Padding(
          padding: const EdgeInsets.all(12),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            if (!_hasVariants)
              Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
                Expanded(child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Flexible(child: Text(FormatUtils.price(displayPrice), style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900, letterSpacing: -0.5, color: AppColors.textPrimary), maxLines: 1, overflow: TextOverflow.ellipsis)),
                  if (isDeal)
                    Container(
                      margin: const EdgeInsets.only(left: 8),
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(color: AppColors.error.withOpacity(0.1), borderRadius: BorderRadius.circular(6)),
                      child: Text(
                        l10n.translate('product_deal_active'),
                        style: const TextStyle(color: AppColors.error, fontWeight: FontWeight.w600, fontSize: 11),
                      ),
                    )
                  else if (discount && originalPrice != null)
                    Container(
                      margin: const EdgeInsets.only(left: 8),
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(color: AppColors.error.withOpacity(0.1), borderRadius: BorderRadius.circular(6)),
                      child: Text(
                        l10n.translate('product_save_percent')
                            .replaceAll('{amount}', FormatUtils.price(originalPrice! - displayPrice))
                            .replaceAll('{percent}', p.discountPercentage.toString()),
                        style: const TextStyle(color: AppColors.error, fontWeight: FontWeight.w600, fontSize: 11),
                      ),
                    ),
                ])),
              ])
            else ...[
              if (_isCompleteSelection) ...[
                Text(
                  FormatUtils.price(_displayPrice(p)),
                  style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900, letterSpacing: -0.5, color: AppColors.textPrimary),
                ),
                const SizedBox(height: 4),
                Text(
                  l10n.translate('product_selected_variant_price'),
                  style: const TextStyle(color: AppColors.textMuted, fontSize: 12),
                ),
              ] else ...[
                Text(
                  l10n.translate('product_from_price').replaceAll('{price}', FormatUtils.price(p.effectivePrice)),
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 4),
                Text(l10n.translate('product_select_options_exact_price'), style: const TextStyle(color: AppColors.textMuted, fontSize: 12)),
              ],
            ],
            if (isDeal && _dealEndsAt != null)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: _DealCountdown(endsAt: _dealEndsAt!),
              ),
            if (originalPrice != null && originalPrice! > displayPrice)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text(
                  FormatUtils.price(originalPrice!),
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    fontSize: 13,
                    decoration: TextDecoration.lineThrough,
                    color: AppColors.textMuted,
                  ),
                ),
              ),
          ]),
        ),
      ]),
    );
  }

  Widget _buildQuantitySelector(Product p) {
    final l10n = AppLocalizations.of(context);
    final int maxQty = _maxOrderQuantity;
    final minQty = _minOrderQuantity;
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(children: [
        Text(l10n.translate('product_qty'), style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
        const SizedBox(width: 8),
        Container(
          decoration: BoxDecoration(border: Border.all(color: Colors.grey.shade300), borderRadius: BorderRadius.circular(AppShapes.radiusSm)),
          child: Row(children: [
            InkWell(
              onTap: () { if (_quantity > minQty) setState(() => _quantity--); },
              child: const Padding(padding: EdgeInsets.all(8), child: Icon(Icons.remove, size: 16))
            ),
            Container(padding: const EdgeInsets.symmetric(horizontal: 12), child: Text('$_quantity', style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14))),
            InkWell(
              onTap: () { if (_quantity < maxQty) setState(() => _quantity++); },
              child: const Padding(padding: EdgeInsets.all(8), child: Icon(Icons.add, size: 16))
            ),
          ]),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            _isUnlimitedStock ? l10n.translate('unlimited_stock') : l10n.translate('product_available').replaceAll('{stock}', maxQty.toString()),
            style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AppColors.textMuted),
          ),
        ),
      ]),
    );
  }

  Widget _buildRatingRow(Product p) => Row(children: [
    Text(p.rating.toStringAsFixed(1), style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.textPrimary)), const SizedBox(width: 4),
    Row(mainAxisSize: MainAxisSize.min, children: List.generate(5, (i) => Icon(i < p.rating.round() ? Icons.star_rounded : Icons.star_outline_rounded, color: AppColors.starGold, size: 14))),
    const SizedBox(width: 8),
    Text('(${p.reviewsCount})', style: Theme.of(context).textTheme.bodySmall),
    const SizedBox(width: 8),
    Text('${p.soldCount} sold', style: Theme.of(context).textTheme.bodySmall),
  ]);

  Widget _buildSpecifications(Map<String, dynamic> attrs) {
    final l10n = AppLocalizations.of(context);
    if (attrs.isEmpty) return const SizedBox.shrink();
    final entries = attrs.entries.toList();
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: AppColors.cardBackground,
        borderRadius: BorderRadius.circular(AppShapes.radiusMd),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
          child: Text(
            l10n.translate('product_specifications'),
            style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
          ),
        ),
        Table(
          columnWidths: const {
            0: IntrinsicColumnWidth(),
            1: FlexColumnWidth(),
          },
          border: TableBorder.all(color: const Color(0xFFE5E5EA), width: 0.5),
          defaultVerticalAlignment: TableCellVerticalAlignment.middle,
          children: entries.map((e) {
            return TableRow(
              decoration: BoxDecoration(
                color: entries.indexOf(e).isEven ? Colors.white : const Color(0xFFF9F9F9),
              ),
              children: [
                TableCell(
                  verticalAlignment: TableCellVerticalAlignment.middle,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    child: Text(
                      e.key.replaceAll('_', ' '),
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: AppColors.textMuted,
                        fontWeight: FontWeight.w500,
                        fontSize: 13,
                      ),
                      softWrap: true,
                    ),
                  ),
                ),
                TableCell(
                  verticalAlignment: TableCellVerticalAlignment.middle,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    child: Text(
                      e.value.toString(),
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                        color: AppColors.textPrimary,
                        fontSize: 13,
                      ),
                    ),
                  ),
                ),
              ],
            );
          }).toList(),
        ),
      ]),
    );
  }

  Widget _buildDimensionsAndWeight(Product p) {
    final l10n = AppLocalizations.of(context);
    final entries = <MapEntry<String, String>>[
      if (p.weightKg != null && p.weightKg! > 0)
        MapEntry('Weight', '${p.weightKg!.toStringAsFixed(2)} kg'),
      if (p.lengthCm != null && p.lengthCm! > 0)
        MapEntry('Length', '${p.lengthCm!.toStringAsFixed(1)} cm'),
      if (p.widthCm != null && p.widthCm! > 0)
        MapEntry('Width', '${p.widthCm!.toStringAsFixed(1)} cm'),
      if (p.heightCm != null && p.heightCm! > 0)
        MapEntry('Height', '${p.heightCm!.toStringAsFixed(1)} cm'),
    ];
    if (entries.isEmpty) return const SizedBox.shrink();

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: AppColors.cardBackground,
        borderRadius: BorderRadius.circular(AppShapes.radiusMd),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
          child: Text(
            l10n.translate('product_dimensions_weight'),
            style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
          ),
        ),
        Table(
          columnWidths: const {
            0: IntrinsicColumnWidth(),
            1: FlexColumnWidth(),
          },
          border: TableBorder.all(color: const Color(0xFFE5E5EA), width: 0.5),
          defaultVerticalAlignment: TableCellVerticalAlignment.middle,
          children: entries.map((e) {
            return TableRow(
              decoration: BoxDecoration(
                color: entries.indexOf(e).isEven ? Colors.white : const Color(0xFFF9F9F9),
              ),
              children: [
                TableCell(
                  verticalAlignment: TableCellVerticalAlignment.middle,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    child: Text(
                      e.key,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: AppColors.textMuted,
                        fontWeight: FontWeight.w500,
                        fontSize: 13,
                      ),
                    ),
                  ),
                ),
                TableCell(
                  verticalAlignment: TableCellVerticalAlignment.middle,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    child: Text(
                      e.value,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                        color: AppColors.textPrimary,
                        fontSize: 13,
                      ),
                    ),
                  ),
                ),
              ],
            );
          }).toList(),
        ),
      ]),
    );
  }

  Widget _buildReviewsSection(Product product) {
    final l10n = AppLocalizations.of(context);
    return Container(
      padding: const EdgeInsets.all(12),
      margin: const EdgeInsets.only(bottom: 6),
      decoration: BoxDecoration(
        color: AppColors.cardBackground,
        borderRadius: BorderRadius.circular(AppShapes.radiusMd),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(l10n.translate('product_customer_reviews'),
            style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
        const SizedBox(height: 12),
        ReviewListWidget(
          key: ValueKey('reviews_$_reviewRefreshCounter'),
          productId: widget.productId,
        ),
        const SizedBox(height: 12),
        Center(
          child: TextButton(
            onPressed: () {
              Navigator.push(context, MaterialPageRoute(builder: (_) => AllReviewsPage(productId: product.id)));
            },
            child: Text(l10n.translate('product_see_all_reviews'),
                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
          ),
        ),
      ]),
    );
  }

  Widget _buildShopClosedBanner(Product product) {
    final l10n = AppLocalizations.of(context);
    final shopClosed = !product.vendorAcceptingOrders;
    if (!shopClosed) return const SizedBox.shrink();
    final vendorName = product.vendorBusinessName ?? 'This shop';
    return Container(
      key: ValueKey(shopClosed),
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: AppSpacing.xs),
      padding: const EdgeInsets.all(AppSpacing.sm),
      decoration: BoxDecoration(
        color: Colors.amber.shade50,
        border: Border.all(color: Colors.amber.shade300),
        borderRadius: BorderRadius.circular(AppShapes.radiusSm),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(Icons.storefront, color: Colors.amber[800], size: 18),
          const SizedBox(width: 8),
          Text(l10n.translate('product_shop_not_accepting').replaceAll('{name}', vendorName),
              style: TextStyle(fontWeight: FontWeight.w700, color: Colors.amber[900], fontSize: 13)),
        ]),
        Padding(padding: const EdgeInsets.only(top: 4), child: Text(
          product.vendorReopenAt != null
              ? l10n.translate('product_shop_reopen').replaceAll('{date}', product.vendorReopenAt!.toLocal().toString().substring(0, 16))
              : l10n.translate('product_shop_check_back'),
          style: TextStyle(color: Colors.amber[800], fontSize: 12),
        )),
      ]),
    );
  }

  Widget _buildVendorCard(Product product) {
    final l10n = AppLocalizations.of(context);
    final textTheme = Theme.of(context).textTheme;
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      decoration: BoxDecoration(
        color: AppColors.cardBackground,
        borderRadius: BorderRadius.circular(AppShapes.radiusMd),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 8, offset: const Offset(0, 2))],
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            CircleAvatar(
              radius: 24,
              backgroundColor: AppColors.primary.withOpacity(0.1),
              backgroundImage: (_vendorLogoUrl != null && _vendorLogoUrl!.isNotEmpty) ? CachedNetworkImageProvider(_vendorLogoUrl!) : null,
              child: (_vendorLogoUrl == null || _vendorLogoUrl!.isEmpty) ? const Icon(Icons.store_rounded, color: AppColors.primary, size: 28) : null,
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(product.sellerName!, style: textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w600)),
              const SizedBox(height: 2),
              Row(children: [
                if (_vendorDetails != null && _vendorDetails!['rating'] != null)
                  Text('${_vendorDetails!['rating']} · ', style: textTheme.bodySmall?.copyWith(color: AppColors.textMuted)),
                if (_vendorDetails != null && _vendorDetails!['reviews_count'] != null)
                  Text('${_vendorDetails!['reviews_count']} reviews · ', style: textTheme.bodySmall?.copyWith(color: AppColors.textMuted)),
                Text('${_vendorDetails?['products_count'] ?? product.vendorProductsCount} products',
                    style: textTheme.bodySmall?.copyWith(color: AppColors.textMuted)),
              ]),
            ])),
            TextButton(
              onPressed: () => Navigator.pushNamed(context, '/shop', arguments: product.sellerId.toString()),
              style: TextButton.styleFrom(foregroundColor: AppColors.textPrimary, padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppShapes.radiusSm))),
              child: Text(l10n.translate('product_visit_shop'), style: const TextStyle(fontWeight: FontWeight.w600)),
            ),
          ]),
          const SizedBox(height: 8),
          if (_isShippingEstimateLoading)
            Text(l10n.translate('product_calculating_delivery'), style: textTheme.bodySmall?.copyWith(color: AppColors.textMuted))
          else if (_shippingEstimateText != null)
            Text(_shippingEstimateText!, style: textTheme.bodySmall?.copyWith(color: Colors.green.shade700, fontWeight: FontWeight.w500))
          else if (ref.read(authProvider) != null)
            GestureDetector(
              onTap: () => Navigator.pushNamed(context, '/profile/addresses'),
              child: Text(l10n.translate('product_add_delivery_address'), style: textTheme.bodySmall?.copyWith(color: AppColors.primary)),
            )
          else
            GestureDetector(
              onTap: () => Navigator.pushNamed(context, '/login'),
              child: Text(l10n.translate('product_login_to_see_delivery'), style: textTheme.bodySmall?.copyWith(color: AppColors.primary)),
            ),
          // -- Call Company button --
          if (_vendorDetails != null &&
              (_vendorDetails!['is_bulk_supplier'] == true || _vendorDetails!['is_company'] == true) &&
              _vendorDetails!['phone'] != null &&
              _vendorDetails!['phone'].toString().isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: InkWell(
                onTap: () => launchUrl(Uri.parse('tel:${_vendorDetails!['phone']}')),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.phone, size: 16, color: Colors.green),
                    const SizedBox(width: 6),
                    Text(
                      _vendorDetails!['phone'].toString(),
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: Colors.grey.shade700,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          // -- end call button --
        ]), // closing of Column
      ),
    );
  }

  String _localisedTabLabel(String key, AppLocalizations l10n) {
    switch (key) {
      case 'overview':        return l10n.translate('tab_overview');
      case 'description':     return l10n.translate('tab_description');
      case 'reviews':         return l10n.translate('tab_reviews');
      case 'recommendations': return l10n.translate('tab_recommendations');
      default:                return key;
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    ref.listen(cartProvider, (_, __) { if (!mounted) return; _syncCartState(); });
    final productAsync = ref.watch(productProvider(widget.productId));
    final wishlist = ref.watch(wishlistProvider);
    final cart = ref.watch(cartProvider);
    final compareList = ref.watch(compareProvider);
    final cartItemCount = cart?.itemCount ?? 0;
    final wishlistCount = wishlist.length;
    final compareCount = compareList.length;
    final topPadding = MediaQuery.of(context).padding.top;
    final bottomPadding = MediaQuery.of(context).padding.bottom;
    final textTheme = Theme.of(context).textTheme;

    return Scaffold(
      backgroundColor: const Color(0xFFF2F2F7),
      body: productAsync.when(
        data: (product) {
          _trackRecentlyViewed();
          final minQty = _minOrderQuantity;
          if (_quantity < minQty) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) setState(() => _quantity = minQty);
            });
          }

          if (_mediaItems.isEmpty) _buildMediaItems(product);
          final vendorId = product.sellerId;
          if (vendorId != null) {
            final vendorAsync = ref.watch(vendorDetailsProvider(vendorId));
            vendorAsync.whenData((vendor) {
              if (vendor != null && _vendorDetails != vendor) {
                _vendorDetails = vendor;
                _vendorLogoUrl = vendor['logo_url']?.toString() ?? '';
                if (_shippingEstimateText == null) {
                  _fetchShippingEstimate(vendorId);
                }
                _calculateDeliveryEstimate();
              }
            });
          }

          final shopClosed = !product.vendorAcceptingOrders;
          final canOrder = product.orderable;
          final unavailableReason = product.unavailableReason;
          final attrs = product.productAttributes ?? {};
          final showDelivery = _deliveryEstimateText != null;
          final bool hasReturnPolicy = _vendorDetails != null &&
              _vendorDetails!['return_policy'] != null &&
              _vendorDetails!['return_policy'].toString().isNotEmpty &&
              _vendorDetails!['return_policy'].toString() != 'We accept returns within 14 days of delivery.';

          final attributeList = _allValuesMap(product).entries.where((e) => e.value.isNotEmpty).toList();

          final bool isOutOfStock = !_isUnlimitedStock && (_maxOrderQuantity <= 0);

          return Stack(children: [
            RefreshIndicator(
              onRefresh: () async {
                ref.invalidate(productProvider(widget.productId));
                await ref.refresh(productProvider(widget.productId).future);
              },
              child: CustomScrollView(
                controller: _scrollController,
                slivers: [
                  SliverToBoxAdapter(
                    child: Column(children: [
                      _buildMediaCarousel(),
                      _buildShopClosedBanner(product),
                      if (widget.fromCompany && widget.companyId != null)
                        GestureDetector(
                          onTap: () => Navigator.pushNamed(context, '/shop', arguments: widget.companyId!.toString()),
                          child: Container(
                            color: Colors.white,
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                            child: Row(
                              children: [
                                const Icon(Icons.arrow_back_ios, size: 14, color: AppColors.primary),
                                const SizedBox(width: 4),
                                Text(
                                  'Back to Company',
                                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                    color: AppColors.primary,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          const SizedBox(height: 12),
                          Text(product.title, style: textTheme.headlineMedium?.copyWith(fontSize: 17, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
                          const SizedBox(height: 4),
                          _buildBulkInfoCard(product),
                          const SizedBox(height: 4),
                          _buildRatingRow(product),
                          const SizedBox(height: 4),
                          _buildPriceBlock(product),
                          _buildVariantsInCart(product),
                          if (_hasVariants && attributeList.isNotEmpty)
                            Container(
                              margin: const EdgeInsets.only(top: 6),
                              decoration: BoxDecoration(color: AppColors.cardBackground, borderRadius: BorderRadius.circular(AppShapes.radiusMd)),
                              padding: const EdgeInsets.all(12),
                              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                Text(l10n.translate('product_available_options'), style: textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
                                const SizedBox(height: 8),
                                ...attributeList.map((entry) => Padding(
                                  padding: const EdgeInsets.symmetric(vertical: 4),
                                  child: Row(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      SizedBox(
                                        width: 100,
                                        child: Text(
                                          '${entry.key}:',
                                          style: textTheme.bodyMedium?.copyWith(
                                            fontWeight: FontWeight.w500,
                                            color: AppColors.textMuted,
                                          ),
                                          softWrap: true,
                                        ),
                                      ),
                                      Expanded(
                                        child: Text(
                                          entry.value.join(', '),
                                          style: textTheme.bodyMedium?.copyWith(
                                            fontWeight: FontWeight.w600,
                                            color: AppColors.textPrimary,
                                          ),
                                          softWrap: true,
                                        ),
                                      ),
                                    ],
                                  ),
                                )),
                              ]),
                            ),
                          if (!_hasVariants && _isCompleteSelection)
                            _buildQuantitySelector(product),
                          if (showDelivery || hasReturnPolicy)
                            Container(
                              margin: const EdgeInsets.only(top: 6),
                              child: Row(children: [
                                if (showDelivery)
                                  Expanded(child: Container(
                                    padding: const EdgeInsets.all(12),
                                    decoration: BoxDecoration(color: AppColors.cardBackground, borderRadius: BorderRadius.circular(AppShapes.radiusMd)),
                                    child: Row(children: [
                                      const Icon(Icons.local_shipping_outlined, size: 20, color: AppColors.primary),
                                      const SizedBox(width: 8),
                                      Expanded(child: Text(_deliveryEstimateText!, style: textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w500, color: AppColors.textPrimary))),
                                    ]),
                                  )),
                                if (showDelivery && hasReturnPolicy) const SizedBox(width: AppSpacing.xs),
                                if (hasReturnPolicy)
                                  Expanded(child: Container(
                                    padding: const EdgeInsets.all(12),
                                    decoration: BoxDecoration(color: AppColors.cardBackground, borderRadius: BorderRadius.circular(AppShapes.radiusMd)),
                                    child: Row(children: [
                                      const Icon(Icons.assignment_return, size: 20, color: AppColors.primary),
                                      const SizedBox(width: 8),
                                      Expanded(child: Text(_vendorDetails!['return_policy'], style: textTheme.bodySmall?.copyWith(color: AppColors.textMuted))),
                                    ]),
                                  )),
                              ]),
                            ),
                          if (isOutOfStock && !_hasVariants)
                            Padding(
                              padding: const EdgeInsets.only(top: 8),
                              child: Text(
                                l10n.translate('product_out_of_stock') ?? 'Out of stock',
                                style: TextStyle(color: AppColors.error, fontSize: 14, fontWeight: FontWeight.w600),
                              ),
                            ),
                        ]),
                      ),
                    ]),
                  ),
                  SliverToBoxAdapter(child: _buildSpecifications(attrs)),
                  SliverToBoxAdapter(child: _buildDimensionsAndWeight(product)),
                  if (product.description != null && product.description!.isNotEmpty)
                    SliverToBoxAdapter(
                      child: Container(
                        margin: const EdgeInsets.fromLTRB(8, 6, 8, 0),
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(color: AppColors.cardBackground, borderRadius: BorderRadius.circular(AppShapes.radiusMd)),
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(l10n.translate('product_description'), style: textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
                          const SizedBox(height: 6),
                          Text(product.description!, style: textTheme.bodyMedium?.copyWith(height: 1.5, color: AppColors.textPrimary)),
                        ]),
                      ),
                    ),
                  if (product.sellerName != null && product.sellerName!.isNotEmpty)
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        child: _buildVendorCard(product),
                      ),
                    ),
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      child: _buildReviewsSection(product),
                    ),
                  ),
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Padding(
                          padding: const EdgeInsets.fromLTRB(0, 6, 0, AppSpacing.xs),
                          child: Text(l10n.translate('product_similar_items'), style: textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
                        ),
                        if (_isLoadingSimilar && _similarProducts.isEmpty)
                          const Padding(padding: EdgeInsets.all(20), child: Center(child: CircularProgressIndicator()))
                        else
                          MasonryGridView.count(
                            shrinkWrap: true,
                            physics: const NeverScrollableScrollPhysics(),
                            crossAxisCount: 2, mainAxisSpacing: 4, crossAxisSpacing: 4,
                            padding: const EdgeInsets.fromLTRB(0, 0, 0, 0),
                            itemCount: _similarProducts.length,
                            itemBuilder: (ctx, index) {
                              final prod = _similarProducts[index];
                              return GestureDetector(
                                onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => ProductDetailScreen(key: ValueKey(prod.id), productId: prod.id))),
                                child: ProductCard(product: prod, isDeal: false),
                              );
                            },
                          ),
                      ]),
                    ),
                  ),
                  SliverToBoxAdapter(child: SizedBox(height: 80 + bottomPadding)),
                ],
              ),
            ),
            Positioned(
              top: topPadding + AppSpacing.sm, left: 0, right: 0,
              child: FadeTransition(opacity: _imageIconsFadeAnimation, child: Padding(padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs), child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                _TransparentIcon(icon: Icons.arrow_back_ios_new_rounded, onTap: () => Navigator.pop(context)),
                Row(children: [
                  _TransparentIcon(icon: Icons.search_rounded, onTap: _navigateToSearch),
                  const SizedBox(width: 8),
                  _TransparentIcon(icon: Icons.share_rounded, onTap: _showShareSheet),
                ]),
              ]))),
            ),
            FadeTransition(
              opacity: _searchBarFadeAnimation,
              child: Visibility(
                visible: _searchBarFadeAnimation.value > 0.0,
                child: Positioned(top: 0, left: 0, right: 0, child: Material(elevation: 0, child: Container(color: AppColors.cardBackground, padding: EdgeInsets.only(top: topPadding), child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Padding(padding: const EdgeInsets.fromLTRB(AppSpacing.xs, AppSpacing.xs, AppSpacing.xs, AppSpacing.xs), child: Row(children: [
                    _HeaderIcon(icon: Icons.arrow_back_ios_new_rounded, onTap: () => Navigator.pop(context)),
                    const SizedBox(width: AppSpacing.xs),
                    Expanded(child: GestureDetector(onTap: _navigateToSearch, child: Container(height: 44, decoration: BoxDecoration(color: const Color(0xFFF5F5F5), borderRadius: BorderRadius.circular(14), border: Border.all(color: const Color(0xFFE0E0E0), width: 1)), child: Row(children: [const SizedBox(width: 12), Icon(Icons.search_rounded, size: 20, color: AppColors.primary), const SizedBox(width: 8), Text(l10n.translate('product_search_hint'), style: TextStyle(fontSize: 14, color: AppColors.textMuted))])))),
                    const SizedBox(width: AppSpacing.xs),
                    _HeaderIcon(icon: Icons.share_rounded, onTap: _showShareSheet),
                  ])),
                  if (_showTabs)
                    Container(height: 44, margin: const EdgeInsets.only(bottom: 4), decoration: const BoxDecoration(color: AppColors.cardBackground), child: TabBar(
                      controller: _tabController, isScrollable: true,
                      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs),
                      labelColor: AppColors.primary, unselectedLabelColor: AppColors.textMuted,
                      labelStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
                      unselectedLabelStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
                      dividerColor: Colors.transparent,
                      indicator: const BoxDecoration(color: Colors.transparent),
                      indicatorWeight: 0, indicatorPadding: EdgeInsets.zero,
                      overlayColor: WidgetStateProperty.all(Colors.transparent),
                      splashFactory: NoSplash.splashFactory,
                      tabAlignment: TabAlignment.start,
                      tabs: _tabKeys.map((key) => Tab(child: Text(_localisedTabLabel(key, l10n)))).toList(),
                    )),
                ])))),
              ),
            ),
            Positioned(
              bottom: 0, left: 0, right: 0,
              child: Material(
                elevation: 9.8,
                shadowColor: Colors.black.withOpacity(0.15),
                borderRadius: const BorderRadius.vertical(top: Radius.circular(AppShapes.radiusMd)),
                child: Container(
                  padding: EdgeInsets.fromLTRB(AppSpacing.xs, 6, AppSpacing.xs, 6 + bottomPadding),
                  decoration: BoxDecoration(color: AppColors.cardBackground, borderRadius: const BorderRadius.vertical(top: Radius.circular(AppShapes.radiusMd))),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (!canOrder && unavailableReason != null)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 4),
                          child: Text(
                            unavailableReason,
                            style: TextStyle(color: AppColors.error, fontSize: 12, fontWeight: FontWeight.w600),
                            textAlign: TextAlign.center,
                          ),
                        ),
                      if (isOutOfStock && !_hasVariants && canOrder)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 4),
                          child: Text(
                            l10n.translate('product_out_of_stock') ?? 'Out of stock',
                            style: TextStyle(color: AppColors.error, fontSize: 12, fontWeight: FontWeight.w600),
                            textAlign: TextAlign.center,
                          ),
                        ),
                      Row(children: [
                        _BottomIconCompact(icon: PhosphorIcons.shoppingCart(PhosphorIconsStyle.regular), badgeCount: cartItemCount, onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const CartScreen())), badgeColor: AppColors.error, iconColor: AppColors.textPrimary),
                        const SizedBox(width: AppSpacing.xs),
                        _BottomIconCompact(icon: PhosphorIcons.arrowsLeftRight(PhosphorIconsStyle.regular), badgeCount: compareCount, onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const CompareScreen())), badgeColor: AppColors.primary, iconColor: AppColors.textPrimary),
                        const SizedBox(width: AppSpacing.xs),
                        _BottomIconCompact(icon: PhosphorIcons.heart(PhosphorIconsStyle.regular), badgeCount: wishlistCount, onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const WishlistScreen())), badgeColor: AppColors.error, iconColor: AppColors.textPrimary),
                        const SizedBox(width: AppSpacing.sm),
                        Flexible(
                          child: OutlinedButton(
                            onPressed: (_isCartActionInProgress || shopClosed || !canOrder || isOutOfStock ||
                                (!_hasVariants && (_quantity < _minOrderQuantity || _maxOrderQuantity <= 0)))
                                ? null
                                : () {
                                    if (_hasVariants) {
                                      _showVariantSelectionSheet(product, buyNow: false);
                                    } else {
                                      _toggleCart(product);
                                    }
                                  },
                            style: OutlinedButton.styleFrom(
                              foregroundColor: _isInCart ? AppColors.primary : AppColors.textPrimary,
                              side: BorderSide(color: _isInCart ? AppColors.primary : AppColors.textPrimary, width: 1.5),
                              padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 12),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppShapes.radiusSm)),
                              backgroundColor: AppColors.cardBackground,
                            ),
                            child: _isCartActionInProgress
                                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.primary))
                                : FittedBox(
                                    fit: BoxFit.scaleDown,
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(_isInCart ? Icons.check_rounded : Icons.shopping_cart_outlined, size: 16, color: _isInCart ? AppColors.primary : AppColors.textPrimary),
                                        const SizedBox(width: 4),
                                        Text(
                                          shopClosed ? l10n.translate('product_shop_closed')
                                              : (_isInCart ? l10n.translate('product_added') : l10n.translate('product_add_to_cart')),
                                          style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700,
                                              color: _isInCart ? AppColors.primary : AppColors.textPrimary),
                                        ),
                                      ],
                                    ),
                                  ),
                          ),
                        ),
                        const SizedBox(width: AppSpacing.xs),
                        Expanded(
                          child: ElevatedButton(
                            onPressed: (shopClosed || !canOrder || isOutOfStock ||
                                (!_hasVariants && (_quantity < _minOrderQuantity || _maxOrderQuantity <= 0)))
                                ? null
                                : () {
                                    if (_hasVariants) {
                                      _showVariantSelectionSheet(product, buyNow: true);
                                    } else {
                                      if (!_isInCart) {
                                        final notifier = ref.read(cartProvider.notifier);
                                        notifier.addItem(product, quantity: _quantity);
                                      }
                                      Navigator.push(context, MaterialPageRoute(builder: (_) => const CheckoutScreen()));
                                    }
                                  },
                            style: ElevatedButton.styleFrom(
                              backgroundColor: (shopClosed || !canOrder || isOutOfStock) ? Colors.grey.shade400 : AppColors.primary,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 12),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppShapes.radiusSm)),
                              elevation: 3,
                              shadowColor: (shopClosed || !canOrder || isOutOfStock) ? Colors.transparent : AppColors.primary.withOpacity(0.4),
                            ),
                            child: Text(
                              shopClosed ? l10n.translate('product_shop_closed')
                                  : (!canOrder || isOutOfStock) ? l10n.translate('product_unavailable')
                                  : l10n.translate('product_buy_now'),
                              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ),
                      ]),
                    ],
                  ),
                ),
              ),
            ),
          ]);
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, _) => Center(child: Text(AppLocalizations.of(context).translate('product_error_loading'), style: TextStyle(color: AppColors.error))),
      ),
    );
  }
}

class _BottomIconCompact extends StatelessWidget {
  final PhosphorIconData icon;
  final int badgeCount;
  final VoidCallback onTap;
  final Color? badgeColor;
  final Color? iconColor;
  const _BottomIconCompact({required this.icon, required this.badgeCount, required this.onTap, this.badgeColor, this.iconColor});
  @override Widget build(BuildContext context) {
    return Stack(clipBehavior: Clip.none, children: [
      Container(width: 40, height: 40, decoration: BoxDecoration(color: AppColors.hoverState, borderRadius: BorderRadius.circular(AppShapes.radiusSm)), child: IconButton(padding: EdgeInsets.zero, icon: PhosphorIcon(icon, color: iconColor ?? AppColors.textPrimary, size: 22), onPressed: onTap)),
      if (badgeCount > 0) Positioned(right: -4, top: -4, child: Container(padding: const EdgeInsets.all(3), decoration: BoxDecoration(color: badgeColor ?? AppColors.error, shape: BoxShape.circle, border: Border.all(color: Colors.white, width: 1.5)), constraints: const BoxConstraints(minWidth: 16, minHeight: 16), child: Text(badgeCount > 9 ? '9+' : '$badgeCount', style: const TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.w800), textAlign: TextAlign.center))),
    ]);
  }
}

class _TransparentIcon extends StatefulWidget {
  final IconData icon;
  final VoidCallback onTap;
  final Color? iconColor;
  const _TransparentIcon({required this.icon, required this.onTap, this.iconColor});
  @override State<_TransparentIcon> createState() => _TransparentIconState();
}
class _TransparentIconState extends State<_TransparentIcon> with SingleTickerProviderStateMixin {
  late AnimationController _scaleController;
  late Animation<double> _scaleAnimation;
  @override void initState() { super.initState(); _scaleController = AnimationController(vsync: this, duration: const Duration(milliseconds: 100)); _scaleAnimation = Tween<double>(begin: 1.0, end: 0.9).animate(CurvedAnimation(parent: _scaleController, curve: Curves.easeInOut)); }
  @override void dispose() { _scaleController.dispose(); super.dispose(); }
  void _onTapDown(TapDownDetails _) => _scaleController.forward();
  void _onTapUp(TapUpDetails _) { _scaleController.reverse(); widget.onTap(); }
  void _onTapCancel() => _scaleController.reverse();
  @override Widget build(BuildContext context) => GestureDetector(onTapDown: _onTapDown, onTapUp: _onTapUp, onTapCancel: _onTapCancel, child: ScaleTransition(scale: _scaleAnimation, child: Container(padding: const EdgeInsets.all(8), decoration: BoxDecoration(color: Colors.black.withOpacity(0.2), shape: BoxShape.circle), child: Icon(widget.icon, color: widget.iconColor ?? Colors.white, size: 20))));
}

class _HeaderIcon extends StatefulWidget {
  final IconData icon;
  final VoidCallback onTap;
  const _HeaderIcon({required this.icon, required this.onTap});
  @override State<_HeaderIcon> createState() => _HeaderIconState();
}
class _HeaderIconState extends State<_HeaderIcon> with SingleTickerProviderStateMixin {
  late AnimationController _scaleController;
  late Animation<double> _scaleAnimation;
  @override void initState() { super.initState(); _scaleController = AnimationController(vsync: this, duration: const Duration(milliseconds: 100)); _scaleAnimation = Tween<double>(begin: 1.0, end: 0.9).animate(CurvedAnimation(parent: _scaleController, curve: Curves.easeInOut)); }
  @override void dispose() { _scaleController.dispose(); super.dispose(); }
  void _onTapDown(TapDownDetails _) => _scaleController.forward();
  void _onTapUp(TapUpDetails _) { _scaleController.reverse(); widget.onTap(); }
  void _onTapCancel() => _scaleController.reverse();
  @override Widget build(BuildContext context) => GestureDetector(onTapDown: _onTapDown, onTapUp: _onTapUp, onTapCancel: _onTapCancel, child: ScaleTransition(scale: _scaleAnimation, child: Container(padding: const EdgeInsets.all(10), decoration: const BoxDecoration(color: AppColors.cardBackground, shape: BoxShape.circle), child: Icon(widget.icon, color: AppColors.textPrimary, size: 18))));
}

class _ShareOption extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  const _ShareOption({required this.icon, required this.label, required this.color});
  @override Widget build(BuildContext context) => GestureDetector(onTap: () {}, child: Column(children: [
    Container(padding: const EdgeInsets.all(12), decoration: BoxDecoration(color: color.withOpacity(0.1), shape: BoxShape.circle), child: Icon(icon, color: color, size: 24)),
    const SizedBox(height: 8), Text(label, style: Theme.of(context).textTheme.bodySmall),
  ]));
}

// -- Full-screen image viewer -----------------
class _FullScreenImageViewer extends ConsumerStatefulWidget {
  final List<String> images;
  final int initialIndex;
  final int productId;
  const _FullScreenImageViewer({required this.images, required this.initialIndex, required this.productId});

  @override ConsumerState<_FullScreenImageViewer> createState() => _FullScreenImageViewerState();
}

class _FullScreenImageViewerState extends ConsumerState<_FullScreenImageViewer> {
  late PageController _pageController;
  late int _currentIndex;
  bool _isInCart = false;
  bool _isCartActionInProgress = false;

  @override void initState() {
    super.initState();
    _currentIndex = widget.initialIndex;
    _pageController = PageController(initialPage: _currentIndex);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final cart = ref.read(cartProvider);
      if (cart != null) setState(() => _isInCart = cart.items.any((item) => item.productId == widget.productId));
    });
  }

  @override void dispose() { _pageController.dispose(); super.dispose(); }

  Future<void> _toggleCart(Product product) async {
    if (_isCartActionInProgress) return;
    setState(() => _isCartActionInProgress = true);
    try {
      final notifier = ref.read(cartProvider.notifier);
      if (_isInCart) { await notifier.removeItem(product.id); if (mounted) setState(() => _isInCart = false); }
      else { await notifier.addItem(product, quantity: 1); if (mounted) setState(() => _isInCart = true); }
    } catch (_) {} finally { if (mounted) setState(() => _isCartActionInProgress = false); }
  }

  @override Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final productAsync = ref.watch(productProvider(widget.productId));
    final bottomPadding = MediaQuery.of(context).padding.bottom;
    return Scaffold(
      backgroundColor: Colors.black,
      body: productAsync.when(
        data: (product) => Stack(children: [
          InteractiveViewer(
            child: PageView.builder(
              controller: _pageController,
              itemCount: widget.images.length,
              onPageChanged: (index) => setState(() => _currentIndex = index),
              itemBuilder: (ctx, index) => Center(child: CachedNetworkImage(imageUrl: widget.images[index], fit: BoxFit.contain)),
            ),
          ),
          Positioned(top: MediaQuery.of(context).padding.top + 8, left: 12, child: _FloatingIcon(icon: Icons.close, onTap: () => Navigator.pop(context))),
          Positioned(
            bottom: 0, left: 0, right: 0,
            child: Container(
              padding: EdgeInsets.fromLTRB(12, 8, 12, 8 + bottomPadding),
              decoration: BoxDecoration(color: AppColors.cardBackground, borderRadius: const BorderRadius.vertical(top: Radius.circular(16))),
              child: Row(children: [
                Expanded(flex: 3, child: OutlinedButton(
                  onPressed: _isCartActionInProgress ? null : () => _toggleCart(product),
                  style: OutlinedButton.styleFrom(foregroundColor: _isInCart ? AppColors.primary : AppColors.textPrimary, side: BorderSide(color: _isInCart ? AppColors.primary : AppColors.textPrimary, width: 1.5), padding: const EdgeInsets.symmetric(vertical: 12), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppShapes.radiusSm)), backgroundColor: AppColors.cardBackground),
                  child: _isCartActionInProgress ? SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.primary)) : Row(mainAxisAlignment: MainAxisAlignment.center, children: [Icon(_isInCart ? Icons.check_rounded : Icons.shopping_cart_outlined, size: 16, color: _isInCart ? AppColors.primary : AppColors.textPrimary), const SizedBox(width: 4), Text(_isInCart ? l10n.translate('product_added') : l10n.translate('product_add_to_cart'), style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: _isInCart ? AppColors.primary : AppColors.textPrimary))]),
                )),
                const SizedBox(width: 12),
                Expanded(flex: 3, child: ElevatedButton(
                  onPressed: () async { if (!_isInCart) { final notifier = ref.read(cartProvider.notifier); await notifier.addItem(product, quantity: 1); } if (mounted) Navigator.push(context, MaterialPageRoute(builder: (_) => const CheckoutScreen())); },
                  style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(vertical: 12), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppShapes.radiusSm)), elevation: 3, shadowColor: AppColors.primary.withOpacity(0.4)),
                  child: Text(l10n.translate('product_buy_now'), style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800)),
                )),
              ]),
            ),
          ),
        ]),
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, __) => Center(child: Text(l10n.translate('product_error_loading'), style: const TextStyle(color: Colors.white))),
      ),
    );
  }
}

class _FloatingIcon extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  const _FloatingIcon({required this.icon, required this.onTap});
  @override Widget build(BuildContext context) => GestureDetector(onTap: onTap, child: Container(padding: const EdgeInsets.all(8), decoration: BoxDecoration(color: Colors.white.withOpacity(0.85), shape: BoxShape.circle), child: Icon(icon, size: 20)));
}

// -- Mobile Video Player ----------------------
class _VideoPlayerScreen extends StatefulWidget {
  final String url;
  const _VideoPlayerScreen({required this.url});
  @override State<_VideoPlayerScreen> createState() => _VideoPlayerScreenState();
}

class _VideoPlayerScreenState extends State<_VideoPlayerScreen> {
  late VideoPlayerController _videoController;
  bool _initialized = false;
  String? _errorMessage;

  @override void initState() {
    super.initState();
    _initializeVideo();
  }

  Future<void> _initializeVideo() async {
    final l10n = AppLocalizations.of(context);
    try {
      _videoController = VideoPlayerController.networkUrl(Uri.parse(widget.url));
      _videoController.addListener(() {
        if (!mounted) return;
        final value = _videoController.value;
        if (value.hasError) {
          setState(() { _errorMessage = l10n.translate('product_video_error').replaceAll('{error}', value.errorDescription!).replaceAll('{url}', widget.url); });
        }
        else if (!_initialized && value.isInitialized) { setState(() => _initialized = true); _videoController.play(); }
      });
      Future.delayed(const Duration(seconds: 15), () {
        if (!_initialized && mounted && _errorMessage == null)
          setState(() => _errorMessage = l10n.translate('product_video_loading_timeout').replaceAll('{url}', widget.url));
      });
      await _videoController.initialize();
      if (mounted && _videoController.value.isInitialized) { setState(() => _initialized = true); _videoController.play(); }
    } catch (e) {
      if (mounted) setState(() => _errorMessage = 'Could not load video:\n$e\nURL: ${widget.url}');
    }
  }

  @override void dispose() { _videoController.dispose(); super.dispose(); }

  @override Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(backgroundColor: Colors.black, leading: IconButton(icon: const Icon(Icons.close, color: Colors.white), onPressed: () => Navigator.pop(context))),
      body: Center(
        child: _errorMessage != null
            ? Padding(padding: const EdgeInsets.all(20), child: Text(_errorMessage!, style: const TextStyle(color: Colors.white, fontSize: 16), textAlign: TextAlign.center))
            : _initialized
                ? AspectRatio(aspectRatio: _videoController.value.aspectRatio, child: VideoPlayer(_videoController))
                : const CircularProgressIndicator(color: Colors.white),
      ),
      floatingActionButton: _initialized
          ? FloatingActionButton(backgroundColor: Colors.white, child: Icon(_videoController.value.isPlaying ? Icons.pause : Icons.play_arrow, color: Colors.black), onPressed: () { setState(() { _videoController.value.isPlaying ? _videoController.pause() : _videoController.play(); }); })
          : null,
    );
  }
}
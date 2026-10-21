// lib/screens/home_screen.dart
import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:carousel_slider/carousel_slider.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter_staggered_grid_view/flutter_staggered_grid_view.dart';
import 'package:lottie/lottie.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../api/client.dart';
import '../providers/cart_provider.dart';
import '../providers/tab_provider.dart';
import '../theme/app_theme.dart';
import '../l10n/app_localizations.dart';
import '../widgets/product_card.dart';
import '../widgets/flash_deal_card.dart';
import '../widgets/hot_deal_card.dart';
import '../widgets/super_deal_card.dart';
import '../widgets/package_card.dart';
import '../widgets/collection_card.dart';
import '../widgets/search_bar.dart';
import '../widgets/hero_banner.dart';
import '../widgets/notification_bell.dart';
import '../widgets/announcement_banner.dart';
import '../models/category.dart';
import '../models/product.dart';
import 'login_screen.dart';
import 'product_detail_screen.dart';
import 'product_listing_screen.dart';
import 'packages_screen.dart';
import 'search_screen.dart';
import 'flash_deals_overlay.dart';
import 'super_deals_overlay.dart';
import 'company_profile_screen.dart';

// ────── Live countdown widget (unchanged) ──────
class DealCountdown extends StatefulWidget {
  final DateTime? endAt;
  const DealCountdown({Key? key, this.endAt}) : super(key: key);
  @override
  State<DealCountdown> createState() => _DealCountdownState();
}
class _DealCountdownState extends State<DealCountdown> {
  Timer? _timer;
  Duration _remaining = Duration.zero;
  @override
  void initState() {
    super.initState();
    _updateRemaining();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) => _updateRemaining());
  }
  void _updateRemaining() {
    if (widget.endAt == null) {
      _remaining = Duration.zero;
    } else {
      final diff = widget.endAt!.difference(DateTime.now());
      _remaining = diff.isNegative ? Duration.zero : diff;
    }
    setState(() {});
  }
  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
  @override
  Widget build(BuildContext context) {
    if (_remaining == Duration.zero || widget.endAt == null)
      return const SizedBox.shrink();
    final h = _remaining.inHours.remainder(24).toString().padLeft(2, '0');
    final m = _remaining.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = _remaining.inSeconds.remainder(60).toString().padLeft(2, '0');
    return Row(mainAxisSize: MainAxisSize.min, children: [
      _diceBox(h), const SizedBox(width: 2),
      Text(':', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 12, color: AppColors.textMuted)), const SizedBox(width: 2),
      _diceBox(m), const SizedBox(width: 2),
      Text(':', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 12, color: AppColors.textMuted)), const SizedBox(width: 2),
      _diceBox(s),
    ]);
  }
  Widget _diceBox(String t) => Container(
    width: 20, height: 20,
    decoration: BoxDecoration(color: const Color(0xFFFFF3E0), borderRadius: BorderRadius.circular(4)),
    alignment: Alignment.center,
    child: Text(t, style: const TextStyle(color: AppColors.primary, fontSize: 12, fontWeight: FontWeight.w700)),
  );
}

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({Key? key}) : super(key: key);
  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> with TickerProviderStateMixin {
  int _selectedCarouselIndex = 0;
  int _selectedTabIndex = 0;

  late List<String> tabs;
  final List<String> _tabRoutes = [
    '', '/all-products', '/new-arrivals', '/best-sellers',
    '/trending', '/hot-deals', '/packages', '/collections',
  ];

  List<Category> _allCategories = [];
  List<Category> _mainCategories = [];
  List<Map<String, dynamic>> _banners = [];
  List<Map<String, dynamic>> _promotionalSections = [];
  List<Map<String, dynamic>> _collectionsData = [];
  List<Product> _packages = [];

  bool _isLoading = true;
  String? _error;
  Timer? _packageRotationTimer;
  List<Product> _displayedPackages = [];
  int _currentCollectionIndex = 0;
  Timer? _collectionTimer;

  Timer? _superHotInterchangeTimer;
  int _superStartIndex = 0;
  int _hotStartIndex = 0;
  List<Product> _allSuperProducts = [];
  List<Product> _allHotProducts = [];

  late AnimationController _staggerController;
  late Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();
    _staggerController = AnimationController(vsync: this, duration: const Duration(milliseconds: 800));
    _fadeAnimation = CurvedAnimation(parent: _staggerController, curve: Curves.easeOutQuart);
    _staggerController.forward();
    _fetchAllData();
  }

  // ── Parse package JSON from homepage package_summary into Product ──
  Product _parsePackage(Map<String, dynamic> json) {
    final j = Map<String, dynamic>.from(json);
    j['title'] = j['name'] ?? j['title'] ?? '';
    // price
    double price = 0.0;
    final rawPrice = j['price'];
    if (rawPrice is double) {
      price = rawPrice;
    } else if (rawPrice is int) {
      price = rawPrice.toDouble();
    } else if (rawPrice is String) {
      price = double.tryParse(rawPrice) ?? 0.0;
    }
    j['price'] = price;
    j['effective_price'] = price; // package price already discounted if backend sends current_price? Actually price field is current_price, so use same.
    // image
    j['image_url'] = (j['image_urls'] is List && j['image_urls'].isNotEmpty)
        ? j['image_urls'][0]
        : (j['images'] is List && j['images'].isNotEmpty)
            ? j['images'][0]
            : 'https://via.placeholder.com/300?text=Package';
    // rating, reviews_count, sold_count
    j['rating'] = (j['rating'] is num) ? (j['rating'] as num).toDouble() : 4.0;
    j['reviews_count'] = j['reviews_count'] ?? 0;
    j['sold_count'] = j['sold_count'] ?? 0;
    j['free_shipping'] = j['free_delivery'] == true || j['free_shipping'] == true;
    // discount
    if (j['discount_type'] == 'percentage') {
      j['discount'] = j['discount_value'] ?? 0;
    } else {
      j['discount'] = 0;
    }
    return Product.fromJson(j);
  }

  Future<void> _fetchAllData() async {
    bool anySuccess = false;

    // Categories
    try {
      final catRes = await ApiClient.instance.get('/categories');
      _allCategories = (catRes.data as List).map((c) => Category.fromJson(c)).toList();
      _mainCategories = _allCategories.where((c) => c.parentId == null).toList();
      anySuccess = true;
    } catch (e) { debugPrint('❌ CATEGORIES ERROR: $e'); }

    // Banners
    try {
      final res = await ApiClient.instance.get('/api/v1/banners');
      _banners = (res.data as List?)
          ?.map((b) => {
                'image_url': b['image_url'] ?? b['image'] ?? '',
                'title': b['title'] ?? '',
                'subtitle': b['description'] ?? b['subtitle'] ?? '',
                'link': b['link'] ?? ''
              })
          .toList() ??
      [];
      anySuccess = true;
    } catch (e) { debugPrint('❌ BANNERS ERROR: $e'); }

    // Homepage (includes packages)
    try {
      final homeRes = await ApiClient.instance.get('/api/v1/homepage', queryParameters: {
        '_t': DateTime.now().millisecondsSinceEpoch.toString(),
      });
      final homepage = homeRes.data;
      _promotionalSections =
          List<Map<String, dynamic>>.from(homepage['promotional_sections'] ?? []);
      _collectionsData = (homepage['collections'] as List<dynamic>?)
              ?.whereType<Map<String, dynamic>>()
              .toList() ??
          [];
      anySuccess = true;

      // ★ Parse packages from homepage packages section
      _packages = [];
      final packagesSection = _promotionalSections.firstWhere(
        (s) => s['section_type']?.toString().toLowerCase() == 'packages',
        orElse: () => <String, dynamic>{},
      );
      if (packagesSection.isNotEmpty && packagesSection['packages'] is List) {
        final packagesList = packagesSection['packages'] as List;
        _packages = packagesList
            .map((p) => _parsePackage(Map<String, dynamic>.from(p)))
            .toList();
      }
      if (_packages.isNotEmpty) {
        _displayedPackages = _packages.take(4).toList();
        _startPackageRotation();
      }
    } catch (e) { debugPrint('❌ HOMEPAGE ERROR: $e'); }

    if (!anySuccess) _error = AppLocalizations.of(context).translate('home_error');
    if (mounted) {
      setState(() => _isLoading = false);
      _startSuperHotInterchange();
      _startCollectionSwitcher();
    }
  }

  void _startPackageRotation() {
    if (_packages.length < 4) return;
    _packageRotationTimer?.cancel();
    _packageRotationTimer = Timer.periodic(const Duration(seconds: 20), (_) {
      if (!mounted) return;
      setState(() {
        final ci = _packages.indexOf(_displayedPackages.first);
        final ni = (ci + 4) % _packages.length;
        _displayedPackages = [
          _packages[ni],
          _packages[(ni + 1) % _packages.length],
          _packages[(ni + 2) % _packages.length],
          _packages[(ni + 3) % _packages.length]
        ];
      });
    });
  }

  void _startSuperHotInterchange() {
    if (_allSuperProducts.isEmpty && _allHotProducts.isEmpty) return;
    _superHotInterchangeTimer?.cancel();
    _superHotInterchangeTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (!mounted) return;
      setState(() {
        if (_allSuperProducts.isNotEmpty)
          _superStartIndex = (_superStartIndex + 2) % _allSuperProducts.length;
        if (_allHotProducts.isNotEmpty)
          _hotStartIndex = (_hotStartIndex + 2) % _allHotProducts.length;
      });
    });
  }

  void _startCollectionSwitcher() {
    if (_collectionsData.isEmpty) return;
    _collectionTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (!mounted) return;
      setState(() {
        _currentCollectionIndex = (_currentCollectionIndex + 1) % _collectionsData.length;
      });
    });
  }

  @override
  void dispose() {
    _packageRotationTimer?.cancel();
    _collectionTimer?.cancel();
    _superHotInterchangeTimer?.cancel();
    _staggerController.dispose();
    super.dispose();
  }

  void _onTabSelected(int index) {
    if (index == 0) {
      setState(() => _selectedTabIndex = 0);
      return;
    }
    if (index == _selectedTabIndex && index != 0) return;
    setState(() => _selectedTabIndex = index);
    Navigator.pushNamed(context, _tabRoutes[index])
        .then((_) {
      if (mounted) setState(() => _selectedTabIndex = 0);
    });
  }

  void _handleBannerTap(String link) async {
    if (link.isEmpty) return;
    if (link.startsWith('http')) {
      final uri = Uri.parse(link);
      if (await canLaunchUrl(uri)) await launchUrl(uri, mode: LaunchMode.externalApplication);
    } else if (link.startsWith('/product/')) {
      final productId = int.tryParse(link.split('/').last) ?? 0;
      if (productId > 0) Navigator.pushNamed(context, '/product', arguments: productId);
    } else if (link.startsWith('/category/')) {
      final categoryId = int.tryParse(link.split('/').last) ?? 0;
      if (categoryId > 0) {
        Navigator.pushNamed(context, '/category',
          arguments: {
            'categoryId': categoryId,
            'categoryName': 'Category',
          },
        );
      }
    } else {
      Navigator.pushNamed(context, link);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    tabs = [
      l10n.translate('explore'),
      l10n.translate('all_products'),
      l10n.translate('new_arrivals'),
      l10n.translate('best_sellers'),
      l10n.translate('trending'),
      l10n.translate('hot_deals_title'),
      l10n.translate('packages'),
      l10n.translate('collections'),
    ];

    if (_error != null) {
      return Scaffold(
          backgroundColor: AppColors.pageBackground,
          body: SafeArea(
              child: Center(
                  child: Padding(
                      padding: const EdgeInsets.all(32),
                      child: Column(mainAxisSize: MainAxisSize.min, children: [
                        const Icon(Icons.wifi_off, size: 48, color: AppColors.textMuted),
                        const SizedBox(height: 16),
                        Text(_error!,
                            textAlign: TextAlign.center,
                            style: const TextStyle(color: AppColors.textMuted, fontSize: 16)),
                        const SizedBox(height: 16),
                        ElevatedButton(
                            onPressed: () {
                              setState(() {
                                _error = null;
                                _isLoading = true;
                              });
                              _fetchAllData();
                            },
                            style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary),
                            child: Text(l10n.translate('retry')))
                      ])))));
    }
    if (_isLoading)
      return Scaffold(
          backgroundColor: AppColors.pageBackground,
          body: const SafeArea(
              child: Center(
                  child: CircularProgressIndicator(color: AppColors.primary))));

    final sectionsByType = <String, Map<String, dynamic>>{};
    for (final s in _promotionalSections) {
      sectionsByType[s['section_type'] ?? ''] ??= s;
    }
    final flashSection = sectionsByType['flash_sale'],
        superSection = sectionsByType['super_deal'],
        hotSection = sectionsByType['hot_deal'],
        trendingSection = sectionsByType['trending'],
        bestSection = sectionsByType['best_sellers'],
        newSection = sectionsByType['new_arrivals'],
        featuredVendorsSection = sectionsByType['featured_vendors'];
    final otherSections = _promotionalSections
        .where((s) => ![
              'flash_sale',
              'super_deal',
              'hot_deal',
              'trending',
              'best_sellers',
              'new_arrivals',
              'featured_vendors',
              'packages' // ← ensure packages section doesn't appear as generic
            ].contains(s['section_type'] ?? ''))
        .toList();

    if (_allSuperProducts.isEmpty && superSection != null) {
      _allSuperProducts = (superSection['products'] as List? ?? [])
          .map((p) => Product.fromJson(Map<String, dynamic>.from(p)))
          .toList();
    }
    if (_allHotProducts.isEmpty && hotSection != null) {
      _allHotProducts = (hotSection['products'] as List? ?? [])
          .map((p) => Product.fromJson(Map<String, dynamic>.from(p)))
          .toList();
    }

    return Scaffold(
      backgroundColor: AppColors.pageBackground,
      floatingActionButton: const AnnouncementFloatingIcon(),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _fetchAllData,
          child: CustomScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
              SliverToBoxAdapter(child: _buildHeader()),
              SliverPersistentHeader(
                pinned: true,
                delegate: _SearchAndLinksDelegate(
                  tabs: tabs,
                  selectedIndex: _selectedTabIndex,
                  onLinkTap: _onTabSelected,
                ),
              ),
              SliverToBoxAdapter(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (_mainCategories.isNotEmpty) _buildCategoryRow(_mainCategories),
                    const SizedBox(height: 4),
                    if (_banners.isNotEmpty)
                      HeroBanner(
                        banners: _banners,
                        selectedIndex: _selectedCarouselIndex,
                        onPageChanged: (i) => setState(() => _selectedCarouselIndex = i),
                        onBannerTap: _handleBannerTap,
                      ),
                    const SizedBox(height: 12),
                  ],
                ),
              ),
              SliverToBoxAdapter(
                child: Container(
                  color: AppColors.productListBackground,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SizedBox(height: 8),
                      if (flashSection != null)
                        _renderPromotionalSection(flashSection),
                      if (superSection != null || hotSection != null)
                        _buildSuperHotCombinedSection(),
                      const SizedBox(height: 4),
                      // ★ Packages from homepage
                      if (_displayedPackages.isNotEmpty)
                        _buildPackagesSection(),
                      const SizedBox(height: 4),
                      if (newSection != null)
                        _renderPromotionalSection(newSection),
                      if (featuredVendorsSection != null)
                        _buildFeaturedVendorsSection(featuredVendorsSection),
                      const SizedBox(height: 4),
                      if (_collectionsData.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        _buildCollectionsBanner(_collectionsData),
                        const SizedBox(height: 4),
                      ],
                      if (trendingSection != null)
                        _renderPromotionalSection(trendingSection),
                      const SizedBox(height: 4),
                      if (bestSection != null)
                        _renderPromotionalSection(bestSection),
                      const SizedBox(height: 4),
                      for (final sec in otherSections)
                        _renderPromotionalSection(sec),
                      const SizedBox(height: 24),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── ★ New: Packages section with header ──
  Widget _buildPackagesSection() {
    final l10n = AppLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                l10n.translate('packages'),
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary,
                ),
              ),
              TextButton(
                onPressed: () => Navigator.pushNamed(context, '/packages'),
                style: TextButton.styleFrom(
                  padding: EdgeInsets.zero,
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                child: Text(
                  l10n.translate('view_all'),
                  style: const TextStyle(
                    fontSize: 13,
                    color: AppColors.primary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 4),
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 500),
          transitionBuilder: (c, a) => FadeTransition(opacity: a, child: c),
          child: _buildPackageGrid(
            _displayedPackages,
            key: ValueKey(
              _displayedPackages.isNotEmpty ? _displayedPackages.first.id : 'packages',
            ),
          ),
        ),
      ],
    );
  }

  // ── ★ Top bar header ──
  Widget _buildHeader() => Container(
        color: AppColors.cardBackground,
        padding: const EdgeInsets.only(
            left: AppSpacing.sm, right: AppSpacing.sm, bottom: AppSpacing.xs, top: AppSpacing.sm),
        child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [_buildLogo(), const NotificationBell()]),
      );

  Widget _buildLogo() =>
      Image.asset('assets/images/et_logo.jpg', height: 36, fit: BoxFit.contain);

  // ── ★ Featured Sellers Section (unchanged) ──
  Widget _buildFeaturedVendorsSection(Map<String, dynamic> section) {
    final vendors = (section['vendors'] as List<dynamic>?) ?? [];
    if (vendors.isEmpty) return const SizedBox.shrink();
    final name = section['name'] ?? 'Featured Sellers';
    final totalSellers = vendors.length;

    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: SizedBox(
        height: 340,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: Stack(
            children: [
              Positioned.fill(
                child: Container(
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      colors: [Color(0xFFF9FAFB), Color(0xFFF3F4F6), Color(0xFFE5E7EB)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                  ),
                ),
              ),
              Positioned(top: -40, left: -30, width: 180, height: 180,
                child: Container(decoration: BoxDecoration(shape: BoxShape.circle, color: const Color(0xFFFFD6D6).withOpacity(0.2)))),
              Positioned(top: 50, right: -30, width: 160, height: 160,
                child: Container(decoration: BoxDecoration(shape: BoxShape.circle, color: const Color(0xFFCCEEFF).withOpacity(0.25)))),
              Positioned(bottom: -20, left: 60, width: 140, height: 140,
                child: Container(decoration: BoxDecoration(shape: BoxShape.circle, color: const Color(0xFFE5FFE0).withOpacity(0.2)))),
              Positioned(bottom: 20, right: 40, width: 120, height: 120,
                child: Container(decoration: BoxDecoration(shape: BoxShape.circle, color: const Color(0xFFFFE5B4).withOpacity(0.2)))),
              Positioned.fill(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildBrochureHeader(name, totalSellers),
                      const SizedBox(height: 12),
                      SizedBox(
                        height: 240,
                        child: ListView.builder(
                          scrollDirection: Axis.horizontal,
                          itemCount: vendors.length,
                          padding: const EdgeInsets.only(bottom: 8),
                          itemBuilder: (context, index) {
                            final vendor = vendors[index] as Map<String, dynamic>;
                            return Padding(
                              padding: const EdgeInsets.only(right: 16),
                              child: _FeaturedSellerCard(vendor: vendor),
                            );
                          },
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── ★ Brochure header for featured sellers ──
  Widget _buildBrochureHeader(String name, int totalSellers) {
    return Column(
      children: [
        Row(
          children: [
            Expanded(child: Divider(color: Colors.grey.shade300, thickness: 1, endIndent: 10)),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 32, height: 32,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle, color: Colors.white,
                    border: Border.all(color: Colors.grey.shade200),
                    boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 4)],
                  ),
                  child: const Icon(Icons.verified, size: 18, color: AppColors.primary),
                ),
                const SizedBox(width: 8),
                Text(
                  name,
                  style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: AppColors.textPrimary, fontFamily: 'Serif'),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade100,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.grey.shade200),
                  ),
                  child: Text(
                    '$totalSellers ${totalSellers == 1 ? 'Seller' : 'Sellers'}',
                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.textSecondary),
                  ),
                ),
              ],
            ),
            Expanded(child: Divider(color: Colors.grey.shade300, thickness: 1, indent: 10)),
          ],
        ),
        const SizedBox(height: 6),
        const Text('Handpicked sellers you can trust', style: TextStyle(fontSize: 13, fontStyle: FontStyle.italic, color: AppColors.textMuted)),
      ],
    );
  }

  Widget _renderPromotionalSection(Map<String, dynamic> s) {
    final l10n = AppLocalizations.of(context);
    final type = s['section_type'] ?? '';

    if (type == 'featured_vendors') {
      return _buildFeaturedVendorsSection(s);
    }

    final prods = (s['products'] as List? ?? []).map((p) {
      final j = Map<String, dynamic>.from(p);
      if (!j.containsKey('effective_price')) j['effective_price'] = j['price'];
      return Product.fromJson(j);
    }).toList();
    if (prods.isEmpty) return const SizedBox.shrink();
    final dynamicTitle = s['name'] ?? '';
    String title;
    if (dynamicTitle.isNotEmpty) {
      title = dynamicTitle;
    } else {
      title = _defaultTitleForType(type, l10n);
    }
    DateTime? countdownEnd;
    if (type == 'flash_sale') {
      final first = s['products']?.first;
      if (first != null && first['flash_sale_ends_at'] != null)
        countdownEnd = DateTime.tryParse(first['flash_sale_ends_at'].toString());
    }

    switch (type) {
      case 'flash_sale':
        return _buildDealSection(
            title: title,
            products: prods,
            cardBuilder: (p) => FlashDealCard(product: p),
            countdownEnd: countdownEnd,
            linkRoute: null,
            leading: const Icon(Icons.bolt, color: Colors.amber, size: 20),
            onViewAll: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const FlashDealsOverlay()),
            ),
        );
      case 'trending':
        return _buildProductGridSection(
            title: title,
            products: prods,
            linkRoute: '/trending');
      case 'new_arrivals':
        return _buildProductGridSection(
            title: title,
            products: prods,
            linkRoute: '/new-arrivals');
      case 'best_sellers':
        return _buildProductGridSection(
            title: title,
            products: prods,
            linkRoute: '/best-sellers');
      default:
        return _buildProductGridSection(title: title, products: prods, linkRoute: null);
    }
  }

  String _defaultTitleForType(String type, AppLocalizations l10n) {
    switch (type) {
      case 'flash_sale': return l10n.translate('flash_deals_title');
      case 'super_deal': return l10n.translate('super_deals_title');
      case 'hot_deal': return l10n.translate('hot_deals_title');
      case 'trending': return l10n.translate('trending_now_title');
      case 'new_arrivals': return l10n.translate('new_arrivals_title');
      case 'best_sellers': return l10n.translate('best_sellers_title');
      default: return '';
    }
  }

  Widget _buildDealSection({
    required String title,
    required List<Product> products,
    required Widget Function(Product) cardBuilder,
    DateTime? countdownEnd,
    String? linkRoute,
    Widget? leading,
    VoidCallback? onViewAll,
    bool showPeek = false,
  }) {
    final l10n = AppLocalizations.of(context);
    if (products.isEmpty) return const SizedBox.shrink();

    final screenWidth = MediaQuery.of(context).size.width;
    const double gap = 8.0;
    final double cardWidth = (screenWidth - 3 * gap) / 2.4;

    final titleStyle = const TextStyle(
      fontSize: 17,
      fontWeight: FontWeight.w700,
      color: AppColors.textPrimary,
    );

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs),
        child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Row(mainAxisSize: MainAxisSize.min, children: [
            if (leading != null) ...[
              leading,
              const SizedBox(width: 4),
            ],
            Text(title, style: titleStyle),
            if (countdownEnd != null) ...[
              const SizedBox(width: 6),
              DealCountdown(endAt: countdownEnd)
            ]
          ]),
          if (onViewAll != null)
            TextButton(
                onPressed: onViewAll,
                style: TextButton.styleFrom(
                    padding: EdgeInsets.zero,
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap),
                child: Text(l10n.translate('view_all'),
                    style: const TextStyle(
                        fontSize: 13,
                        color: AppColors.primary,
                        fontWeight: FontWeight.w600))),
          if (onViewAll == null && linkRoute != null)
            TextButton(
                onPressed: () => Navigator.pushNamed(context, linkRoute),
                style: TextButton.styleFrom(
                    padding: EdgeInsets.zero,
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap),
                child: Text(l10n.translate('view_all'),
                    style: const TextStyle(
                        fontSize: 13,
                        color: AppColors.primary,
                        fontWeight: FontWeight.w600))),
        ]),
      ),
      const SizedBox(height: 4),
      SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: EdgeInsets.zero,
        child: Row(
          children: products.map((product) {
            return Padding(
              padding: const EdgeInsets.only(right: 8),
              child: GestureDetector(
                onTap: () => Navigator.pushNamed(context, '/product', arguments: product.id),
                child: SizedBox(
                  width: cardWidth,
                  child: cardBuilder(product),
                ),
              ),
            );
          }).toList(),
        ),
      ),
    ]);
  }

  Widget _buildSuperHotCombinedSection() {
    final l10n = AppLocalizations.of(context);

    List<Product> superDisplay = [];
    if (_allSuperProducts.isNotEmpty) {
      int start = _superStartIndex % _allSuperProducts.length;
      for (int i = 0; i < 2; i++) {
        int idx = (start + i) % _allSuperProducts.length;
        superDisplay.add(_allSuperProducts[idx]);
      }
    }
    List<Product> hotDisplay = [];
    if (_allHotProducts.isNotEmpty) {
      int start = _hotStartIndex % _allHotProducts.length;
      for (int i = 0; i < 2; i++) {
        int idx = (start + i) % _allHotProducts.length;
        hotDisplay.add(_allHotProducts[idx]);
      }
    }

    final combinedList = [...superDisplay, ...hotDisplay];
    if (combinedList.isEmpty) return const SizedBox.shrink();

    final superTitle = _allSuperProducts.isNotEmpty
        ? l10n.translate('super_deals_title')
        : '';
    final hotTitle = _allHotProducts.isNotEmpty
        ? l10n.translate('hot_deals_title')
        : '';

    final superTextStyle = const TextStyle(
      fontSize: 17,
      fontWeight: FontWeight.w900,
      color: Color(0xFF9C27B0),
    );
    final hotTextStyle = const TextStyle(
      fontSize: 17,
      fontWeight: FontWeight.w900,
      color: Color(0xFFFF5722),
    );

    Widget headerRow;
    if (_allSuperProducts.isNotEmpty && _allHotProducts.isNotEmpty) {
      headerRow = Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          GestureDetector(
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const SuperDealsOverlay()),
            ),
            child: Text(superTitle, style: superTextStyle),
          ),
          GestureDetector(
            onTap: () => Navigator.pushNamed(context, '/hot-deals'),
            child: Text(hotTitle, style: hotTextStyle),
          ),
        ],
      );
    } else {
      final isSuper = _allSuperProducts.isNotEmpty;
      final title = isSuper ? superTitle : hotTitle;
      final route = isSuper ? '/super-deals' : '/hot-deals';
      final style = isSuper ? superTextStyle : hotTextStyle;
      headerRow = GestureDetector(
        onTap: () {
          if (isSuper) {
            Navigator.push(context,
                MaterialPageRoute(builder: (_) => const SuperDealsOverlay()));
          } else {
            Navigator.pushNamed(context, route);
          }
        },
        child: Text(title, style: style),
      );
    }

    final screenWidth = MediaQuery.of(context).size.width;
    const double gap = 8.0;
    final double cardWidth = (screenWidth - 3 * gap) / 2.4;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs),
          child: headerRow,
        ),
        const SizedBox(height: 4),
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 600),
          transitionBuilder: (child, animation) =>
              FadeTransition(opacity: animation, child: child),
          child: SingleChildScrollView(
            key: ValueKey('${_superStartIndex}_$_hotStartIndex'),
            scrollDirection: Axis.horizontal,
            padding: EdgeInsets.zero,
            child: Row(
              children: combinedList.map((product) {
                final isSuper = superDisplay.contains(product);
                final card = isSuper
                    ? SuperDealCard(product: product)
                    : HotDealCard(product: product);
                return Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: GestureDetector(
                    onTap: () => Navigator.pushNamed(context, '/product', arguments: product.id),
                    child: SizedBox(
                      width: cardWidth,
                      child: card,
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
        ),
        const SizedBox(height: 4),
      ],
    );
  }

  Widget _buildProductGridSection({
    required String title,
    required List<Product> products,
    String? linkRoute,
  }) {
    final l10n = AppLocalizations.of(context);
    if (products.isEmpty) return const SizedBox.shrink();
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs),
        child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Text(title,
              style: const TextStyle(
                  fontSize: 16, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
          if (linkRoute != null)
            TextButton(
                onPressed: () => Navigator.pushNamed(context, linkRoute),
                style: TextButton.styleFrom(
                    padding: EdgeInsets.zero,
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap),
                child: Text(l10n.translate('view_all'),
                    style: const TextStyle(
                        fontSize: 13,
                        color: AppColors.primary,
                        fontWeight: FontWeight.w600))),
        ]),
      ),
      const SizedBox(height: 4),
      _buildMasonryProductGrid(products),
    ]);
  }

  Widget _buildMasonryProductGrid(List<Product> products) {
    return MasonryGridView.count(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisCount: 2,
      mainAxisSpacing: 4,
      crossAxisSpacing: 4,
      padding: EdgeInsets.zero,
      itemCount: products.length,
      itemBuilder: (context, index) => GestureDetector(
        onTap: () =>
            Navigator.pushNamed(context, '/product', arguments: products[index].id),
        child: ProductCard(product: products[index], isDeal: false),
      ),
    );
  }

  Widget _buildCategoryRow(List<Category> cats) {
    return SizedBox(
      height: 90,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: EdgeInsets.zero,
        itemCount: cats.length,
        itemBuilder: (_, i) {
          final c = cats[i];
          final img = c.image ?? '';
          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: GestureDetector(
              onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (_) => ProductListingScreen(
                            title: c.name,
                            apiEndpoint: '/products?category=${c.id}',
                            showSubcategoryRow: c.children.isNotEmpty,
                            subcategories: c.children.isNotEmpty ? c.children : null,
                            mainCategoryId: c.id,
                            heroImageUrl: c.image,
                          ))),
              child: Column(children: [
                Container(
                  width: 60,
                  height: 60,
                  decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.white,
                      border: Border.all(color: AppColors.borderLight, width: 1)),
                  child: ClipOval(
                    child: img.isNotEmpty
                        ? Image.network(img,
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) =>
                                Icon(Icons.category, color: Colors.grey.shade400))
                        : Icon(Icons.category, color: Colors.grey.shade400),
                  ),
                ),
                const SizedBox(height: 6),
                Text(c.name,
                    style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textPrimary)),
              ]),
            ),
          );
        },
      ),
    );
  }

  Widget _buildPackageGrid(List<Product> p, {Key? key}) {
    return MasonryGridView.count(
      key: key,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisCount: 2,
      mainAxisSpacing: 4,
      crossAxisSpacing: 4,
      padding: EdgeInsets.zero,
      itemCount: p.length,
      itemBuilder: (context, index) => GestureDetector(
        onTap: () => Navigator.push(
            context,
            MaterialPageRoute(
                builder: (_) => PackagesScreen(highlightedPackageId: p[index].id))),
        child: PackageCard(product: p[index]),
      ),
    );
  }

  Widget _buildCollectionsBanner(List<Map<String, dynamic>> collections) {
    final l10n = AppLocalizations.of(context);
    if (_currentCollectionIndex >= collections.length) _currentCollectionIndex = 0;
    final rawCol = collections[_currentCollectionIndex];
    if (rawCol == null) return const SizedBox.shrink();

    final showcaseRaw = rawCol['showcase_products'] as List<dynamic>? ?? [];
    final allProductsRaw = rawCol['products'] as List<dynamic>? ?? [];
    final productCount = rawCol['product_count'] ?? allProductsRaw.length;

    List<ProductPreview> parseProducts(List<dynamic> list) => list
        .map((p) {
          final map = Map<String, dynamic>.from(p);
          return ProductPreview(
            id: map['id'] ?? 0,
            title: map['title'],
            imageUrls: (map['image_urls'] as List<dynamic>?)?.cast<String>(),
            price: _parseDouble(map['price']),
            effectivePrice: _parseDouble(map['effective_price']),
            originalPrice: _parseDouble(map['original_price']),
            discount: map['discount'] is int
                ? map['discount']
                : int.tryParse(map['discount']?.toString() ?? ''),
            rating: _parseDouble(map['rating']),
            freeShipping: map['free_shipping'] == true,
            isFlashSale: map['is_flash_sale'] == true,
            isSuperDeal: map['is_super_deal'] == true,
          );
        })
        .toList();

    final collection = Collection(
      id: rawCol['id'] ?? 0,
      slug: rawCol['slug'],
      name: rawCol['name'] ?? '',
      description: rawCol['description'],
      label: rawCol['label'],
      coverImageUrl: rawCol['cover_image_url'],
      productCount: productCount,
      showcaseProducts: parseProducts(showcaseRaw),
      products: parseProducts(allProductsRaw),
    );

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs),
        child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Text(l10n.translate('collections_title'),
              style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary)),
          TextButton(
              onPressed: () => Navigator.pushNamed(context, '/collections'),
              style: TextButton.styleFrom(
                  padding: EdgeInsets.zero,
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap),
              child: Text(l10n.translate('view_all'),
                  style: const TextStyle(
                      fontSize: 13,
                      color: AppColors.primary,
                      fontWeight: FontWeight.w600))),
        ]),
      ),
      const SizedBox(height: 8),
      AnimatedSwitcher(
        duration: const Duration(milliseconds: 500),
        transitionBuilder: (child, animation) =>
            FadeTransition(opacity: animation, child: child),
        child: CollectionCard(
          key: ValueKey(collection.slug),
          collection: collection,
          onExplore: () {
            Navigator.pushNamed(context, '/collection-detail',
                arguments: collection.slug ?? '');
          },
          onProductTap: (product) {
            Navigator.pushNamed(context, '/product', arguments: product.id);
          },
        ),
      ),
    ]);
  }

  double? _parseDouble(dynamic value) {
    if (value == null) return null;
    if (value is double) return value;
    if (value is int) return value.toDouble();
    return double.tryParse(value.toString());
  }
}

// ─── Featured Seller Card (unchanged) ───
class _FeaturedSellerCard extends StatelessWidget {
  final Map<String, dynamic> vendor;
  const _FeaturedSellerCard({Key? key, required this.vendor}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final logo = vendor['logo_url'] as String?;
    final banner = vendor['banner_url'] as String?;
    final businessName = vendor['business_name'] as String? ?? '';
    final description = vendor['description'] as String?;
    final badge = vendor['badge'] as String?;
    final isCompany = vendor['is_company'] as bool? ?? false;
    final isBulk = vendor['is_bulk_supplier'] as bool? ?? false;
    final verified = vendor['is_verified'] as bool? ?? false;
    final rating = double.tryParse(vendor['rating']?.toString() ?? '') ?? 0.0;
    final totalSales = int.tryParse(vendor['total_sales']?.toString() ?? '') ?? 0;
    final productsCount = int.tryParse(vendor['products_count']?.toString() ?? '') ?? 0;
    final vendorId = vendor['id'];

    return GestureDetector(
      onTap: () {
        if (vendorId == null) return;
        if (isCompany) {
          Navigator.push(context, MaterialPageRoute(builder: (_) => CompanyProfileScreen(companyId: vendorId.toString())));
        } else {
          Navigator.pushNamed(context, '/shop-detail', arguments: vendorId as int);
        }
      },
      child: Container(
        width: 500,
        height: 210,
        decoration: BoxDecoration(
          color: Colors.white,
          border: Border.all(color: Colors.grey.shade200),
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 8, offset: const Offset(0, 2))],
        ),
        child: Row(
          children: [
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Center(
                      child: Stack(
                        clipBehavior: Clip.none,
                        children: [
                          Container(
                            width: 60, height: 60,
                            decoration: BoxDecoration(shape: BoxShape.circle, color: Colors.white, boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.1), blurRadius: 6)]),
                            child: ClipOval(
                              child: logo != null && logo.isNotEmpty
                                  ? CachedNetworkImage(imageUrl: logo, fit: BoxFit.cover, memCacheWidth: 128, errorWidget: (_, __, ___) => const Icon(Icons.store, size: 28, color: Colors.grey))
                                  : const Icon(Icons.store, size: 28, color: Colors.grey),
                            ),
                          ),
                          if (verified)
                            Positioned(
                              bottom: -2, right: -2,
                              child: Container(width: 18, height: 18, decoration: const BoxDecoration(color: Colors.blue, shape: BoxShape.circle),
                                child: const Icon(Icons.check, size: 12, color: Colors.white),
                              ),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(businessName, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppColors.textPrimary), maxLines: 1, overflow: TextOverflow.ellipsis),
                    if (description != null && description.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(description, style: const TextStyle(fontSize: 14, color: AppColors.textSecondary), maxLines: 2, overflow: TextOverflow.ellipsis),
                      ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        if (badge != null)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              gradient: badge.toLowerCase() == 'platinum'
                                  ? const LinearGradient(colors: [Color(0xFF7C3AED), Color(0xFF4F46E5)])
                                  : badge.toLowerCase() == 'gold'
                                      ? const LinearGradient(colors: [Color(0xFFF59E0B), Color(0xFFD97706)])
                                      : const LinearGradient(colors: [Color(0xFF9CA3AF), Color(0xFF6B7280)]),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(badge.toUpperCase(), style: const TextStyle(fontSize: 10, color: Colors.white, fontWeight: FontWeight.bold)),
                          ),
                        if (isCompany) ...[const SizedBox(width: 4), _buildTag('COMPANY', Colors.blue)],
                        if (isBulk && !isCompany) ...[const SizedBox(width: 4), _buildTag('BULK', Colors.deepOrange)],
                      ],
                    ),
                    const Spacer(),
                    Row(
                      children: [
                        const Icon(Icons.star, size: 16, color: Colors.amber), const SizedBox(width: 2),
                        Text(rating.toStringAsFixed(1), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: AppColors.textPrimary)),
                        if (totalSales > 0) ...[const SizedBox(width: 4), Text('· $totalSales sales', style: const TextStyle(fontSize: 12, color: AppColors.textSecondary))],
                        if (productsCount > 0) ...[const SizedBox(width: 4), Text('· $productsCount products', style: const TextStyle(fontSize: 12, color: AppColors.textSecondary))],
                      ],
                    ),
                  ],
                ),
              ),
            ),
            SizedBox(
              width: 224,
              height: double.infinity,
              child: ClipRRect(
                borderRadius: const BorderRadius.only(topRight: Radius.zero, bottomRight: Radius.zero),
                child: banner != null && banner.isNotEmpty
                    ? CachedNetworkImage(imageUrl: banner, fit: BoxFit.cover, memCacheWidth: 640, errorWidget: (_, __, ___) => Container(color: Colors.grey.shade200, child: const Center(child: Icon(Icons.image, size: 48, color: Colors.grey))))
                    : Container(color: Colors.grey.shade200, child: const Center(child: Icon(Icons.image, size: 48, color: Colors.grey))),
              ),
            ),
          ],
        ),
      ),
    );
  }

  static Widget _buildTag(String text, MaterialColor color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.shade50,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color.shade200),
      ),
      child: Text(text, style: TextStyle(fontSize: 10, color: color, fontWeight: FontWeight.w600)),
    );
  }
}

// ────── Pinned Search + Quick Links Delegate (unchanged) ──────
class _SearchAndLinksDelegate extends SliverPersistentHeaderDelegate {
  final List<String> tabs;
  final int selectedIndex;
  final ValueChanged<int> onLinkTap;

  _SearchAndLinksDelegate({
    required this.tabs,
    required this.selectedIndex,
    required this.onLinkTap,
  });

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlapsContent) {
    return ColoredBox(
      color: AppColors.cardBackground,
      child: Column(
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(AppSpacing.xs, 2, AppSpacing.xs, 2),
            child: RotatingSearchBar(),
          ),
          SizedBox(
            height: 44,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs),
              itemCount: tabs.length,
              separatorBuilder: (_, __) => const SizedBox(width: 12),
              itemBuilder: (context, index) {
                final isSelected = index == selectedIndex;
                return GestureDetector(
                  onTap: () => onLinkTap(index),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    padding: const EdgeInsets.symmetric(horizontal: 2),
                    child: Center(
                      child: Text(
                        tabs[index],
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                          color: isSelected ? AppColors.primary : AppColors.textSecondary,
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  @override
  double get maxExtent => 2 + 40 + 2 + 44;
  @override
  double get minExtent => 2 + 40 + 2 + 44;
  @override
  bool shouldRebuild(covariant _SearchAndLinksDelegate oldDelegate) =>
      oldDelegate.selectedIndex != selectedIndex;
}
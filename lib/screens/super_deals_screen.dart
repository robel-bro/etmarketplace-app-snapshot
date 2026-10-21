// 📁 lib/screens/super_deals_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_staggered_grid_view/flutter_staggered_grid_view.dart';
import '../api/client.dart';
import '../models/product.dart';
import '../models/filter_params.dart';
import '../theme/app_theme.dart';
import '../l10n/app_localizations.dart';               // ★ localisation
import '../widgets/product_card.dart';
import '../widgets/search_bar.dart';
import '../widgets/notification_bell.dart';
import '../widgets/quick_links_bar.dart';
import '../widgets/bottom_nav_bar.dart';
import '../widgets/filter_sheet.dart';
import '../widgets/sort_sheet.dart';
import '../providers/tab_provider.dart';

class SuperDealsScreen extends ConsumerStatefulWidget {
  const SuperDealsScreen({Key? key}) : super(key: key);

  @override
  ConsumerState<SuperDealsScreen> createState() => _SuperDealsScreenState();
}

class _SuperDealsScreenState extends ConsumerState<SuperDealsScreen> {
  List<Product> _products = [];
  bool _isLoading = true;
  String? _error;

  FilterParams _currentFilters = FilterParams();
  String _sortBy = '';

  // The quick links will be built using l10n in build()
  late List<Map<String, dynamic>> _quickLinks;
  String _selectedQuickLink = '';

  @override
  void initState() {
    super.initState();
    _fetchProducts();
  }

  Future<void> _fetchProducts() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final queryParams = <String, dynamic>{
        'is_super_deal': 'true',
        if (_sortBy.isNotEmpty) 'sort': _sortBy,
        ..._currentFilters.toQueryParams(),
      };
      final response = await ApiClient.instance.get('/products', queryParameters: queryParams);
      final List data = response.data['data'] ?? response.data;
      setState(() {
        _products = data.map((json) => Product.fromJson(json)).toList();
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _products = [];
        _isLoading = false;
        _error = e.toString();
      });
    }
  }

  void _showFilterBottomSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => FilterSheet(
        initialParams: _currentFilters,
        context: {'is_super_deal': 'true'},
        onApply: (newParams) {
          setState(() => _currentFilters = newParams);
          _fetchProducts();
        },
      ),
    );
  }

  void _showSortBottomSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => SortSheet(
        selectedSort: _sortBy,
        onSortSelected: (value) {
          setState(() => _sortBy = value);
          _fetchProducts();
        },
      ),
    );
  }

  void _onQuickLinkTap(Map<String, dynamic> link) {
    final route = link['route'] as String;
    setState(() => _selectedQuickLink = link['name']);
    if (route.isEmpty || route == '/home') {
      Navigator.of(context).pushNamedAndRemoveUntil('/main', (route) => false);
    } else {
      Navigator.pushNamed(context, route);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);            // ★

    // ★ Build the quick‑links list with localised names
    _quickLinks = [
      {'name': l10n.translate('explore'),         'route': '/home'},
      {'name': l10n.translate('all_products'),    'route': '/all-products'},
      {'name': l10n.translate('new_arrivals'),    'route': '/new-arrivals'},
      {'name': l10n.translate('best_sellers'),    'route': '/best-sellers'},
      {'name': l10n.translate('trending'),        'route': '/trending'},
      {'name': l10n.translate('flash_sales'),     'route': '/flash-deals'},
      {'name': l10n.translate('super_deals'),     'route': '/super-deals'},
      {'name': l10n.translate('packages'),        'route': '/packages'},
      {'name': l10n.translate('collections'),     'route': '/collections'},
    ];
    // Ensure selected label stays in sync
    if (_selectedQuickLink.isEmpty ||
        !_quickLinks.any((link) => link['name'] == _selectedQuickLink)) {
      _selectedQuickLink = l10n.translate('super_deals');
    }

    final bool showEmpty = !_isLoading && _error == null && _products.isEmpty;

    return Scaffold(
      backgroundColor: AppColors.pageBackground,
      body: SafeArea(
        child: CustomScrollView(
          slivers: [
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.xs, 6, AppSpacing.xs, 4,
                ),
                child: Row(
                  children: [
                    Expanded(child: RotatingSearchBar()),
                    const SizedBox(width: 4),
                    const NotificationBell(),
                  ],
                ),
              ),
            ),

            SliverPersistentHeader(
              pinned: true,
              delegate: _QuickLinksAndFilterSortDelegate(
                links: _quickLinks,
                selected: _selectedQuickLink,
                onLinkTap: _onQuickLinkTap,
                onFilterTap: _showFilterBottomSheet,
                onSortTap: _showSortBottomSheet,
                l10n: l10n,                          // ★ pass l10n
              ),
            ),

            if (!showEmpty)
              SliverToBoxAdapter(
                child: Container(
                  color: AppColors.productListBackground,
                  child: _isLoading ? _buildShimmerGrid() : _buildProductGrid(),
                ),
              ),

            if (showEmpty)
              SliverFillRemaining(
                hasScrollBody: false,
                child: Container(
                  color: AppColors.productListBackground,
                  child: Center(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 32),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 72,
                            height: 72,
                            decoration: const BoxDecoration(
                              color: AppColors.primary,
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(
                              Icons.bolt_rounded,
                              color: Colors.white,
                              size: 36,
                            ),
                          ),
                          const SizedBox(height: 20),
                          Text(
                            l10n.translate('no_super_deals_yet'),
                            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.w600,
                                  color: AppColors.textPrimary,
                                ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            l10n.translate('super_deals_empty_msg'),
                            textAlign: TextAlign.center,
                            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                  color: AppColors.textMuted,
                                ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              )
            else
              SliverFillRemaining(
                hasScrollBody: false,
                child: Container(color: AppColors.productListBackground),
              ),
          ],
        ),
      ),
      bottomNavigationBar: BottomNavBar(
        selectedIndex: 0,
        onTap: (index) {
          Navigator.of(context).pushNamedAndRemoveUntil('/main', (route) => false);
          ref.read(tabProvider.notifier).state = index;
        },
      ),
    );
  }

  Widget _buildProductGrid() {
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Text(
            'Error: $_error',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: AppColors.textMuted,
                ),
          ),
        ),
      );
    }

    return MasonryGridView.count(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisCount: 2,
      mainAxisSpacing: 4,
      crossAxisSpacing: 4,
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.xs, AppSpacing.xs, AppSpacing.xs, AppSpacing.lg,
      ),
      itemCount: _products.length,
      itemBuilder: (context, index) {
        final product = _products[index];
        return GestureDetector(
          onTap: () =>
              Navigator.pushNamed(context, '/product', arguments: product.id),
          child: ProductCard(product: product, isDeal: true),
        );
      },
    );
  }

  Widget _buildShimmerGrid() {
    final shimmerCount = 6;
    return MasonryGridView.count(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisCount: 2,
      mainAxisSpacing: 4,
      crossAxisSpacing: 4,
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.xs, AppSpacing.xs, AppSpacing.xs, AppSpacing.lg,
      ),
      itemCount: shimmerCount,
      itemBuilder: (context, index) => _buildShimmerCard(),
    );
  }

  Widget _buildShimmerCard() {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.cardBackground,
        borderRadius: BorderRadius.circular(AppShapes.radiusSm),
        border: Border.all(color: AppColors.borderLight, width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.vertical(
              top: Radius.circular(AppShapes.radiusSm),
            ),
            child: Container(
              height: 140,
              color: Colors.grey.shade200,
              child: const SizedBox.expand(),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(AppSpacing.xs),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  height: 12,
                  width: double.infinity,
                  color: Colors.grey.shade200,
                ),
                const SizedBox(height: 4),
                Container(
                  height: 12,
                  width: 80,
                  color: Colors.grey.shade200,
                ),
                const SizedBox(height: 6),
                Container(
                  height: 16,
                  width: 60,
                  color: Colors.grey.shade200,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Delegate now receives l10n ──────
class _QuickLinksAndFilterSortDelegate extends SliverPersistentHeaderDelegate {
  final List<Map<String, dynamic>> links;
  final String selected;
  final ValueChanged<Map<String, dynamic>> onLinkTap;
  final VoidCallback onFilterTap;
  final VoidCallback onSortTap;
  final AppLocalizations l10n;       // ★

  _QuickLinksAndFilterSortDelegate({
    required this.links,
    required this.selected,
    required this.onLinkTap,
    required this.onFilterTap,
    required this.onSortTap,
    required this.l10n,              // ★
  });

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlapsContent) {
    return ColoredBox(
      color: AppColors.cardBackground,
      child: Column(
        children: [
          SizedBox(
            height: 44,
            child: QuickLinksBar(
              links: links,
              selected: selected,
              onTap: onLinkTap,
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.xs,
              vertical: 4,
            ),
            child: Container(
              height: 40,
              decoration: BoxDecoration(
                color: AppColors.hoverState,
                borderRadius: BorderRadius.circular(AppShapes.radiusSm),
              ),
              child: Row(
                children: [
                  Expanded(
                    flex: 5,
                    child: GestureDetector(
                      onTap: onFilterTap,
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.tune_rounded,
                              size: 16, color: AppColors.primary),
                          const SizedBox(width: 6),
                          Text(
                            l10n.translate('filter'),      // ★
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                              color: AppColors.primary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  Container(
                    width: 1,
                    height: 24,
                    color: AppColors.borderLight,
                  ),
                  Expanded(
                    flex: 3,
                    child: GestureDetector(
                      onTap: onSortTap,
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.swap_vert_rounded,
                              size: 16, color: AppColors.primary),
                          const SizedBox(width: 4),
                          Text(
                            l10n.translate('sort_by'),     // ★
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                              color: AppColors.primary,
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
        ],
      ),
    );
  }

  @override
  double get maxExtent => 44 + 4 + 48;
  @override
  double get minExtent => 44 + 4 + 48;
  @override
  bool shouldRebuild(covariant _QuickLinksAndFilterSortDelegate oldDelegate) =>
      oldDelegate.selected != selected;
}
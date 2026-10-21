import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_staggered_grid_view/flutter_staggered_grid_view.dart';
import '../api/client.dart';
import '../models/product.dart';
import '../models/filter_params.dart';
import '../theme/app_theme.dart';
import '../l10n/app_localizations.dart';
import '../widgets/product_card.dart';
import '../widgets/search_bar.dart';
import '../widgets/notification_bell.dart';
import '../widgets/quick_links_bar.dart';
import '../widgets/bottom_nav_bar.dart';
import '../widgets/filter_sheet.dart';
import '../widgets/sort_sheet.dart';
import '../providers/tab_provider.dart';

class BestSellersScreen extends ConsumerStatefulWidget {
  const BestSellersScreen({Key? key}) : super(key: key);

  @override
  ConsumerState<BestSellersScreen> createState() => _BestSellersScreenState();
}

class _BestSellersScreenState extends ConsumerState<BestSellersScreen> {
  List<Product> _products = [];
  bool _isLoading = true;
  String? _error;

  FilterParams _currentFilters = FilterParams();
  String _sortBy = 'best_sellers';

  late List<Map<String, dynamic>> _quickLinks;
  String _selectedQuickLink = '';

  // Category chips state
  List<Map<String, dynamic>> _allCategories = [];
  List<Map<String, dynamic>> _subCategories = [];
  int? _selectedCategoryId;

  @override
  void initState() {
    super.initState();
    _fetchCategories().then((_) => _fetchProducts());
  }

  Future<void> _fetchCategories() async {
    try {
      final res = await ApiClient.instance.get('/categories');
      final List data = res.data is List ? res.data : (res.data['data'] ?? []);
      if (mounted) {
        setState(() {
          _allCategories = data
              .map((c) => {'id': c['id'], 'name': c['name'].toString()})
              .toList();
        });
      }
    } catch (_) {}
  }

  Future<void> _fetchProducts() async {
    final l10n = AppLocalizations.of(context);
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final queryParams = <String, dynamic>{
        'sort': _sortBy,
        ..._currentFilters.toQueryParams(),
        if (_selectedCategoryId != null) 'category': _selectedCategoryId.toString(),
        '_t': DateTime.now().millisecondsSinceEpoch,   // cache buster
      };
      final response = await ApiClient.instance.get('/products', queryParameters: queryParams);
      final List data = response.data['data'] ?? response.data;
      final products = data
          .map((json) => Product.fromJson(Map<String, dynamic>.from(json)))
          .toList();

      final Set<int> usedCategoryIds = products
          .map((p) => p.categoryId)
          .where((id) => id != null)
          .cast<int>()
          .toSet();

      final List<Map<String, dynamic>> relevant = _allCategories
          .where((cat) => usedCategoryIds.contains(cat['id']))
          .toList();

      if (mounted) {
        setState(() {
          _products = products;
          _subCategories = relevant;
          _isLoading = false;
        });
      }
    } catch (e) {
      setState(() {
        _products = [];
        _isLoading = false;
        _error = l10n.translate('failed_load_products');
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
        context: {},
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
          setState(() {
            _sortBy = value;
            // ★ Clear price filter so sorting is visible
            _currentFilters.priceMin = null;
            _currentFilters.priceMax = null;
          });
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
    final l10n = AppLocalizations.of(context);

    _quickLinks = [
      {'name': l10n.translate('explore'),         'route': '/home'},
      {'name': l10n.translate('all_products'),    'route': '/all-products'},
      {'name': l10n.translate('new_arrivals'),    'route': '/new-arrivals'},
      {'name': l10n.translate('best_sellers'),    'route': '/best-sellers'},
      {'name': l10n.translate('trending'),        'route': '/trending'},
      {'name': l10n.translate('hot_deals_title'), 'route': '/hot-deals'},
      {'name': l10n.translate('packages'),        'route': '/packages'},
      {'name': l10n.translate('collections'),     'route': '/collections'},
    ];
    if (_selectedQuickLink.isEmpty ||
        !_quickLinks.any((link) => link['name'] == _selectedQuickLink)) {
      _selectedQuickLink = l10n.translate('best_sellers');
    }

    final bool showEmpty = !_isLoading && _error == null && _products.isEmpty;
    final bool filterActive = _currentFilters.hasActiveFilters;
    final bool sortActive = _sortBy.isNotEmpty && _sortBy != 'best_sellers';

    return Scaffold(
      backgroundColor: AppColors.pageBackground,
      body: SafeArea(
        child: CustomScrollView(
          slivers: [
            // Search bar – reduced padding
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.xs, 2,
                  AppSpacing.xs, 2,
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

            // Pinned header with updated spacing and buttons
            SliverPersistentHeader(
              pinned: true,
              delegate: _QuickLinksAndFilterSortDelegate(
                links: _quickLinks,
                selected: _selectedQuickLink,
                onLinkTap: _onQuickLinkTap,
                onFilterTap: _showFilterBottomSheet,
                onSortTap: _showSortBottomSheet,
                l10n: l10n,
                filterActive: filterActive,
                sortActive: sortActive,
              ),
            ),

            // ── Gold/Amber rectangular slim chips ──
            if (_subCategories.isNotEmpty)
              SliverToBoxAdapter(
                child: Container(
                  height: 28,
                  margin: const EdgeInsets.only(top: 4, bottom: 2),
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs),
                    itemCount: _subCategories.length + 1,
                    separatorBuilder: (_, __) => const SizedBox(width: 4),
                    itemBuilder: (context, index) {
                      final isAll = index == 0;
                      final catId = isAll ? null : (_subCategories[index - 1]['id'] as int);
                      final catName = isAll ? l10n.translate('all') : (_subCategories[index - 1]['name'] as String);
                      final selected = _selectedCategoryId == catId;

                      return GestureDetector(
                        onTap: () {
                          setState(() => _selectedCategoryId = catId);
                          _fetchProducts();
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: selected ? Colors.amber.shade700 : Colors.grey.shade200,
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                isAll ? Icons.all_inclusive : Icons.emoji_events_rounded,
                                size: 12,
                                color: selected ? Colors.white : Colors.amber.shade700,
                              ),
                              const SizedBox(width: 3),
                              Text(
                                catName,
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                                  color: selected ? Colors.white : AppColors.textPrimary,
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
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
                              Icons.emoji_events_rounded,
                              color: Colors.white,
                              size: 36,
                            ),
                          ),
                          const SizedBox(height: 20),
                          Text(
                            l10n.translate('no_best_sellers_yet'),
                            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.w600,
                                  color: AppColors.textPrimary,
                                ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            l10n.translate('best_sellers_empty_msg'),
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

    // ★ Staggered grid – no empty spaces
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
          child: ProductCard(product: product, isDeal: false),
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

// ─── Delegate with "Filter by" / "Sort by" and active dots ──────
class _QuickLinksAndFilterSortDelegate extends SliverPersistentHeaderDelegate {
  final List<Map<String, dynamic>> links;
  final String selected;
  final ValueChanged<Map<String, dynamic>> onLinkTap;
  final VoidCallback onFilterTap;
  final VoidCallback onSortTap;
  final AppLocalizations l10n;
  final bool filterActive;
  final bool sortActive;

  _QuickLinksAndFilterSortDelegate({
    required this.links,
    required this.selected,
    required this.onLinkTap,
    required this.onFilterTap,
    required this.onSortTap,
    required this.l10n,
    required this.filterActive,
    required this.sortActive,
  });

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlapsContent) {
    return ColoredBox(
      color: AppColors.cardBackground,
      child: Transform.translate(
        offset: const Offset(0, -3),
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
            const SizedBox(height: 2),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs),
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
                      child: InkWell(
                        onTap: onFilterTap,
                        borderRadius: BorderRadius.circular(AppShapes.radiusSm),
                        child: Center(
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.tune_rounded,
                                  size: 16, color: AppColors.primary),
                              const SizedBox(width: 6),
                              const Text(
                                'Filter by',
                                style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w700,
                                    color: AppColors.primary),
                              ),
                              if (filterActive)
                                Container(
                                  margin: const EdgeInsets.only(left: 4),
                                  width: 8, height: 8,
                                  decoration: const BoxDecoration(
                                    color: Colors.blue, shape: BoxShape.circle,
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    Container(width: 1, height: 24, color: AppColors.borderLight),
                    Expanded(
                      flex: 3,
                      child: InkWell(
                        onTap: onSortTap,
                        borderRadius: BorderRadius.circular(AppShapes.radiusSm),
                        child: Center(
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.swap_vert_rounded,
                                  size: 16, color: AppColors.primary),
                              const SizedBox(width: 4),
                              Text(
                                l10n.translate('sort_by'),
                                style: const TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w700,
                                    color: AppColors.primary),
                              ),
                              if (sortActive)
                                Container(
                                  margin: const EdgeInsets.only(left: 4),
                                  width: 8, height: 8,
                                  decoration: const BoxDecoration(
                                    color: Colors.blue, shape: BoxShape.circle,
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  double get maxExtent => 44 + 2 + 40;
  @override
  double get minExtent => 44 + 2 + 40;

  @override
  bool shouldRebuild(covariant _QuickLinksAndFilterSortDelegate oldDelegate) =>
      oldDelegate.selected != selected ||
      oldDelegate.filterActive != filterActive ||
      oldDelegate.sortActive != sortActive;
}
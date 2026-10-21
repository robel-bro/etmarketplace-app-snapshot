import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_staggered_grid_view/flutter_staggered_grid_view.dart';
import '../api/client.dart';
import '../models/product.dart';
import '../models/filter_params.dart';
import '../theme/app_theme.dart';
import '../l10n/app_localizations.dart';
import '../widgets/hot_deal_card.dart';
import '../widgets/search_bar.dart';
import '../widgets/notification_bell.dart';
import '../widgets/quick_links_bar.dart';
import '../widgets/bottom_nav_bar.dart';
import '../widgets/filter_sheet.dart';
import '../widgets/sort_sheet.dart';
import '../providers/tab_provider.dart';

class HotDealsScreen extends ConsumerStatefulWidget {
  const HotDealsScreen({Key? key}) : super(key: key);

  @override
  ConsumerState<HotDealsScreen> createState() => _HotDealsScreenState();
}

class _HotDealsScreenState extends ConsumerState<HotDealsScreen> {
  List<Product> _products = [];
  bool _isLoading = true;
  String? _error;

  FilterParams _currentFilters = FilterParams();
  String _sortBy = '';

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
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final queryParams = <String, dynamic>{
        'is_hot_deal': 'true',
        if (_sortBy.isNotEmpty) 'sort': _sortBy,
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
        _error = 'Failed to load hot deals.';
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
        context: {'is_hot_deal': 'true'},
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

  void _onCategoryTap(int? catId) {
    setState(() => _selectedCategoryId = catId);
    _fetchProducts();
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
      _selectedQuickLink = l10n.translate('hot_deals_title');
    }

    final bool showEmpty = !_isLoading && _error == null && _products.isEmpty;
    final bool filterActive = _currentFilters.hasActiveFilters;
    final bool sortActive = _sortBy.isNotEmpty;

    return Scaffold(
      backgroundColor: AppColors.pageBackground,
      body: SafeArea(
        child: CustomScrollView(
          slivers: [
            // Search bar
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

            // Pinned header – chips + filter/sort icons with active dots
            SliverPersistentHeader(
              pinned: true,
              delegate: _HotDealsHeaderDelegate(
                links: _quickLinks,
                selected: _selectedQuickLink,
                onLinkTap: _onQuickLinkTap,
                subCategories: _subCategories,
                selectedCategoryId: _selectedCategoryId,
                onCategoryTap: _onCategoryTap,
                onFilterTap: _showFilterBottomSheet,
                onSortTap: _showSortBottomSheet,
                l10n: l10n,
                filterActive: filterActive,
                sortActive: sortActive,
              ),
            ),

            if (!showEmpty)
              SliverToBoxAdapter(
                child: Container(
                  color: const Color(0xFFFFF0F0),
                  child: _isLoading ? _buildShimmerGrid() : _buildProductGrid(),
                ),
              ),

            if (showEmpty)
              SliverFillRemaining(
                hasScrollBody: false,
                child: Container(
                  color: const Color(0xFFFFF0F0),
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
                              Icons.local_fire_department_outlined,
                              color: Colors.white,
                              size: 36,
                            ),
                          ),
                          const SizedBox(height: 20),
                          Text(
                            l10n.translate('no_hot_deals_yet'),
                            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.w600,
                                  color: AppColors.textPrimary,
                                ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            l10n.translate('hot_deals_empty_msg'),
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
                child: Container(color: const Color(0xFFFFF0F0)),
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
            _error!,
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
          child: HotDealCard(product: product),
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

// ─── Delegate with chips scrolling UNDER the filter/sort icons & active dots ──────
class _HotDealsHeaderDelegate extends SliverPersistentHeaderDelegate {
  final List<Map<String, dynamic>> links;
  final String selected;
  final ValueChanged<Map<String, dynamic>> onLinkTap;
  final List<Map<String, dynamic>> subCategories;
  final int? selectedCategoryId;
  final ValueChanged<int?> onCategoryTap;
  final VoidCallback onFilterTap;
  final VoidCallback onSortTap;
  final AppLocalizations l10n;
  final bool filterActive;
  final bool sortActive;

  _HotDealsHeaderDelegate({
    required this.links,
    required this.selected,
    required this.onLinkTap,
    required this.subCategories,
    required this.selectedCategoryId,
    required this.onCategoryTap,
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
            // Quick links row
            SizedBox(
              height: 44,
              child: QuickLinksBar(
                links: links,
                selected: selected,
                onTap: onLinkTap,
              ),
            ),
            const SizedBox(height: 2),

            // Chips + overlaid icons (using Stack)
            Padding(
              padding: const EdgeInsets.only(right: 0),
              child: SizedBox(
                height: 28,
                child: subCategories.isEmpty
                    ? Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          _buildFilterIcon(),
                          const SizedBox(width: 8),
                          _buildSortIcon(),
                        ],
                      )
                    : Stack(
                        children: [
                          // Full-width scrollable chips
                          Positioned.fill(
                            child: ListView.separated(
                              scrollDirection: Axis.horizontal,
                              padding: const EdgeInsets.only(
                                left: AppSpacing.xs,
                                right: 70,
                              ),
                              itemCount: subCategories.length + 1,
                              separatorBuilder: (_, __) => const SizedBox(width: 4),
                              itemBuilder: (context, index) {
                                final isAll = index == 0;
                                final catId = isAll ? null : (subCategories[index - 1]['id'] as int);
                                final catName = isAll
                                    ? l10n.translate('all')
                                    : (subCategories[index - 1]['name'] as String);
                                final selected = selectedCategoryId == catId;

                                return GestureDetector(
                                  onTap: () => onCategoryTap(catId),
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                    decoration: BoxDecoration(
                                      color: selected ? Colors.redAccent : Colors.grey.shade200,
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(
                                          isAll
                                              ? Icons.all_inclusive
                                              : Icons.local_fire_department_rounded,
                                          size: 12,
                                          color: selected ? Colors.white : Colors.redAccent,
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

                          // Semi-transparent gradient + icons on the right
                          Positioned(
                            right: 0,
                            top: 0,
                            bottom: 0,
                            child: Container(
                              width: 70,
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  colors: [
                                    AppColors.cardBackground.withOpacity(0.0),
                                    AppColors.cardBackground.withOpacity(0.95),
                                  ],
                                  stops: const [0.0, 0.6],
                                  begin: Alignment.centerLeft,
                                  end: Alignment.centerRight,
                                ),
                              ),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.end,
                                children: [
                                  _buildFilterIcon(),
                                  const SizedBox(width: 8),
                                  _buildSortIcon(),
                                  const SizedBox(width: AppSpacing.xs),
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
      ),
    );
  }

  Widget _buildFilterIcon() {
    return InkWell(
      onTap: onFilterTap,
      borderRadius: BorderRadius.circular(6),
      child: Stack(
        children: [
          const Padding(
            padding: EdgeInsets.all(4),
            child: Icon(Icons.tune_rounded, size: 18, color: AppColors.primary),
          ),
          if (filterActive)
            Positioned(
              right: 2,
              top: 2,
              child: Container(
                width: 8, height: 8,
                decoration: const BoxDecoration(
                  color: Colors.blue,
                  shape: BoxShape.circle,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildSortIcon() {
    return InkWell(
      onTap: onSortTap,
      borderRadius: BorderRadius.circular(6),
      child: Stack(
        children: [
          const Padding(
            padding: EdgeInsets.all(4),
            child: Icon(Icons.swap_vert_rounded, size: 18, color: AppColors.primary),
          ),
          if (sortActive)
            Positioned(
              right: 2,
              top: 2,
              child: Container(
                width: 8, height: 8,
                decoration: const BoxDecoration(
                  color: Colors.blue,
                  shape: BoxShape.circle,
                ),
              ),
            ),
        ],
      ),
    );
  }

  @override
  double get maxExtent => 44 + 2 + 28;
  @override
  double get minExtent => 44 + 2 + 28;

  @override
  bool shouldRebuild(covariant _HotDealsHeaderDelegate oldDelegate) =>
      oldDelegate.selected != selected ||
      oldDelegate.subCategories != subCategories ||
      oldDelegate.selectedCategoryId != selectedCategoryId ||
      oldDelegate.filterActive != filterActive ||
      oldDelegate.sortActive != sortActive;
}
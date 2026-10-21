import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_staggered_grid_view/flutter_staggered_grid_view.dart';
import '../api/client.dart';
import '../models/product.dart';
import '../models/category.dart';
import '../models/filter_params.dart';
import '../theme/app_theme.dart';
import '../l10n/app_localizations.dart';
import '../widgets/product_card.dart';
import '../widgets/search_bar.dart';
import '../widgets/notification_bell.dart';
import '../widgets/filter_sheet.dart';
import '../widgets/sort_sheet.dart';
import 'product_detail_screen.dart';
import '../providers/tab_provider.dart';
import '../widgets/bottom_nav_bar.dart';

class ProductListingScreen extends ConsumerStatefulWidget {
  final String title;
  final String apiEndpoint;
  final List<Category>? categories;
  final bool showCategoryRow;
  final List<Category>? subcategories;
  final bool showSubcategoryRow;
  final void Function(Category)? onCategoryTap;
  final List<String>? brandFilters;
  final bool showBrandRow;
  final int? initialSubcategoryId;
  final int? mainCategoryId;
  final String? heroImageUrl;

  ProductListingScreen({
    required this.title,
    required this.apiEndpoint,
    this.categories,
    this.showCategoryRow = false,
    this.subcategories,
    this.showSubcategoryRow = false,
    this.onCategoryTap,
    this.brandFilters,
    this.showBrandRow = false,
    this.initialSubcategoryId,
    this.mainCategoryId,
    this.heroImageUrl,
    Key? key,
  }) : super(key: key);

  @override
  ConsumerState<ProductListingScreen> createState() =>
      _ProductListingScreenState();
}

class _ProductListingScreenState extends ConsumerState<ProductListingScreen> {
  List<Product> _products = [];
  bool _isLoading = true;
  bool _isLoadingMore = false;
  int _currentPage = 1;
  final int _perPage = 10;
  bool _hasMore = true;
  String? _error;

  FilterParams _currentFilters = FilterParams();
  String _sortBy = '';

  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    if (widget.initialSubcategoryId != null) {
      _currentFilters.categoryIds = [widget.initialSubcategoryId!];
    }
    _scrollController.addListener(_onScroll);
    _fetchProducts();
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _fetchProducts({bool loadMore = false}) async {
    if (loadMore) {
      if (!_hasMore || _isLoadingMore) return;
      setState(() => _isLoadingMore = true);
    } else {
      setState(() {
        _isLoading = true;
        _error = null;
        _currentPage = 1;
      });
    }

    try {
      final queryParams = <String, dynamic>{
        'page': _currentPage,
        'per_page': _perPage,
        if (_sortBy.isNotEmpty) 'sort': _sortBy,
        ..._currentFilters.toQueryParams(),
        '_t': DateTime.now().millisecondsSinceEpoch,
      };

      final response = await ApiClient.instance.get(
        widget.apiEndpoint,
        queryParameters: queryParams,
      );
      final List data = response.data['data'] ?? response.data;
      final List<Product> newProducts =
          data.map((json) => Product.fromJson(json)).toList();

      setState(() {
        _hasMore = newProducts.length == _perPage;
        _currentPage++;
        if (loadMore) {
          _products.addAll(newProducts);
          _isLoadingMore = false;
        } else {
          _products = newProducts;
          _isLoading = false;
        }
      });
    } catch (_) {
      if (!loadMore) {
        setState(() {
          _products = [];
          _isLoading = false;
          _hasMore = false;
        });
      } else {
        setState(() => _isLoadingMore = false);
      }
    }
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 200) {
      _fetchProducts(loadMore: true);
    }
  }

  Future<void> _refresh() async {
    _products.clear();
    _currentPage = 1;
    _hasMore = true;
    await _fetchProducts();
  }

  void _resetFiltersAndSort() {
    setState(() {
      _currentFilters = FilterParams();
      _sortBy = '';
    });
    _refresh();
  }

  void _onSubcategoryTap(Category sub) {
    setState(() {
      if (_currentFilters.categoryIds.contains(sub.id)) {
        _currentFilters.categoryIds.remove(sub.id);
      } else {
        _currentFilters.categoryIds.clear();
        _currentFilters.categoryIds.add(sub.id);
      }
    });
    if (_scrollController.hasClients) {
      _scrollController.jumpTo(0.0);
    }
    _refresh();
  }

  void _onBrandTap(String brand) {
    setState(() {
      if (_currentFilters.brands.contains(brand)) {
        _currentFilters.brands.remove(brand);
      } else {
        _currentFilters.brands.add(brand);
      }
    });
    _refresh();
  }

  void _showFilterBottomSheet() {
    final ctx = <String, String>{};
    if (_currentFilters.categoryIds.isNotEmpty) {
      ctx['category'] = _currentFilters.categoryIds.first.toString();
    } else if (widget.mainCategoryId != null) {
      ctx['category'] = widget.mainCategoryId!.toString();
    } else if (widget.initialSubcategoryId != null) {
      ctx['category'] = widget.initialSubcategoryId.toString();
    }

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => FilterSheet(
        initialParams: _currentFilters,
        context: ctx,
        onApply: (newParams) {
          setState(() => _currentFilters = newParams);
          _refresh();
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
            _currentFilters.priceMin = null;
            _currentFilters.priceMax = null;
          });
          _refresh();
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final bool showEmpty = !_isLoading && _error == null && _products.isEmpty;
    final bool filterActive = _currentFilters.hasActiveFilters;
    final bool sortActive = _sortBy.isNotEmpty;

    return Scaffold(
      backgroundColor: AppColors.productListBackground,
      body: SafeArea(
        bottom: false,
        child: RefreshIndicator(
          onRefresh: _refresh,
          color: AppColors.primary,
          child: CustomScrollView(
            controller: _scrollController,
            slivers: [
              SliverPersistentHeader(pinned: true, delegate: _SearchBarDelegate()),

              if (widget.heroImageUrl != null && widget.heroImageUrl!.isNotEmpty)
                SliverToBoxAdapter(
                  child: SizedBox(
                    height: 200, width: double.infinity,
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        Image.network(widget.heroImageUrl!, fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => SizedBox.shrink()),
                        Positioned(bottom: 0, left: 0, right: 0, height: 60,
                          child: Container(
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                begin: Alignment.topCenter, end: Alignment.bottomCenter,
                                colors: [Colors.transparent, Colors.black.withOpacity(0.7)],
                              ),
                            ),
                          ),
                        ),
                        Positioned(bottom: 12, left: AppSpacing.md, right: AppSpacing.md,
                          child: Text(widget.title,
                            style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                              fontSize: 24, fontWeight: FontWeight.w800, color: Colors.white,
                              letterSpacing: -0.5,
                              shadows: [Shadow(color: Colors.black.withOpacity(0.5), blurRadius: 8, offset: Offset(0, 2))],
                            ),
                            maxLines: 2, overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

              SliverPersistentHeader(
                pinned: true,
                delegate: _FilterSortDelegate(
                  showSubcategoryRow: false, subcategories: [], selectedSubIds: [],
                  onSubTap: (_) {}, showBrandRow: false, brandFilters: [], selectedBrands: [], onBrandTap: (_) {},
                  onFilterTap: _showFilterBottomSheet, onSortTap: _showSortBottomSheet,
                  l10n: l10n, filterActive: filterActive, sortActive: sortActive,
                ),
              ),

              if (showEmpty)
                SliverFillRemaining(hasScrollBody: false, child: _emptyState(l10n))
              else if (_isLoading)
                _buildShimmerSliver()
              else if (_error != null)
                _buildErrorSliver(l10n)
              else ...[
                // ★ Staggered grid – no empty gaps, cards use their natural height
                SliverPadding(
                  padding: EdgeInsets.fromLTRB(AppSpacing.xs, 0, AppSpacing.xs, 0),
                  sliver: SliverMasonryGrid.count(
                    crossAxisCount: 2,
                    mainAxisSpacing: 4,
                    crossAxisSpacing: 4,
                    childCount: _products.length,
                    itemBuilder: (context, index) {
                      final product = _products[index];
                      return GestureDetector(
                        onTap: () => Navigator.push(context,
                          MaterialPageRoute(builder: (_) => ProductDetailScreen(productId: product.id))),
                        child: ProductCard(product: product, isDeal: false),
                      );
                    },
                  ),
                ),
                if (_isLoadingMore)
                  SliverToBoxAdapter(child: Padding(padding: EdgeInsets.all(16),
                      child: Center(child: CircularProgressIndicator(color: AppColors.primary)))),
                if (!_hasMore && _products.isNotEmpty)
                  SliverToBoxAdapter(child: Padding(padding: EdgeInsets.all(16),
                      child: Center(child: Text(l10n.translate('no_more_products'),
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: AppColors.textMuted))))),
                SliverFillRemaining(hasScrollBody: false, child: Container(color: AppColors.productListBackground)),
              ],
            ],
          ),
        ),
      ),
      bottomNavigationBar: BottomNavBar(selectedIndex: 0, onTap: (index) {
        Navigator.of(context).pushNamedAndRemoveUntil('/main', (route) => false);
        ref.read(tabProvider.notifier).state = index;
      }),
    );
  }

  // Empty state, shimmer, error state
  Widget _emptyState(AppLocalizations l10n) {
    return Center(
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: 32),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(width: 72, height: 72, decoration: BoxDecoration(color: AppColors.primary, shape: BoxShape.circle),
            child: Icon(Icons.inventory_2_outlined, color: Colors.white, size: 36)),
          SizedBox(height: 20),
          Text(l10n.translate('no_products_found'),
            style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
          SizedBox(height: 8),
          Text(l10n.translate('no_products_adjust_filters'), textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AppColors.textMuted)),
          SizedBox(height: 20),
          Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            OutlinedButton(onPressed: _refresh,
              style: OutlinedButton.styleFrom(side: BorderSide(color: AppColors.primary), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)), padding: EdgeInsets.symmetric(horizontal: 20, vertical: 10)),
              child: Text(l10n.translate('refresh'), style: TextStyle(color: AppColors.primary))),
            SizedBox(width: 12),
            OutlinedButton(onPressed: _resetFiltersAndSort,
              style: OutlinedButton.styleFrom(side: BorderSide(color: Colors.red), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)), padding: EdgeInsets.symmetric(horizontal: 20, vertical: 10)),
              child: Text('Reset Filters & Sort', style: TextStyle(color: Colors.red))),
          ]),
        ]),
      ),
    );
  }

  Widget _buildShimmerSliver() {
    return SliverToBoxAdapter(
      child: MasonryGridView.count(
        shrinkWrap: true,
        physics: NeverScrollableScrollPhysics(),
        crossAxisCount: 2,
        mainAxisSpacing: 4,
        crossAxisSpacing: 4,
        padding: const EdgeInsets.all(AppSpacing.xs),
        itemCount: 6,
        itemBuilder: (_, __) => Container(
          decoration: BoxDecoration(color: AppColors.cardBackground, borderRadius: BorderRadius.circular(AppShapes.radiusSm), border: Border.all(color: AppColors.borderLight)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Container(height: 140, decoration: BoxDecoration(color: Colors.grey.shade200, borderRadius: BorderRadius.vertical(top: Radius.circular(AppShapes.radiusSm)))),
            Padding(padding: const EdgeInsets.all(AppSpacing.xs), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Container(height: 12, width: double.infinity, color: Colors.grey.shade200), SizedBox(height: 4),
              Container(height: 12, width: 100, color: Colors.grey.shade200), SizedBox(height: 6),
              Container(height: 16, width: 70, color: Colors.grey.shade200), SizedBox(height: 4),
              Container(height: 12, width: 60, color: Colors.grey.shade200),
            ])),
          ]),
        ),
      ),
    );
  }

  Widget _buildErrorSliver(AppLocalizations l10n) {
    return SliverFillRemaining(hasScrollBody: false, child: Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
      Icon(Icons.error_outline_rounded, size: 64, color: AppColors.textMuted), SizedBox(height: 16),
      Text(l10n.translate('oops_something_wrong'), style: Theme.of(context).textTheme.bodyLarge), SizedBox(height: 8),
      Text(_error ?? '', style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: AppColors.textMuted), textAlign: TextAlign.center), SizedBox(height: 20),
      ElevatedButton.icon(onPressed: _refresh, icon: Icon(Icons.refresh_rounded, size: 18), label: Text(l10n.translate('try_again')),
        style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary, foregroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)), padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10))),
    ])));
  }
}

// ── Search bar delegate – compact 2px padding ──
class _SearchBarDelegate extends SliverPersistentHeaderDelegate {
  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlapsContent) {
    return ColoredBox(color: AppColors.cardBackground, child: Padding(
      padding: const EdgeInsets.fromLTRB(AppSpacing.xs, 2, AppSpacing.xs, 2),
      child: Row(children: const [Expanded(child: RotatingSearchBar()), SizedBox(width: 4), NotificationBell()]),
    ));
  }
  @override double get maxExtent => 2 + 40 + 2;
  @override double get minExtent => 2 + 40 + 2;
  @override bool shouldRebuild(covariant SliverPersistentHeaderDelegate oldDelegate) => false;
}

// ── Filter / sort delegate with active dots ──
class _FilterSortDelegate extends SliverPersistentHeaderDelegate {
  final bool showSubcategoryRow;
  final List<Category> subcategories;
  final List<int> selectedSubIds;
  final void Function(Category) onSubTap;
  final bool showBrandRow;
  final List<String> brandFilters;
  final List<String> selectedBrands;
  final void Function(String) onBrandTap;
  final VoidCallback onFilterTap;
  final VoidCallback onSortTap;
  final AppLocalizations l10n;
  final bool filterActive;
  final bool sortActive;

  _FilterSortDelegate({
    required this.showSubcategoryRow,
    required this.subcategories,
    required this.selectedSubIds,
    required this.onSubTap,
    required this.showBrandRow,
    required this.brandFilters,
    required this.selectedBrands,
    required this.onBrandTap,
    required this.onFilterTap,
    required this.onSortTap,
    required this.l10n,
    required this.filterActive,
    required this.sortActive,
  });

  static const double _chipRowHeight = 28;
  static const double _filterHeight = 34;

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlapsContent) {
    return ColoredBox(
      color: AppColors.cardBackground,
      child: Column(
        children: [
          Padding(
            padding: EdgeInsets.fromLTRB(AppSpacing.xs, 2, AppSpacing.xs, AppSpacing.xs),
            child: Container(
              height: _filterHeight,
              decoration: BoxDecoration(color: AppColors.hoverState, borderRadius: BorderRadius.circular(AppShapes.radiusSm)),
              child: Row(children: [
                Expanded(flex: 5, child: InkWell(onTap: onFilterTap, borderRadius: BorderRadius.circular(AppShapes.radiusSm),
                  child: Center(child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(Icons.tune_rounded, size: 16, color: AppColors.primary), const SizedBox(width: 4),
                    const Text('Filter by', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.primary)),
                    if (filterActive) Container(margin: const EdgeInsets.only(left: 4), width: 8, height: 8, decoration: const BoxDecoration(color: Colors.blue, shape: BoxShape.circle)),
                  ])))),
                Container(width: 1, height: 22, color: AppColors.borderLight),
                Expanded(flex: 3, child: InkWell(onTap: onSortTap, borderRadius: BorderRadius.circular(AppShapes.radiusSm),
                  child: Center(child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(Icons.swap_vert_rounded, size: 16, color: AppColors.primary), const SizedBox(width: 3),
                    const Text('Sort by', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.primary)),
                    if (sortActive) Container(margin: const EdgeInsets.only(left: 4), width: 8, height: 8, decoration: const BoxDecoration(color: Colors.blue, shape: BoxShape.circle)),
                  ])))),
              ]),
            ),
          ),
        ],
      ),
    );
  }

  @override double get maxExtent {
    double h = 0;
    if (showSubcategoryRow) h += _chipRowHeight;
    if (showBrandRow) h += _chipRowHeight;
    h += 2 + _filterHeight + AppSpacing.xs;
    return h;
  }
  @override double get minExtent => maxExtent;
  @override bool shouldRebuild(covariant _FilterSortDelegate old) =>
      old.showSubcategoryRow != showSubcategoryRow ||
      old.showBrandRow != showBrandRow ||
      old.selectedSubIds != selectedSubIds ||
      old.selectedBrands != selectedBrands ||
      old.filterActive != filterActive ||
      old.sortActive != sortActive;
}
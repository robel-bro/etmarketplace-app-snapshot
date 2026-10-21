// 📁 lib/screens/flash_deals_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_staggered_grid_view/flutter_staggered_grid_view.dart';
import '../api/client.dart';
import '../models/product.dart';
import '../models/filter_params.dart';
import '../theme/app_theme.dart';
import '../widgets/product_card.dart';
import '../widgets/search_bar.dart';
import '../widgets/notification_bell.dart';
import '../widgets/quick_links_bar.dart';
import '../widgets/bottom_nav_bar.dart';
import '../widgets/filter_sheet.dart';
import '../widgets/sort_sheet.dart';
import '../providers/tab_provider.dart';

class FlashDealsScreen extends ConsumerStatefulWidget {
  const FlashDealsScreen({Key? key}) : super(key: key);

  @override
  ConsumerState<FlashDealsScreen> createState() => _FlashDealsScreenState();
}

class _FlashDealsScreenState extends ConsumerState<FlashDealsScreen> {
  List<Product> _products = [];
  bool _isLoading = true;
  String? _error;

  FilterParams _currentFilters = FilterParams();
  String _sortBy = '';

  final List<Map<String, dynamic>> _quickLinks = [
    {'name': 'Explore', 'route': '/home'},
    {'name': 'All Products', 'route': '/all-products'},
    {'name': 'New Arrivals', 'route': '/new-arrivals'},
    {'name': 'Best Sellers', 'route': '/best-sellers'},
    {'name': 'Trending', 'route': '/trending'},
    {'name': 'Flash Sales', 'route': '/flash-deals'},
    {'name': 'Super Deals', 'route': '/super-deals'},
    {'name': 'Packages', 'route': '/packages'},
    {'name': 'Collections', 'route': '/collections'},
  ];

  String _selectedQuickLink = 'Flash Sales';

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
        'is_flash_sale': 'true',
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
        context: {'is_flash_sale': 'true'},
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

  // ★ FIXED: safely reset to main screen instead of crashing with popUntil
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
    final bool showEmpty = !_isLoading && _error == null && _products.isEmpty;

    return Scaffold(
      backgroundColor: AppColors.pageBackground,
      body: SafeArea(
        child: CustomScrollView(
          slivers: [
            // Search + notification bell – edge‑to‑edge, tight gap (white)
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

            // Combined pinned header: Quick Links + Filter/Sort (white)
            SliverPersistentHeader(
              pinned: true,
              delegate: _QuickLinksAndFilterSortDelegate(
                links: _quickLinks,
                selected: _selectedQuickLink,
                onLinkTap: _onQuickLinkTap,
                onFilterTap: _showFilterBottomSheet,
                onSortTap: _showSortBottomSheet,
              ),
            ),

            // Product grid area (soft red)
            if (!showEmpty)
              SliverToBoxAdapter(
                child: Container(
                  color: const Color(0xFFFFF0F0),
                  child: _isLoading ? _buildShimmerGrid() : _buildProductGrid(),
                ),
              ),

            // If no products, show a centred empty state with filled orange circle icon
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
                          // Filled orange circle with white icon
                          Container(
                            width: 72,
                            height: 72,
                            decoration: const BoxDecoration(
                              color: AppColors.primary,
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(
                              Icons.local_offer_outlined,
                              color: Colors.white,
                              size: 36,
                            ),
                          ),
                          const SizedBox(height: 20),
                          Text(
                            'No Flash Deals Yet',
                            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.w600,
                                  color: AppColors.textPrimary,
                                ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Exciting flash deals will appear here once they are live. Check back soon!',
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
              // Fill remaining space with red when products exist
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

  // ---------- Product Grid (masonry, variable height) ----------
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

  // ---------- Shimmer Grid (masonry, placeholder) ----------
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

// ─── Combined delegate: Quick Links + Filter/Sort bar (updated labels) ──────
class _QuickLinksAndFilterSortDelegate extends SliverPersistentHeaderDelegate {
  final List<Map<String, dynamic>> links;
  final String selected;
  final ValueChanged<Map<String, dynamic>> onLinkTap;
  final VoidCallback onFilterTap;
  final VoidCallback onSortTap;

  _QuickLinksAndFilterSortDelegate({
    required this.links,
    required this.selected,
    required this.onLinkTap,
    required this.onFilterTap,
    required this.onSortTap,
  });

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlapsContent) {
    return ColoredBox(
      color: AppColors.cardBackground,
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
          // Filter & Sort bar – single rectangular strip, bold orange "Sort by"
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
                  // Filter (takes most space)
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
                            'Filter',
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
                  // Vertical divider
                  Container(
                    width: 1,
                    height: 24,
                    color: AppColors.borderLight,
                  ),
                  // Sort (compact) – "Sort by"
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
                            'Sort by',
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
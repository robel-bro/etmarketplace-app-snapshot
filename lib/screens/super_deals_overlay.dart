// 📁 lib/screens/super_deals_overlay.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_staggered_grid_view/flutter_staggered_grid_view.dart';
import 'package:lottie/lottie.dart';
import '../api/client.dart';
import '../models/product.dart';
import '../models/filter_params.dart';
import '../providers/cart_provider.dart';
import '../theme/app_theme.dart';
import '../widgets/super_deal_card.dart';
import '../widgets/filter_sheet.dart';
import '../widgets/sort_sheet.dart';
import 'product_detail_screen.dart';
import 'cart_screen.dart';

class SuperDealsOverlay extends ConsumerStatefulWidget {
  const SuperDealsOverlay({Key? key}) : super(key: key);
  @override
  ConsumerState<SuperDealsOverlay> createState() => _SuperDealsOverlayState();
}

class _SuperDealsOverlayState extends ConsumerState<SuperDealsOverlay> {
  List<Product> _products = [];
  bool _isLoading = true;
  String? _error;
  DateTime? _globalEndAt;

  FilterParams _currentFilters = FilterParams();
  String _sortBy = 'relevance';

  List<Map<String, dynamic>> _allCategories = [];
  List<Map<String, dynamic>> _subCategories = [];
  int? _selectedCategoryId;

  @override
  void initState() {
    super.initState();
    _fetchCategories();
    _fetchSuperProducts();
  }

  Future<void> _fetchCategories() async {
    try {
      final res = await ApiClient.instance.get('/categories');
      final List data = res.data is List ? res.data : (res.data['data'] ?? []);
      _allCategories = data
          .map((c) => {'id': c['id'], 'name': c['name'].toString()})
          .toList();
    } catch (_) {}
  }

  Future<void> _fetchSuperProducts() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final queryParams = <String, dynamic>{
        'is_super_deal': 'true',
        if (_sortBy.isNotEmpty) 'sort': _sortBy,
        ..._currentFilters.toQueryParams(),
        if (_selectedCategoryId != null) 'category': _selectedCategoryId.toString(),
      };
      final response = await ApiClient.instance
          .get('/products', queryParameters: queryParams);
      final List data = response.data['data'] ?? response.data;
      final products = data
          .map((json) => Product.fromJson(Map<String, dynamic>.from(json)))
          .toList();

      // Build chips from categories that appear in the products
      final Set<int> usedCategoryIds = products
          .map((p) => p.categoryId)
          .where((id) => id != null)
          .cast<int>()
          .toSet();
      final List<Map<String, dynamic>> relevant = _allCategories
          .where((cat) => usedCategoryIds.contains(cat['id']))
          .toList();

      DateTime? earliest;
      for (final p in products) {
        if (p.superDealEndsAt != null) {
          if (earliest == null || p.superDealEndsAt!.isBefore(earliest!)) {
            earliest = p.superDealEndsAt;
          }
        }
      }

      if (mounted) {
        setState(() {
          _products = products;
          _subCategories = relevant;
          _globalEndAt = earliest;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _products = [];
          _isLoading = false;
          _error = e.toString();
        });
      }
    }
  }

  void _showFilterSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => FilterSheet(
        initialParams: _currentFilters,
        context: {'is_super_deal': 'true'},
        onApply: (newParams) {
          setState(() => _currentFilters = newParams);
          _fetchSuperProducts();
        },
      ),
    );
  }

  void _showSortSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => SortSheet(
        selectedSort: _sortBy,
        onSortSelected: (value) {
          setState(() => _sortBy = value);
          _fetchSuperProducts();
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cart = ref.watch(cartProvider);
    final cartItemCount = cart?.itemCount ?? 0;

    return Scaffold(
      backgroundColor: AppColors.productListBackground,
      appBar: _buildAppBar(cartItemCount),
      body: _isLoading
          ? const Center(
              child: CircularProgressIndicator(color: AppColors.primary))
          : _error != null
              ? Center(
                  child: Text('Error: $_error',
                      style: const TextStyle(color: AppColors.textPrimary)))
              : _products.isEmpty
                  ? _buildEmptyState()
                  : _buildProductGrid(),
    );
  }

  PreferredSizeWidget _buildAppBar(int cartItemCount) {
    return AppBar(
      elevation: 0,
      backgroundColor: Colors.transparent,
      iconTheme: const IconThemeData(color: Colors.white),
      titleSpacing: 0,
      title: Row(
        children: [
          GestureDetector(
            onTap: () => Navigator.pop(context),
            child: Padding(
              padding: const EdgeInsets.only(left: 8, right: 6),
              child: Icon(Icons.arrow_back_ios_new_rounded, size: 18, color: Colors.white),
            ),
          ),
          Container(
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              color: Colors.amber.withOpacity(0.25),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(Icons.star, color: Colors.amber, size: 18),
          ),
          const SizedBox(width: 6),
          const Expanded(
            child: Text(
              'Super Deals',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w700,
                fontSize: 18,
                letterSpacing: -0.5,
              ),
            ),
          ),
        ],
      ),
      actions: [
        Padding(
          padding: const EdgeInsets.only(right: 4),
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              IconButton(
                icon: const Icon(Icons.shopping_cart, size: 20, color: Colors.white),
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const CartScreen()),
                ),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
              ),
              if (cartItemCount > 0)
                Positioned(
                  right: 2,
                  top: 2,
                  child: Container(
                    padding: const EdgeInsets.all(2),
                    decoration: const BoxDecoration(
                      color: Colors.white,
                      shape: BoxShape.circle,
                    ),
                    constraints: const BoxConstraints(
                      minWidth: 16,
                      minHeight: 16,
                    ),
                    child: Text(
                      cartItemCount.toString(),
                      style: const TextStyle(
                        color: Colors.red,
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(right: 4),
          child: IconButton(
            icon: const Icon(Icons.tune, size: 20, color: Colors.white),
            onPressed: _showFilterSheet,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(right: 4),
          child: IconButton(
            icon: const Icon(Icons.sort, size: 20, color: Colors.white),
            onPressed: _showSortSheet,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
          ),
        ),
      ],
      flexibleSpace: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [Color(0xFF7B1FA2), Color(0xFF4A148C)],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        ),
      ),
      automaticallyImplyLeading: false,
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.shopping_bag_outlined,
              size: 64, color: AppColors.textMuted.withOpacity(0.4)),
          const SizedBox(height: 16),
          Text('No active super deals',
              style: TextStyle(
                  color: AppColors.textMuted,
                  fontSize: 16,
                  fontWeight: FontWeight.w500)),
          const SizedBox(height: 8),
          Text('Stay tuned for incredible offers ✨',
              style: TextStyle(
                  color: AppColors.primary.withOpacity(0.8), fontSize: 13)),
        ],
      ),
    );
  }

  Widget _buildProductGrid() {
    return SafeArea(
      child: RefreshIndicator(
        color: AppColors.primary,
        backgroundColor: AppColors.productListBackground,
        onRefresh: _fetchSuperProducts,
        child: CustomScrollView(
          slivers: [
            // ── Countdown ──
            if (_globalEndAt != null)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(0, 12, 0, 4),
                  child: _SuperCountdown(endAt: _globalEndAt!),
                ),
              ),

            // ── Sub‑category chips (purple accent, smaller, star icon) ──
            if (_subCategories.isNotEmpty)
              SliverToBoxAdapter(
                child: Container(
                  height: 34,                     // smaller row
                  margin: const EdgeInsets.only(bottom: 4),
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    itemCount: _subCategories.length + 1,   // +1 for "All"
                    separatorBuilder: (_, __) => const SizedBox(width: 6),
                    itemBuilder: (context, index) {
                      final isAll = index == 0;
                      final catId = isAll ? null : (_subCategories[index - 1]['id'] as int);
                      final catName = isAll ? 'All' : (_subCategories[index - 1]['name'] as String);
                      final selected = _selectedCategoryId == catId;

                      return GestureDetector(
                        onTap: () {
                          setState(() => _selectedCategoryId = catId);
                          _fetchSuperProducts();
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                          decoration: BoxDecoration(
                            color: selected ? Colors.purple.shade600 : Colors.white,
                            borderRadius: BorderRadius.circular(18),
                            border: Border.all(
                              color: selected ? Colors.purple.shade600 : Colors.purple.shade300,
                              width: 1,
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.star,
                                size: 14,
                                color: selected ? Colors.white : Colors.purple.shade400,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                catName,
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                                  color: selected ? Colors.white : Colors.purple.shade700,
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

            // ── Product grid – using the existing SuperDealCard ──
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(4, 0, 4, 24),
              sliver: SliverMasonryGrid.count(
                crossAxisCount: 2,
                mainAxisSpacing: 4,
                crossAxisSpacing: 4,
                childCount: _products.length,
                itemBuilder: (context, index) {
                  final product = _products[index];
                  return GestureDetector(
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) =>
                            ProductDetailScreen(productId: product.id),
                      ),
                    ),
                    child: SuperDealCard(product: product),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Countdown banner – purple accent, Lottie animation ──
class _SuperCountdown extends StatefulWidget {
  final DateTime endAt;
  const _SuperCountdown({required this.endAt});
  @override
  State<_SuperCountdown> createState() => _SuperCountdownState();
}

class _SuperCountdownState extends State<_SuperCountdown> {
  Timer? _timer;
  Duration _remaining = Duration.zero;

  @override
  void initState() {
    super.initState();
    _updateRemaining();
    _timer = Timer.periodic(
        const Duration(seconds: 1), (_) => _updateRemaining());
  }

  void _updateRemaining() {
    final diff = widget.endAt.difference(DateTime.now());
    setState(() {
      _remaining = diff.isNegative ? Duration.zero : diff;
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_remaining == Duration.zero) return const SizedBox.shrink();
    final h = _remaining.inHours;
    final m = _remaining.inMinutes.remainder(60);
    final s = _remaining.inSeconds.remainder(60);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.productListBackground,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 48,
            height: 48,
            child: Lottie.asset(
              'assets/animations/super_deal.json',
              fit: BoxFit.contain,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Limited time',
              style: TextStyle(
                color: Colors.black87,
                fontWeight: FontWeight.w600,
                fontSize: 15,
              ),
            ),
          ),
          _TimeBox(value: h, label: 'h'),
          const SizedBox(width: 6),
          _TimeBox(value: m, label: 'm'),
          const SizedBox(width: 6),
          _TimeBox(value: s, label: 's'),
        ],
      ),
    );
  }
}

class _TimeBox extends StatelessWidget {
  final int value;
  final String label;
  const _TimeBox({required this.value, required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        color: const Color(0xFFF5F5F5),
        borderRadius: BorderRadius.circular(8),
      ),
      alignment: Alignment.center,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            value.toString().padLeft(2, '0'),
            style: const TextStyle(
              color: Color(0xFF7B1FA2),
              fontWeight: FontWeight.w800,
              fontSize: 16,
              height: 1,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: TextStyle(
              color: Colors.grey.shade600,
              fontSize: 9,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
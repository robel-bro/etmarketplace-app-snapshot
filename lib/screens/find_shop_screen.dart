// lib/screens/find_shop_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:shimmer/shimmer.dart';
import '../api/client.dart';
import '../models/product.dart';
import '../utils/format_utils.dart';
import '../widgets/notification_bell.dart';
import '../theme/app_theme.dart';
import '../l10n/app_localizations.dart';
import 'product_detail_screen.dart';
import 'company_profile_screen.dart';

// ─────────────────────────────────────────────
// Providers
// ─────────────────────────────────────────────
final bulkOnlyProvider = StateProvider<bool>((ref) => false);

final allVendorsProvider = FutureProvider<List<Map<String, dynamic>>>((ref) async {
  final bulk = ref.watch(bulkOnlyProvider);
  final queryParams = <String, dynamic>{};
  if (bulk) queryParams['bulk'] = 'true';

  final response = await ApiClient.instance.get(
    '/api/v1/vendors',
    queryParameters: queryParams.isNotEmpty ? queryParams : null,
  );

  final raw = response.data;
  final List data = raw is List ? raw : (raw['data'] ?? []);

  final List<Map<String, dynamic>> vendors = [];
  for (final v in data) {
    if (v == null) continue;
    vendors.add({
      'id': v['id'].toString(),
      'name': v['business_name'] ?? 'Unknown',
      'imageUrl': v['logo_url'] ?? '',
      'category': v['category']?.toString() ?? 'General',
      'rating': (v['rating'] as num?)?.toDouble() ?? 0.0,
      'reviewsCount': v['reviews_count'] ?? 0,
      'totalSales': v['total_sales_count'] ?? 0,
      'address': v['business_address'] ?? '',
      'is_bulk_supplier': (v['is_bulk_supplier'] as bool?) ?? false,
      'is_company': (v['is_company'] as bool?) ?? false,
      'membership_tier': v['membership_tier']?.toString() ?? 'free',
      'featured': (v['featured'] as bool?) ?? false,
      'badge': v['badge']?.toString(),
    });
  }
  return vendors;
});

// ─────────────────────────────────────────────
// ★ Shimmer membership badge (no background, emoji + text, visible)
// ─────────────────────────────────────────────
class MembershipBadge extends StatelessWidget {
  final String tier;
  const MembershipBadge({Key? key, required this.tier}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final lower = tier.toLowerCase();
    String glyph;
    Color baseColor;

    if (lower.contains('platinum')) {
      glyph = '💎';
      baseColor = Colors.blue.shade700;
    } else if (lower.contains('gold')) {
      glyph = '🏆';
      baseColor = const Color(0xFFF59E0B);
    } else if (lower.contains('silver')) {
      glyph = '🥈';
      baseColor = const Color(0xFF9CA3AF);
    } else {
      glyph = '✨';
      baseColor = const Color(0xFF6B7280);
    }

    final highlightColor = Color.lerp(baseColor, Colors.white, 0.4)!;

    return Shimmer.fromColors(
      baseColor: baseColor,
      highlightColor: highlightColor,
      period: const Duration(milliseconds: 1500),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(glyph, style: TextStyle(fontSize: 13, color: baseColor)),
          const SizedBox(width: 3),
          Text(
            tier,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w800,
              color: baseColor,
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────
// ★ Company badge (sleek icon + text, no background)
// ─────────────────────────────────────────────
class CompanyBadge extends StatelessWidget {
  const CompanyBadge({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.business, size: 13, color: Colors.blue.shade700),
        const SizedBox(width: 2),
        Text(
          'COMPANY',
          style: TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w800,
            color: Colors.blue.shade700,
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────
// ★ Bulk badge (sleek icon + text, no background)
// ─────────────────────────────────────────────
class BulkBadge extends StatelessWidget {
  const BulkBadge({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.inventory_2, size: 13, color: Colors.orange.shade700),
        const SizedBox(width: 2),
        Text(
          'BULK',
          style: TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w800,
            color: Colors.orange.shade700,
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────
// Find Shop Screen
// ─────────────────────────────────────────────
class FindShopScreen extends ConsumerStatefulWidget {
  const FindShopScreen({Key? key}) : super(key: key);
  @override
  ConsumerState<FindShopScreen> createState() => _FindShopScreenState();
}

class _FindShopScreenState extends ConsumerState<FindShopScreen> {
  final TextEditingController _searchController = TextEditingController();
  double _minRating = 0.0;
  String _selectedCategory = 'All';
  String _sortBy = 'recommended';
  String _expandedRow = '';

  List<Map<String, dynamic>> _filteredVendors = [];
  List<String> _categories = ['All'];
  Map<String, List<Product>> _vendorProducts = {};

  late List<Map<String, dynamic>> _sortOptions;
  late List<Map<String, dynamic>> _ratingOptions;

  static const Map<String, int> _tierPriority = {
    'platinum': 4,
    'gold': 3,
    'silver': 2,
    'free': 1,
  };

  bool _needsRefresh = true;

  @override
  void initState() {
    super.initState();
    _searchController.addListener(_applyFilters);
    _needsRefresh = true;
  }

  @override
  void dispose() {
    _searchController.removeListener(_applyFilters);
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _fetchVendorProducts(String vendorId) async {
    try {
      final response = await ApiClient.instance.get(
        '/api/v1/products',
        queryParameters: {'vendor_id': vendorId, 'per_page': '5'},
      );
      final List raw = response.data['data'] ?? [];
      if (raw.isEmpty) return;
      final List<Product> products =
          raw.map((e) => Product.fromJson(Map<String, dynamic>.from(e))).toList();
      if (mounted) setState(() => _vendorProducts[vendorId] = products);
    } catch (_) {}
  }

  void _applyFilters() {
    final query = _searchController.text.toLowerCase();
    setState(() {
      _filteredVendors = _allVendors.where((v) {
        final matchesSearch = (v['name'] as String).toLowerCase().contains(query);
        final matchesRating = (v['rating'] as double) >= _minRating;
        final matchesCategory =
            _selectedCategory == 'All' || v['category'] == _selectedCategory;
        return matchesSearch && matchesRating && matchesCategory;
      }).toList();

      switch (_sortBy) {
        case 'rating':
          _filteredVendors.sort((a, b) => (b['rating'] as double).compareTo(a['rating'] as double));
          break;
        case 'reviews':
          _filteredVendors.sort((a, b) => (b['reviewsCount'] as int).compareTo(a['reviewsCount'] as int));
          break;
        case 'newest':
          break;
        case 'recommended':
        default:
          _filteredVendors.sort((a, b) {
            final aF = (a['featured'] as bool?) ?? false;
            final bF = (b['featured'] as bool?) ?? false;
            if (aF && !bF) return -1;
            if (!aF && bF) return 1;

            final aT = _tierPriority[a['membership_tier']] ?? 0;
            final bT = _tierPriority[b['membership_tier']] ?? 0;
            if (aT != bT) return bT.compareTo(aT);

            final r = (b['rating'] as double).compareTo(a['rating'] as double);
            if (r != 0) return r;

            final aS = (a['totalSales'] as int?) ?? 0;
            final bS = (b['totalSales'] as int?) ?? 0;
            return bS.compareTo(aS);
          });
          break;
      }
    });
  }

  List<Map<String, dynamic>> get _allVendors =>
      ref.watch(allVendorsProvider).valueOrNull ?? [];

  void _toggleBulk() {
    ref.read(bulkOnlyProvider.notifier).state = !ref.read(bulkOnlyProvider);
  }

  void _navigateToShop(String shopId) {
    final vendor = _filteredVendors.firstWhere((v) => v['id'] == shopId);
    final isBulk = (vendor['is_bulk_supplier'] as bool?) ?? false;
    final isCompany = (vendor['is_company'] as bool?) ?? false;

    if (isBulk || isCompany) {
      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => CompanyProfileScreen(companyId: shopId)),
      );
    } else {
      Navigator.pushNamed(context, '/shop', arguments: shopId);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final textTheme = Theme.of(context).textTheme;

    if (_needsRefresh) {
      ref.invalidate(allVendorsProvider);
      _needsRefresh = false;
    }

    final vendorsAsync = ref.watch(allVendorsProvider);
    final bool isLoading =
        vendorsAsync.isLoading || (vendorsAsync.hasValue && _categories.length <= 1);

    if (vendorsAsync.hasValue && _categories.length == 1 && _categories.first == 'All') {
      final cats = vendorsAsync.value!.map((v) => v['category'].toString()).toSet();
      final sortedCats = cats.toList()..sort();
      _categories = ['All', ...sortedCats];
      WidgetsBinding.instance.addPostFrameCallback((_) => _applyFilters());
    }

    if (vendorsAsync.hasValue) {
      for (final v in vendorsAsync.value!) {
        final id = v['id'];
        if (!_vendorProducts.containsKey(id)) {
          _fetchVendorProducts(id);
        }
      }
    }

    _sortOptions = [
      {'label': l10n.translate('sort_recommended'), 'value': 'recommended'},
      {'label': l10n.translate('sort_top_rated'), 'value': 'rating'},
      {'label': l10n.translate('sort_most_reviews'), 'value': 'reviews'},
      {'label': l10n.translate('sort_newest'), 'value': 'newest'},
    ];

    _ratingOptions = [
      {'label': l10n.translate('rating_all'), 'value': 0.0},
      {'label': l10n.translate('rating_4_above'), 'value': 4.0},
      {'label': l10n.translate('rating_3_above'), 'value': 3.0},
      {'label': l10n.translate('rating_2_above'), 'value': 2.0},
    ];

    return Scaffold(
      backgroundColor: Colors.grey.shade100,
      appBar: AppBar(
        toolbarHeight: 48,
        flexibleSpace: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [Color(0xFFFF7A00), Color(0xFFD84315)],
              begin: Alignment.centerLeft,
              end: Alignment.centerRight,
            ),
          ),
        ),
        elevation: 0,
        titleSpacing: 6,
        title: Row(
          children: [
            Expanded(child: _buildSearchField(l10n)),
            const SizedBox(width: 8),
            Theme(
              data: Theme.of(context).copyWith(iconTheme: const IconThemeData(color: Colors.white)),
              child: const NotificationBell(),
            ),
          ],
        ),
        automaticallyImplyLeading: false,
      ),
      body: isLoading
          ? const Center(child: CircularProgressIndicator(color: AppColors.primary))
          : vendorsAsync.hasError
              ? Center(
                  child: Text('Failed to load shops: ${vendorsAsync.error}',
                      style: TextStyle(color: AppColors.error)),
                )
              : CustomScrollView(
                  slivers: [
                    SliverToBoxAdapter(child: _buildFilterRow(l10n)),
                    if (_expandedRow == 'sort')
                      SliverToBoxAdapter(
                        child: _buildExpandedRow(
                          _sortOptions,
                          _sortBy,
                          (val) {
                            setState(() {
                              _sortBy = val;
                              _expandedRow = '';
                              _applyFilters();
                            });
                          },
                          'value',
                          'label',
                        ),
                      ),
                    if (_expandedRow == 'rating')
                      SliverToBoxAdapter(
                        child: _buildExpandedRow(
                          _ratingOptions,
                          _minRating,
                          (val) {
                            setState(() {
                              _minRating = (val as double);
                              _expandedRow = '';
                              _applyFilters();
                            });
                          },
                          'value',
                          'label',
                        ),
                      ),
                    if (_expandedRow == 'category')
                      SliverToBoxAdapter(child: _buildCategoryRow()),
                    SliverToBoxAdapter(child: _buildResultCount(l10n)),
                    if (_filteredVendors.isEmpty)
                      const SliverToBoxAdapter(child: _EmptyState())
                    else
                      SliverList(
                        delegate: SliverChildBuilderDelegate(
                          (context, index) {
                            final vendor = _filteredVendors[index];
                            final vendorId = vendor['id'];
                            final products = _vendorProducts[vendorId] ?? [];
                            return _ShopCard(
                              vendor: vendor,
                              products: products,
                              onTap: () => _navigateToShop(vendorId),
                              onProductTap: (productId) => Navigator.push(
                                context,
                                MaterialPageRoute(
                                    builder: (_) => ProductDetailScreen(productId: productId)),
                              ),
                            );
                          },
                          childCount: _filteredVendors.length,
                        ),
                      ),
                    const SliverToBoxAdapter(child: SizedBox(height: 60)),
                  ],
                ),
    );
  }

  Widget _buildFilterRow(AppLocalizations l10n) {
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.xs),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: EdgeInsets.zero,
        child: Row(
          children: [
            const SizedBox(width: AppSpacing.sm),
            _mainChip(
              _sortLabel(l10n),
              onTap: () => setState(() => _expandedRow = _expandedRow == 'sort' ? '' : 'sort'),
            ),
            const SizedBox(width: AppSpacing.xs),
            _mainChip(
              _ratingLabel(l10n),
              onTap: () =>
                  setState(() => _expandedRow = _expandedRow == 'rating' ? '' : 'rating'),
            ),
            const SizedBox(width: AppSpacing.xs),
            _mainChip(
              _categoryLabel(l10n),
              onTap: () =>
                  setState(() => _expandedRow = _expandedRow == 'category' ? '' : 'category'),
            ),
            const SizedBox(width: AppSpacing.xs),
            GestureDetector(
              onTap: _toggleBulk,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: ref.watch(bulkOnlyProvider)
                      ? AppColors.primary.withOpacity(0.1)
                      : AppColors.cardBackground,
                  borderRadius: BorderRadius.circular(AppShapes.radiusSm),
                  border: Border.all(
                    color: ref.watch(bulkOnlyProvider) ? AppColors.primary : AppColors.borderLight,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      ref.watch(bulkOnlyProvider) ? Icons.check_box : Icons.check_box_outline_blank,
                      size: 18,
                      color: ref.watch(bulkOnlyProvider)
                          ? AppColors.primary
                          : AppColors.textMuted,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      l10n.translate('bulk_suppliers_only'),
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        color: ref.watch(bulkOnlyProvider)
                            ? AppColors.primary
                            : AppColors.textPrimary,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
          ],
        ),
      ),
    );
  }

  Widget _buildExpandedRow(
    List<Map<String, dynamic>> options,
    dynamic current,
    void Function(dynamic) onSelect,
    String valueKey,
    String labelKey,
  ) {
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.xs),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: EdgeInsets.zero,
        child: Row(
          children: [
            const SizedBox(width: AppSpacing.sm),
            ...options.map((o) {
              final selected = current == o[valueKey];
              return Padding(
                padding: const EdgeInsets.only(right: AppSpacing.xs),
                child: _subChip(
                  o[labelKey] as String,
                  selected: selected,
                  onTap: () => onSelect(o[valueKey]),
                ),
              );
            }),
            const SizedBox(width: AppSpacing.sm),
          ],
        ),
      ),
    );
  }

  Widget _buildCategoryRow() {
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.xs),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: EdgeInsets.zero,
        child: Row(
          children: [
            const SizedBox(width: AppSpacing.sm),
            ..._categories.map((cat) {
              final selected = _selectedCategory == cat;
              return Padding(
                padding: const EdgeInsets.only(right: AppSpacing.xs),
                child: _subChip(
                  cat,
                  selected: selected,
                  onTap: () {
                    setState(() {
                      _selectedCategory = cat;
                      _expandedRow = '';
                      _applyFilters();
                    });
                  },
                ),
              );
            }),
            const SizedBox(width: AppSpacing.sm),
          ],
        ),
      ),
    );
  }

  Widget _buildResultCount(AppLocalizations l10n) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(AppSpacing.sm, AppSpacing.sm, AppSpacing.sm, AppSpacing.xs),
      child: Text(
        l10n.translate('shops_found').replaceAll('{count}', _filteredVendors.length.toString()),
        style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AppColors.textMuted),
      ),
    );
  }

  Widget _buildSearchField(AppLocalizations l10n) {
    return Container(
      height: 40,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(AppShapes.radiusMd),
      ),
      child: TextField(
        controller: _searchController,
        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.w500,
              color: AppColors.textPrimary,
              fontSize: 13,
              height: 1.0,
            ),
        decoration: InputDecoration(
          hintText: l10n.translate('search_shops_hint'),
          hintStyle: TextStyle(fontSize: 13, color: AppColors.textMuted),
          prefixIcon: const Padding(
            padding: EdgeInsets.only(left: 8, right: 8),
            child: Icon(Icons.search_rounded, size: 18, color: AppColors.primary),
          ),
          prefixIconConstraints: const BoxConstraints(minWidth: 0, minHeight: 0),
          border: InputBorder.none,
          enabledBorder: InputBorder.none,
          focusedBorder: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(vertical: 0, horizontal: 8),
          filled: true,
          fillColor: Colors.white,
        ),
      ),
    );
  }

  Widget _mainChip(String label, {VoidCallback? onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: AppColors.cardBackground,
          borderRadius: BorderRadius.circular(AppShapes.radiusSm),
          border: Border.all(color: AppColors.borderLight),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(label,
                style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: AppColors.textPrimary)),
            const SizedBox(width: 4),
            Icon(Icons.keyboard_arrow_down, size: 14, color: AppColors.textMuted),
          ],
        ),
      ),
    );
  }

  Widget _subChip(String label, {bool selected = false, VoidCallback? onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: selected ? AppColors.primary.withOpacity(0.08) : AppColors.cardBackground,
          borderRadius: BorderRadius.circular(AppShapes.radiusSm),
          border: Border.all(
            color: selected ? AppColors.primary : AppColors.borderLight,
            width: selected ? 1.5 : 1,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 11,
            fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
            color: selected ? AppColors.primary : AppColors.textPrimary,
          ),
        ),
      ),
    );
  }

  String _sortLabel(AppLocalizations l10n) {
    final label = _sortOptions.firstWhere((o) => o['value'] == _sortBy)['label'] as String;
    return '${l10n.translate("sort_label")}: $label';
  }

  String _ratingLabel(AppLocalizations l10n) {
    if (_minRating == 0) return l10n.translate('rating_label');
    return '${l10n.translate("rating_label")}: ${_minRating.toStringAsFixed(0)}★+';
  }

  String _categoryLabel(AppLocalizations l10n) {
    if (_selectedCategory == 'All') return l10n.translate('category_label');
    return '${l10n.translate("category_label")}: $_selectedCategory';
  }
}

// ─────────────────────────────────────────────
// Shop card – company badge next to name, membership badge next to reviews
// ─────────────────────────────────────────────
class _ShopCard extends StatelessWidget {
  final Map<String, dynamic> vendor;
  final List<Product> products;
  final VoidCallback onTap;
  final void Function(int productId) onProductTap;

  const _ShopCard({
    required this.vendor,
    required this.products,
    required this.onTap,
    required this.onProductTap,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final textTheme = Theme.of(context).textTheme;
    final name = vendor['name'] ?? '';
    final imageUrl = vendor['imageUrl'] ?? '';
    final category = vendor['category'] ?? 'General';
    final rating = (vendor['rating'] as num?)?.toDouble() ?? 0.0;
    final reviewsCount = vendor['reviewsCount'] ?? 0;
    final totalSales = vendor['totalSales'] ?? 0;
    final address = vendor['address'] ?? '';
    final isBulk = (vendor['is_bulk_supplier'] as bool?) ?? false;
    final isCompany = (vendor['is_company'] as bool?) ?? false;
    final membershipTier = vendor['membership_tier']?.toString() ?? 'free';

    // Build display badge text for membership
    String? badgeText = vendor['badge']?.toString();
    if ((badgeText == null || badgeText.isEmpty) &&
        membershipTier != 'free' &&
        membershipTier.isNotEmpty) {
      badgeText = '${membershipTier[0].toUpperCase()}${membershipTier.substring(1)} Seller';
    }

    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: AppSpacing.xs),
        decoration: BoxDecoration(
          color: Colors.grey.shade100,
          borderRadius: BorderRadius.circular(AppShapes.radiusMd),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.04),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(width: AppSpacing.sm),
                  CircleAvatar(
                    radius: 28,
                    backgroundColor: AppColors.hoverState,
                    backgroundImage: imageUrl.isNotEmpty ? NetworkImage(imageUrl) : null,
                    child: imageUrl.isEmpty
                        ? Icon(Icons.store, color: AppColors.textMuted, size: 28)
                        : null,
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  // Store name + company/bulk badges inline
                                  Wrap(
                                    crossAxisAlignment: WrapCrossAlignment.center,
                                    children: [
                                      Text(
                                        name,
                                        style: textTheme.bodyLarge?.copyWith(
                                          fontWeight: FontWeight.w700,
                                          color: AppColors.textPrimary,
                                          fontSize: 14,
                                        ),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                      if (isCompany) ...[
                                        const SizedBox(width: 6),
                                        const CompanyBadge(),
                                      ],
                                      if (isBulk && !isCompany) ...[
                                        const SizedBox(width: 6),
                                        const BulkBadge(),
                                      ],
                                    ],
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: AppSpacing.xs),
                            GestureDetector(
                              onTap: onTap,
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                decoration: BoxDecoration(
                                  gradient: const LinearGradient(
                                    colors: [Color(0xFFFF7A00), Color(0xFFD84315)],
                                    begin: Alignment.centerLeft,
                                    end: Alignment.centerRight,
                                  ),
                                  borderRadius:
                                      BorderRadius.circular(AppShapes.radiusSm),
                                ),
                                child: Text(
                                  l10n.translate('visit_shop'),
                                  style: textTheme.bodySmall?.copyWith(
                                    fontWeight: FontWeight.w700,
                                    color: Colors.white,
                                    fontSize: 11,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: AppSpacing.sm),
                          ],
                        ),
                        const SizedBox(height: 6),
                        // Rating row + membership badge
                        Row(
                          children: [
                            Icon(Icons.star, size: 13, color: AppColors.starGold),
                            const SizedBox(width: 2),
                            Text(
                              rating.toStringAsFixed(1),
                              style: textTheme.bodyMedium?.copyWith(
                                  fontWeight: FontWeight.w700,
                                  color: AppColors.textPrimary,
                                  fontSize: 12),
                            ),
                            const SizedBox(width: 4),
                            Text(
                              l10n
                                  .translate('reviews_count')
                                  .replaceAll('{count}', reviewsCount.toString()),
                              style: textTheme.bodySmall?.copyWith(
                                  color: AppColors.textMuted, fontSize: 11),
                            ),
                            // Membership badge right after review count
                            if (badgeText != null) ...[
                              const SizedBox(width: 6),
                              MembershipBadge(tier: badgeText),
                            ],
                            if (totalSales > 0) ...[
                              const SizedBox(width: 8),
                              Icon(Icons.sell, size: 13, color: AppColors.textMuted),
                              const SizedBox(width: 2),
                              Text(
                                '$totalSales sold',
                                style: textTheme.bodySmall?.copyWith(
                                    color: AppColors.textMuted, fontSize: 11),
                              ),
                            ],
                          ],
                        ),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: AppColors.hoverState,
                                borderRadius:
                                    BorderRadius.circular(AppShapes.radiusSm),
                              ),
                              child: Text(
                                category,
                                style: textTheme.bodySmall?.copyWith(
                                    fontSize: 10, color: AppColors.textMuted),
                              ),
                            ),
                            if (address.isNotEmpty) ...[
                              const SizedBox(width: AppSpacing.xs),
                              Flexible(
                                child: Text(
                                  address,
                                  style: textTheme.bodySmall?.copyWith(
                                      color: AppColors.textMuted, fontSize: 10),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            if (products.isNotEmpty)
              Container(
                padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
                decoration: BoxDecoration(
                  color: const Color(0xFFF5F5F5),
                  borderRadius: const BorderRadius.only(
                    bottomLeft: Radius.circular(AppShapes.radiusMd),
                    bottomRight: Radius.circular(AppShapes.radiusMd),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
                      child: Text(
                        l10n.translate('top_picks_from').replaceAll('{name}', name),
                        style: textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                          color: AppColors.textPrimary,
                          fontSize: 13,
                        ),
                      ),
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    SizedBox(
                      height: 135,
                      child: ListView.separated(
                        scrollDirection: Axis.horizontal,
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        itemCount: products.length,
                        separatorBuilder: (_, __) => const SizedBox(width: 6),
                        itemBuilder: (context, index) {
                          final product = products[index];
                          return GestureDetector(
                            onTap: () => onProductTap(product.id),
                            child: _MiniProductCard(product: product),
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────
// Mini product card (unchanged)
// ─────────────────────────────────────────────
class _MiniProductCard extends StatelessWidget {
  final Product product;
  const _MiniProductCard({required this.product});

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final discount = product.discountPercentage;
    final displayPrice = FormatUtils.price(product.effectivePrice ?? product.price);

    return Container(
      width: 85,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(AppShapes.radiusSm),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.06),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          ClipRRect(
            borderRadius: const BorderRadius.vertical(
              top: Radius.circular(AppShapes.radiusSm),
            ),
            child: AspectRatio(
              aspectRatio: 1.0,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  CachedNetworkImage(
                    imageUrl: product.imageUrl,
                    fit: BoxFit.cover,
                    placeholder: (_, __) => Shimmer.fromColors(
                      baseColor: Colors.grey.shade200,
                      highlightColor: Colors.grey.shade100,
                      child: Container(color: Colors.white),
                    ),
                    errorWidget: (_, __, ___) => Container(
                      color: Colors.grey.shade100,
                      child: Icon(Icons.image_not_supported_outlined,
                          color: Colors.grey.shade400, size: 18),
                    ),
                  ),
                  if (discount > 0)
                    Positioned(
                      top: 3,
                      left: 3,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                        decoration: BoxDecoration(
                          color: AppColors.error,
                          borderRadius: BorderRadius.circular(AppShapes.radiusFull),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.1),
                              blurRadius: 4,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: Text(
                          '-$discount%',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 7,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(3, 2, 3, 3),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  product.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: textTheme.bodySmall?.copyWith(
                    fontSize: 9,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 1),
                Text(
                  displayPrice,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: textTheme.bodyMedium?.copyWith(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 2),
                Row(
                  children: [
                    ...List.generate(5, (index) {
                      final filled = index < product.rating.round();
                      return Icon(
                        filled ? Icons.star_rounded : Icons.star_outline_rounded,
                        size: 8,
                        color: filled ? AppColors.starGold : AppColors.starGold.withOpacity(0.3),
                      );
                    }),
                    const SizedBox(width: 1),
                    Text(
                      '(${product.reviewsCount})',
                      style: textTheme.bodySmall?.copyWith(
                        fontSize: 8,
                        color: AppColors.textMuted,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.store_outlined, size: 40, color: AppColors.textMuted.withOpacity(0.4)),
            const SizedBox(height: 10),
            Text(
              AppLocalizations.of(context).translate('no_shops_found'),
              style: Theme.of(context).textTheme.bodyLarge?.copyWith(color: AppColors.textMuted),
            ),
          ],
        ),
      ),
    );
  }
}
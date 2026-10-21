// lib/screens/shop_detail_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:flutter_staggered_grid_view/flutter_staggered_grid_view.dart';
import 'package:shimmer/shimmer.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../api/client.dart';
import '../models/vendor.dart';
import '../models/product.dart';
import '../widgets/product_card.dart';
import '../widgets/package_card.dart';
import '../theme/app_theme.dart';
import 'product_detail_screen.dart';
import '../widgets/review_list_widget.dart';
import 'all_reviews_page.dart';

// ── Helpers ──
double _parseDouble(dynamic value) => double.tryParse(value?.toString() ?? '0') ?? 0.0;
int _parseInt(dynamic value) => int.tryParse(value?.toString() ?? '0') ?? 0;

// ── Filter state (unchanged) ──
class VendorFilterState {
  String search;
  String sort;
  String minPrice;
  String maxPrice;
  List<String> selectedCategories;
  List<int> selectedRatings;
  List<String> selectedDelivery;

  VendorFilterState({
    this.search = '',
    this.sort = '',
    this.minPrice = '',
    this.maxPrice = '',
    List<String>? selectedCategories,
    List<int>? selectedRatings,
    List<String>? selectedDelivery,
  })  : selectedCategories = selectedCategories ?? [],
        selectedRatings = selectedRatings ?? [],
        selectedDelivery = selectedDelivery ?? [];

  VendorFilterState copyWith({
    String? search,
    String? sort,
    String? minPrice,
    String? maxPrice,
    List<String>? selectedCategories,
    List<int>? selectedRatings,
    List<String>? selectedDelivery,
  }) {
    return VendorFilterState(
      search: search ?? this.search,
      sort: sort ?? this.sort,
      minPrice: minPrice ?? this.minPrice,
      maxPrice: maxPrice ?? this.maxPrice,
      selectedCategories: selectedCategories ?? List<String>.from(this.selectedCategories),
      selectedRatings: selectedRatings ?? List<int>.from(this.selectedRatings),
      selectedDelivery: selectedDelivery ?? List<String>.from(this.selectedDelivery),
    );
  }
}

// ── Global category map (unchanged) ──
Map<String, List<String>> categoryMap = {};

Future<void> buildCategoryMap(ApiClient api) async {
  try {
    final response = await api.get('/categories');
    final List categories = response.data is List ? response.data : (response.data['data'] ?? []);
    final Map<int, String> idToName = {};
    final Map<int, List<String>> parentToChildren = {};

    for (final c in categories) {
      idToName[c['id'] as int] = c['name'] as String;
    }
    for (final c in categories) {
      final parentId = c['parent_id'];
      if (parentId != null) {
        parentToChildren.putIfAbsent(parentId, () => []).add(c['name'] as String);
      }
    }

    categoryMap = {};
    final roots = categories.where((c) => c['parent_id'] == null);
    for (final root in roots) {
      final rootName = root['name'] as String;
      categoryMap[rootName] = [rootName];
      _addAllDescendants(root['id'], parentToChildren, idToName, rootName);
    }
  } catch (_) {
    categoryMap = {};
  }
}

void _addAllDescendants(int parentId, Map<int, List<String>> parentToChildren,
    Map<int, String> idToName, String rootName) {
  final children = parentToChildren[parentId] ?? [];
  for (final childName in children) {
    categoryMap[rootName]!.add(childName);
    final childId = idToName.keys.firstWhere((k) => idToName[k] == childName);
    _addAllDescendants(childId, parentToChildren, idToName, rootName);
  }
}

// ── Providers ──
final vendorProvider = FutureProvider.family<Map<String, dynamic>, int>((ref, id) async {
  final response = await ApiClient.instance.get('/api/v1/vendors/$id');
  return response.data as Map<String, dynamic>;
});

class ShopDetailScreen extends ConsumerStatefulWidget {
  final int shopId;
  const ShopDetailScreen({Key? key, required this.shopId}) : super(key: key);
  @override
  ConsumerState<ShopDetailScreen> createState() => _ShopDetailScreenState();
}

class _ShopDetailScreenState extends ConsumerState<ShopDetailScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final ScrollController _scrollController = ScrollController();

  // ★ Performance: only the report button rebuilds on scroll
  final ValueNotifier<double> _reportOpacity = ValueNotifier(1.0);
  int _reviewRefreshCounter = 0;

  VendorFilterState _productFilters = VendorFilterState();
  VendorFilterState _packageFilters = VendorFilterState();
  Map<String, dynamic> _filterMeta = {};

  List<Map<String, dynamic>> _allProducts = [];
  List<Map<String, dynamic>> _allPackages = [];

  final TextEditingController _minPriceController = TextEditingController();
  final TextEditingController _maxPriceController = TextEditingController();
  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 5, vsync: this);
    _scrollController.addListener(() {
      _reportOpacity.value =
          (1.0 - (_scrollController.offset / 120)).clamp(0.0, 1.0);
    });
    _fetchFilterMeta();
    _loadCategoryMap();
  }

  Future<void> _fetchFilterMeta() async {
    try {
      final response =
          await ApiClient.instance.get('/api/v1/vendors/${widget.shopId}/filter_options');
      final data = response.data as Map<String, dynamic>;
      if (mounted) setState(() => _filterMeta = data);
    } catch (_) {}
  }

  Future<void> _loadCategoryMap() async {
    await buildCategoryMap(ApiClient.instance);
  }

  void _extractFromVendor(Map<String, dynamic> vendorData) {
    _allProducts =
        (vendorData['products'] as List?)?.map((e) => Map<String, dynamic>.from(e)).toList() ?? [];
    _allPackages =
        (vendorData['packages'] as List?)?.map((e) => Map<String, dynamic>.from(e)).toList() ?? [];
  }

  // ── Filtering (unchanged) ──
  List<Map<String, dynamic>> _applyFilters(List<Map<String, dynamic>> list,
      {required bool isPackage}) {
    if (list.isEmpty) return [];
    final filters = isPackage ? _packageFilters : _productFilters;
    final search = filters.search.toLowerCase();
    final sort = filters.sort;

    var filtered = List<Map<String, dynamic>>.from(list);

    if (search.isNotEmpty) {
      filtered = filtered.where((p) {
        final title = (p['title'] ?? p['name'] ?? '').toString().toLowerCase();
        return title.contains(search);
      }).toList();
    }

    if (filters.selectedCategories.isNotEmpty) {
      final expanded = <String>{};
      for (final cat in filters.selectedCategories) {
        expanded.add(cat);
        if (categoryMap.containsKey(cat)) expanded.addAll(categoryMap[cat]!);
      }
      filtered = filtered.where((p) {
        final productCat =
            p['category'] is Map ? (p['category'] as Map)['name']?.toString() : null;
        final packageCats = (p['categories'] as List?)
                ?.map((c) => c is Map ? c['name'].toString() : c.toString())
                .toList() ??
            [];
        final allItemCats = <String>[];
        if (productCat != null) allItemCats.add(productCat);
        allItemCats.addAll(packageCats);
        return allItemCats.any((c) => expanded.contains(c));
      }).toList();
    }

    if (filters.selectedDelivery.isNotEmpty) {
      filtered = filtered.where((p) {
        return filters.selectedDelivery
            .contains(p['delivery_label']?.toString() ?? 'Paid Shipping');
      }).toList();
    }

    final minP = double.tryParse(filters.minPrice);
    final maxP = double.tryParse(filters.maxPrice);
    if (minP != null || maxP != null) {
      filtered = filtered.where((p) {
        final price = _parseDouble(p['effective_price'] ?? p['price']);
        return (minP == null || price >= minP) && (maxP == null || price <= maxP);
      }).toList();
    }

    if (filters.selectedRatings.isNotEmpty) {
      final minRating = filters.selectedRatings.reduce((a, b) => a < b ? a : b);
      filtered = filtered.where((p) => _parseDouble(p['rating']) >= minRating).toList();
    }

    switch (sort) {
      case 'price_asc':
        filtered.sort((a, b) =>
            _parseDouble(a['effective_price'] ?? a['price'])
                .compareTo(_parseDouble(b['effective_price'] ?? b['price'])));
        break;
      case 'price_desc':
        filtered.sort((a, b) =>
            _parseDouble(b['effective_price'] ?? b['price'])
                .compareTo(_parseDouble(a['effective_price'] ?? a['price'])));
        break;
      case 'rating':
        filtered.sort((a, b) => _parseDouble(b['rating']).compareTo(_parseDouble(a['rating'])));
        break;
      case 'newest':
        filtered.sort((a, b) => _parseInt(b['id']).compareTo(_parseInt(a['id'])));
        break;
    }
    return filtered;
  }

  // ── Filter panel with rectangular Apply button and restored setState ──
  void _openFilterPanel({required bool isPackage}) {
    final meta = isPackage ? (_filterMeta['packages'] ?? {}) : (_filterMeta['products'] ?? {});
    final vendorCategoriesRaw = (meta['categories'] as List<dynamic>?) ?? [];
    final ratings = (meta['ratings'] as List<dynamic>?) ?? [];
    final priceRange = meta['price_range'] as Map<String, dynamic>? ?? {};
    final deliveryOptions = (meta['delivery_options'] as List<dynamic>?) ?? [];
    final filters = isPackage ? _packageFilters : _productFilters;

    _minPriceController.text = filters.minPrice;
    _maxPriceController.text = filters.maxPrice;
    _searchController.text = filters.search;

    List<Map<String, dynamic>> enrichedCategories;
    if (vendorCategoriesRaw.isEmpty || categoryMap.isEmpty) {
      enrichedCategories = vendorCategoriesRaw.map((c) => Map<String, dynamic>.from(c)).toList();
    } else {
      final countByName = <String, int>{};
      for (final cat in vendorCategoriesRaw) {
        countByName[cat['name']] = (cat['count'] as num?)?.toInt() ?? 0;
      }
      for (final cat in vendorCategoriesRaw) {
        final name = cat['name'] as String;
        categoryMap.forEach((parent, children) {
          if (children.contains(name) && parent != name) {
            countByName[parent] =
                (countByName[parent] ?? 0) + ((cat['count'] as num?)?.toInt() ?? 0);
          }
        });
      }
      enrichedCategories = countByName.entries
          .map((e) => {'name': e.key, 'count': e.value})
          .toList();
    }

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        VendorFilterState local = filters.copyWith();

        return StatefulBuilder(
          builder: (context, setSheetState) {
            bool showPrice = true;
            bool showDelivery = true;
            bool showCategory = true;
            bool showRating = true;

            return Container(
              height: MediaQuery.of(context).size.height * 0.75,
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
              ),
              child: Column(
                children: [
                  // Handle + Header
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
                    child: Column(
                      children: [
                        Container(
                            width: 32,
                            height: 4,
                            decoration: BoxDecoration(
                                color: Colors.grey[350],
                                borderRadius: BorderRadius.circular(2))),
                        const SizedBox(height: 14),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(isPackage ? 'Package Filters' : 'Product Filters',
                                style: const TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.w700,
                                    color: Colors.black)),
                            TextButton(
                              onPressed: () {
                                setSheetState(() {
                                  local = VendorFilterState();
                                  _minPriceController.text = '';
                                  _maxPriceController.text = '';
                                  _searchController.text = '';
                                });
                                Navigator.pop(sheetContext);
                              },
                              child: const Text('Reset',
                                  style: TextStyle(color: Colors.black, fontSize: 13)),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 6),
                  Expanded(
                    child: ListView(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      children: [
                        // Pill‑shaped search bar
                        TextField(
                          controller: _searchController,
                          decoration: InputDecoration(
                            hintText: 'Search...',
                            hintStyle: TextStyle(color: Colors.grey[500], fontSize: 13),
                            prefixIcon: const Icon(Icons.search, size: 18, color: Colors.grey),
                            filled: true,
                            fillColor: Colors.grey[100],
                            contentPadding:
                                const EdgeInsets.symmetric(vertical: 8, horizontal: 14),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(24),
                              borderSide: BorderSide.none,
                            ),
                          ),
                          style: const TextStyle(fontSize: 13),
                          onChanged: (v) =>
                              setSheetState(() => local = local.copyWith(search: v)),
                        ),
                        const SizedBox(height: 10),

                        // Sort
                        DropdownButtonFormField<String>(
                          value: local.sort.isEmpty ? null : local.sort,
                          decoration: InputDecoration(
                            labelText: 'Sort By',
                            labelStyle: TextStyle(fontSize: 13, color: Colors.black),
                            contentPadding:
                                const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                            border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(10),
                                borderSide: BorderSide(color: Colors.grey[300]!)),
                            isDense: true,
                          ),
                          style: const TextStyle(fontSize: 13, color: Colors.black),
                          items: const [
                            DropdownMenuItem(value: '', child: Text('Default')),
                            DropdownMenuItem(value: 'price_asc', child: Text('Price: Low to High')),
                            DropdownMenuItem(value: 'price_desc', child: Text('Price: High to Low')),
                            DropdownMenuItem(value: 'rating', child: Text('Highest Rated')),
                            DropdownMenuItem(value: 'newest', child: Text('Newest')),
                          ],
                          onChanged: (v) =>
                              setSheetState(() => local = local.copyWith(sort: v ?? '')),
                        ),
                        const SizedBox(height: 10),

                        // Price Range
                        _CompactSectionHeader(title: 'Price Range (ETB)', open: showPrice, onTap: () => setSheetState(() => showPrice = !showPrice)),
                        if (showPrice) ...[
                          const SizedBox(height: 6),
                          Row(
                            children: [
                              Expanded(
                                child: TextField(
                                  controller: _minPriceController,
                                  keyboardType: TextInputType.number,
                                  style: const TextStyle(fontSize: 13),
                                  decoration: InputDecoration(
                                    hintText: 'Min (${priceRange['min'] ?? 0})',
                                    hintStyle: TextStyle(fontSize: 12, color: Colors.grey[500]),
                                    contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                                    border: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(10),
                                        borderSide: BorderSide(color: Colors.grey[300]!)),
                                    isDense: true,
                                  ),
                                  onChanged: (v) =>
                                      setSheetState(() => local = local.copyWith(minPrice: v)),
                                ),
                              ),
                              const SizedBox(width: 8),
                              const Text('–', style: TextStyle(fontSize: 14)),
                              const SizedBox(width: 8),
                              Expanded(
                                child: TextField(
                                  controller: _maxPriceController,
                                  keyboardType: TextInputType.number,
                                  style: const TextStyle(fontSize: 13),
                                  decoration: InputDecoration(
                                    hintText: 'Max (${priceRange['max'] ?? 0})',
                                    hintStyle: TextStyle(fontSize: 12, color: Colors.grey[500]),
                                    contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                                    border: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(10),
                                        borderSide: BorderSide(color: Colors.grey[300]!)),
                                    isDense: true,
                                  ),
                                  onChanged: (v) =>
                                      setSheetState(() => local = local.copyWith(maxPrice: v)),
                                ),
                              ),
                            ],
                          ),
                        ],
                        const SizedBox(height: 10),

                        // Delivery
                        if (deliveryOptions.isNotEmpty) ...[
                          _CompactSectionHeader(title: 'Delivery', open: showDelivery, onTap: () => setSheetState(() => showDelivery = !showDelivery)),
                          if (showDelivery) ...[
                            const SizedBox(height: 4),
                            ...deliveryOptions.map<Widget>((opt) {
                              final label = opt['label'] ?? '';
                              final count = opt['count'] ?? 0;
                              return _RoundCheckboxTile(
                                label: '$label ($count)',
                                value: local.selectedDelivery.contains(label),
                                onChanged: (v) {
                                  setSheetState(() {
                                    final newList = List<String>.from(local.selectedDelivery);
                                    if (v == true) newList.add(label);
                                    else newList.remove(label);
                                    local = local.copyWith(selectedDelivery: newList);
                                  });
                                },
                              );
                            }),
                          ],
                          const SizedBox(height: 10),
                        ],

                        // Categories
                        if (enrichedCategories.isNotEmpty) ...[
                          _CompactSectionHeader(title: 'Category', open: showCategory, onTap: () => setSheetState(() => showCategory = !showCategory)),
                          if (showCategory) ...[
                            const SizedBox(height: 4),
                            ...enrichedCategories.map<Widget>((cat) {
                              final name = cat['name'] ?? '';
                              final count = cat['count'] ?? 0;
                              return _RoundCheckboxTile(
                                label: '$name ($count)',
                                value: local.selectedCategories.contains(name),
                                onChanged: (v) {
                                  setSheetState(() {
                                    final newList = List<String>.from(local.selectedCategories);
                                    if (v == true) newList.add(name);
                                    else newList.remove(name);
                                    local = local.copyWith(selectedCategories: newList);
                                  });
                                },
                              );
                            }),
                          ],
                          const SizedBox(height: 10),
                        ],

                        // Ratings
                        if (ratings.isNotEmpty) ...[
                          _CompactSectionHeader(title: 'Rating', open: showRating, onTap: () => setSheetState(() => showRating = !showRating)),
                          if (showRating) ...[
                            const SizedBox(height: 4),
                            ...ratings.map<Widget>((r) {
                              final star = r['star'] ?? 0;
                              final count = r['count'] ?? 0;
                              return _RoundCheckboxTile(
                                labelWidget: Row(
                                  children: [
                                    ...List.generate(star,
                                        (index) => const Icon(Icons.star, size: 16, color: Colors.amber)),
                                    const SizedBox(width: 4),
                                    Text('& up ($count)',
                                        style: const TextStyle(fontSize: 13, color: Colors.black)),
                                  ],
                                ),
                                value: local.selectedRatings.contains(star),
                                onChanged: (v) {
                                  setSheetState(() {
                                    final newList = List<int>.from(local.selectedRatings);
                                    if (v == true) newList.add(star);
                                    else newList.remove(star);
                                    local = local.copyWith(selectedRatings: newList);
                                  });
                                },
                              );
                            }),
                          ],
                        ],
                        const SizedBox(height: 16),
                      ],
                    ),
                  ),
                  // ★ Rectangular Apply button – calls setState to rebuild the product list
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                    decoration: const BoxDecoration(
                      color: Colors.white,
                      border: Border(top: BorderSide(color: Color(0xFFEEEEEE), width: 1)),
                    ),
                    child: ElevatedButton(
                      onPressed: () {
                        setState(() {  // ★ This rebuilds the whole page, applying the filters
                          if (isPackage) _packageFilters = local;
                          else _productFilters = local;
                        });
                        Navigator.pop(sheetContext);
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFF97519),
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.zero,
                        ),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                      child: const Text('Apply Filters',
                          style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
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

  @override
  void dispose() {
    _scrollController.removeListener(() {});
    _scrollController.dispose();
    _tabController.dispose();
    _reportOpacity.dispose();
    _minPriceController.dispose();
    _maxPriceController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final vendorAsync = ref.watch(vendorProvider(widget.shopId));
    return Scaffold(
      backgroundColor: AppColors.pageBackground,
      body: vendorAsync.when(
        data: (vendorData) {
          _extractFromVendor(vendorData);
          final vendor = Vendor.fromJson(vendorData);
          final isBulk = vendorData['is_bulk_supplier'] == true;
          final isCompany = vendorData['is_company'] == true;
          final totalSales = _parseInt(vendorData['total_sales']);
          final productsCount = _parseInt(vendorData['products_count']);
          final badge = vendorData['badge'] as String?;

          return NestedScrollView(
            controller: _scrollController,
            headerSliverBuilder: (context, innerBoxIsScrolled) => [
              SliverAppBar(
                expandedHeight: 100,
                toolbarHeight: 44,
                pinned: false,
                automaticallyImplyLeading: false,
                backgroundColor: AppColors.pageBackground,
                elevation: 0,
                leading: Padding(
                  padding: const EdgeInsets.only(left: AppSpacing.xs, top: AppSpacing.xs),
                  child: Material(
                    color: Colors.transparent,
                    child: InkWell(
                      onTap: () => Navigator.pop(context),
                      borderRadius: BorderRadius.circular(20),
                      child: Container(
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(
                            color: Colors.black.withOpacity(0.2), shape: BoxShape.circle),
                        child: const Icon(Icons.arrow_back, color: Colors.white, size: 20),
                      ),
                    ),
                  ),
                ),
                actions: [
                  // ★ Report button – fades independently (no full‑screen rebuild)
                  ValueListenableBuilder<double>(
                    valueListenable: _reportOpacity,
                    builder: (context, opacity, _) => Opacity(
                      opacity: opacity,
                      child: Padding(
                        padding: const EdgeInsets.only(top: AppSpacing.xs),
                        child: Material(
                          color: Colors.transparent,
                          child: InkWell(
                            onTap: () {},
                            borderRadius: BorderRadius.circular(20),
                            child: Container(
                              width: 36,
                              height: 36,
                              margin: const EdgeInsets.only(right: 4),
                              decoration: BoxDecoration(
                                  color: Colors.black.withOpacity(0.2), shape: BoxShape.circle),
                              child: Icon(PhosphorIcons.flag(PhosphorIconsStyle.regular),
                                  size: 18, color: Colors.white),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.only(top: AppSpacing.xs),
                    child: Material(
                      color: Colors.transparent,
                      child: InkWell(
                        onTap: () {},
                        borderRadius: BorderRadius.circular(20),
                        child: Container(
                          width: 36,
                          height: 36,
                          margin: const EdgeInsets.only(right: AppSpacing.xs),
                          decoration: BoxDecoration(
                              color: Colors.black.withOpacity(0.2), shape: BoxShape.circle),
                          child: Icon(PhosphorIcons.shareNetwork(PhosphorIconsStyle.regular),
                              size: 18, color: Colors.white),
                        ),
                      ),
                    ),
                  ),
                ],
                flexibleSpace: FlexibleSpaceBar(
                  background: CachedNetworkImage(
                    imageUrl: vendor.banner ?? vendor.logo ?? '',
                    fit: BoxFit.cover,
                    memCacheWidth: 800,
                    errorWidget: (_, __, ___) => Container(
                      color: const Color(0xFFD6D6D6),
                      child: Center(child: Icon(Icons.store, size: 48, color: AppColors.textMuted)),
                    ),
                  ),
                ),
              ),
              SliverPersistentHeader(
                pinned: true,
                delegate: _BottomAlignedProfileHeaderDelegate(
                  vendor: vendor,
                  topSafe: MediaQuery.of(context).padding.top,
                  isCompany: isCompany,
                  totalSales: totalSales,
                  productsCount: productsCount,
                  badge: badge,
                ),
              ),
              if (isBulk)
                SliverToBoxAdapter(
                  child: Container(
                    margin: const EdgeInsets.fromLTRB(AppSpacing.sm, AppSpacing.sm, AppSpacing.sm, 0),
                    padding: const EdgeInsets.all(AppSpacing.md),
                    decoration: BoxDecoration(
                        color: Colors.orange.shade50,
                        borderRadius: BorderRadius.circular(AppShapes.radiusMd),
                        border: Border.all(color: Colors.orange.shade200)),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Row(children: [
                        Icon(Icons.business, color: Colors.orange.shade700, size: 20),
                        const SizedBox(width: 8),
                        Text('Bulk Supplier',
                            style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w700,
                                color: Colors.orange.shade800)),
                      ]),
                      const SizedBox(height: 12),
                      Row(children: [
                        Icon(Icons.business_outlined, color: Colors.orange.shade700, size: 18),
                        const SizedBox(width: 8),
                        Expanded(
                            child: Text(vendor.businessName,
                                style: const TextStyle(fontWeight: FontWeight.w500))),
                      ]),
                      const SizedBox(height: 8),
                      Row(children: [
                        Icon(Icons.location_on_outlined, color: Colors.orange.shade700, size: 18),
                        const SizedBox(width: 8),
                        Expanded(
                            child: Text(vendor.businessAddress ?? 'Ethiopia',
                                style: const TextStyle(fontWeight: FontWeight.w500))),
                      ]),
                      const SizedBox(height: 8),
                      Row(children: [
                        Icon(Icons.phone_outlined, color: Colors.orange.shade700, size: 18),
                        const SizedBox(width: 8),
                        Expanded(
                            child: Text(vendorData['phone']?.toString() ?? 'Not provided',
                                style: const TextStyle(fontWeight: FontWeight.w500))),
                      ]),
                    ]),
                  ),
                ),
              // ★ Flush tab bar – no white card, just tabs on product‑list background
              SliverPersistentHeader(
                pinned: true,
                delegate: _FlushTabBarDelegate(
                  tabController: _tabController,
                  onFilterTap: () => _openFilterPanel(isPackage: _tabController.index == 1),
                ),
              ),
            ],
            body: TabBarView(
              controller: _tabController,
              children: [
                _buildProductsTab(),
                _buildPackagesTab(),
                _buildDiscountsTab(),
                _buildReviewsTab(vendor),
                _buildAboutTab(vendor),
              ],
            ),
          );
        },
        loading: () =>
            const Center(child: CircularProgressIndicator(color: AppColors.primary)),
        error: (_, __) => const Center(child: Text('Shop not found')),
      ),
    );
  }

  Widget _buildCoverImage(Vendor vendor) {
    final coverUrl = vendor.banner ?? vendor.logo;
    if (coverUrl != null && coverUrl.isNotEmpty)
      return CachedNetworkImage(imageUrl: coverUrl, fit: BoxFit.cover, memCacheWidth: 800);
    return Container(
        color: const Color(0xFFD6D6D6),
        child: Center(child: Icon(Icons.store, size: 48, color: AppColors.textMuted)));
  }

  // ── Original product tabs (filtered in build) ──
  Widget _buildProductsTab() {
    final filtered = _applyFilters(_allProducts, isPackage: false);
    return filtered.isEmpty
        ? const Center(child: Text('No products found'))
        : Container(
            color: AppColors.productListBackground,
            child: CustomScrollView(
              slivers: [
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(AppSpacing.xs, 0, AppSpacing.xs, 4),
                  sliver: SliverToBoxAdapter(
                    child: MasonryGridView.count(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      crossAxisCount: 2,
                      mainAxisSpacing: 4,
                      crossAxisSpacing: 4,
                      itemCount: filtered.length,
                      itemBuilder: (ctx, i) {
                        final product = Product.fromJson(filtered[i]);
                        return RepaintBoundary(
                          child: GestureDetector(
                            onTap: () => Navigator.push(
                                context,
                                MaterialPageRoute(
                                    builder: (_) => ProductDetailScreen(productId: product.id))),
                            child: ProductCard(
                              product: product,
                              isDeal: false,
                              hideMembershipBadge: true,
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ),
                const SliverFillRemaining(hasScrollBody: false, child: SizedBox.shrink()),
              ],
            ),
          );
  }

  Widget _buildPackagesTab() {
    final filtered = _applyFilters(_allPackages, isPackage: true);
    return filtered.isEmpty
        ? const Center(child: Text('No packages available'))
        : Container(
            color: AppColors.productListBackground,
            child: CustomScrollView(
              slivers: [
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(AppSpacing.xs, 0, AppSpacing.xs, 4),
                  sliver: SliverToBoxAdapter(
                    child: MasonryGridView.count(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      crossAxisCount: 2,
                      mainAxisSpacing: 4,
                      crossAxisSpacing: 4,
                      itemCount: filtered.length,
                      itemBuilder: (ctx, i) {
                        final package = Product.fromJson(filtered[i]);
                        return RepaintBoundary(child: PackageCard(product: package));
                      },
                    ),
                  ),
                ),
                const SliverFillRemaining(hasScrollBody: false, child: SizedBox.shrink()),
              ],
            ),
          );
  }

  Widget _buildDiscountsTab() {
    final discounted = _applyFilters(
        _allProducts.where((p) => (p['discount'] ?? 0) > 0).toList(), isPackage: false);
    return discounted.isEmpty
        ? const Center(child: Text('No discounted products'))
        : Container(
            color: AppColors.productListBackground,
            child: CustomScrollView(
              slivers: [
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(AppSpacing.xs, 0, AppSpacing.xs, 4),
                  sliver: SliverToBoxAdapter(
                    child: MasonryGridView.count(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      crossAxisCount: 2,
                      mainAxisSpacing: 4,
                      crossAxisSpacing: 4,
                      itemCount: discounted.length,
                      itemBuilder: (ctx, i) {
                        final product = Product.fromJson(discounted[i]);
                        return RepaintBoundary(
                          child: GestureDetector(
                            onTap: () => Navigator.push(
                                context,
                                MaterialPageRoute(
                                    builder: (_) => ProductDetailScreen(productId: product.id))),
                            child: ProductCard(
                              product: product,
                              isDeal: true,
                              hideMembershipBadge: true,
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ),
                const SliverFillRemaining(hasScrollBody: false, child: SizedBox.shrink()),
              ],
            ),
          );
  }

  Widget _buildReviewsTab(Vendor vendor) {
    return Container(
      color: AppColors.productListBackground,
      child: CustomScrollView(
        slivers: [
          SliverPadding(
            padding: const EdgeInsets.all(AppSpacing.md),
            sliver: SliverToBoxAdapter(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Shop Reviews',
                    style: Theme.of(context)
                        .textTheme
                        .titleMedium
                        ?.copyWith(fontWeight: FontWeight.w600)),
                const SizedBox(height: 12),
                ReviewListWidget(
                    key: ValueKey('vendor_reviews_$_reviewRefreshCounter'),
                    vendorId: vendor.id),
                const SizedBox(height: 12),
                Center(
                    child: TextButton(
                        onPressed: () => Navigator.push(
                            context,
                            MaterialPageRoute(
                                builder: (_) => AllReviewsPage(vendorId: widget.shopId))),
                        child: const Text('See all reviews'))),
              ]),
            ),
          ),
          SliverFillRemaining(
              hasScrollBody: false, child: Container(color: AppColors.productListBackground)),
        ],
      ),
    );
  }

  Widget _buildAboutTab(Vendor vendor) {
    final textTheme = Theme.of(context).textTheme;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(
          padding: const EdgeInsets.all(AppSpacing.md),
          decoration: BoxDecoration(
              color: AppColors.cardBackground,
              borderRadius: BorderRadius.circular(AppShapes.radiusMd),
              boxShadow: [
                BoxShadow(
                    color: Colors.black.withOpacity(0.04),
                    blurRadius: 8,
                    offset: const Offset(0, 2))
              ]),
          child: Row(children: [
            Icon(Icons.location_on_outlined, color: AppColors.primary, size: 22),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Location',
                  style: textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w600)),
              const SizedBox(height: 4),
              Text(vendor.businessAddress ?? 'Address not available',
                  style: textTheme.bodySmall?.copyWith(color: AppColors.textMuted)),
            ])),
          ]),
        ),
        const SizedBox(height: AppSpacing.md),
        if (vendor.description != null && vendor.description!.isNotEmpty)
          Container(
            padding: const EdgeInsets.all(AppSpacing.md),
            decoration: BoxDecoration(
                color: AppColors.cardBackground,
                borderRadius: BorderRadius.circular(AppShapes.radiusMd),
                boxShadow: [
                  BoxShadow(
                      color: Colors.black.withOpacity(0.04),
                      blurRadius: 8,
                      offset: const Offset(0, 2))
                ]),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('About',
                  style: textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w600)),
              const SizedBox(height: AppSpacing.xs),
              Text(vendor.description!,
                  style: textTheme.bodySmall?.copyWith(color: AppColors.textMuted, height: 1.4)),
            ]),
          ),
      ]),
    );
  }
}

// ─── Profile Header (bottom‑aligned, no gap) ───
class _BottomAlignedProfileHeaderDelegate extends SliverPersistentHeaderDelegate {
  final Vendor vendor;
  final double topSafe;
  final bool isCompany;
  final int totalSales, productsCount;
  final String? badge;

  const _BottomAlignedProfileHeaderDelegate({
    required this.vendor,
    required this.topSafe,
    this.isCompany = false,
    this.totalSales = 0,
    this.productsCount = 0,
    this.badge,
  });

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlapsContent) {
    final textTheme = Theme.of(context).textTheme;
    return Container(
      color: AppColors.pageBackground,
      padding: EdgeInsets.only(left: AppSpacing.md, right: AppSpacing.md, top: topSafe),
      height: maxExtent,
      child: Align(
        alignment: Alignment.bottomCenter,
        child: Padding(
          padding: const EdgeInsets.only(bottom: 4),
          child: Row(children: [
            Container(
              width: 50,
              height: 50,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: Colors.grey.shade200, width: 2.5),
                boxShadow: [
                  BoxShadow(
                      color: Colors.black.withOpacity(0.1),
                      blurRadius: 8,
                      offset: const Offset(0, 3))
                ],
                image: (vendor.logo != null && vendor.logo!.isNotEmpty)
                    ? DecorationImage(image: NetworkImage(vendor.logo!), fit: BoxFit.cover)
                    : null,
              ),
              child: (vendor.logo == null || vendor.logo!.isEmpty)
                  ? const Icon(Icons.store, color: AppColors.textMuted, size: 26)
                  : null,
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    Flexible(
                        child: Text(vendor.businessName,
                            style: textTheme.headlineMedium?.copyWith(
                                fontSize: 17, fontWeight: FontWeight.w800, letterSpacing: -0.3),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis)),
                    if (badge != null && badge!.isNotEmpty) ...[
                      const SizedBox(width: 6),
                      RepaintBoundary(child: _buildShimmerMembershipBadge(badge!)),
                    ],
                    if (isCompany) ...[
                      const SizedBox(width: 6),
                      _buildCompanyBadge(),
                    ],
                  ]),
                  const SizedBox(height: 4),
                  Row(children: [
                    const Icon(Icons.star, size: 16, color: AppColors.starGold),
                    const SizedBox(width: 4),
                    Text(vendor.rating.toStringAsFixed(1),
                        style: textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w600)),
                    const SizedBox(width: 4),
                    Text('(${vendor.reviewsCount} reviews)',
                        style: textTheme.bodyMedium?.copyWith(
                            color: AppColors.textMuted, fontWeight: FontWeight.w500)),
                    if (totalSales > 0) ...[
                      const SizedBox(width: 8),
                      Text('$totalSales sales',
                          style: textTheme.bodyMedium?.copyWith(
                              color: AppColors.textPrimary, fontWeight: FontWeight.w500)),
                    ],
                    if (productsCount > 0) ...[
                      const SizedBox(width: 8),
                      Text('$productsCount products',
                          style: textTheme.bodyMedium?.copyWith(
                              color: AppColors.textPrimary, fontWeight: FontWeight.w500)),
                    ],
                  ]),
                ],
              ),
            ),
          ]),
        ),
      ),
    );
  }

  Widget _buildShimmerMembershipBadge(String badgeText) {
    final lower = badgeText.toLowerCase();
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
          Text(glyph, style: TextStyle(fontSize: 14, color: baseColor)),
          const SizedBox(width: 3),
          Flexible(
            child: Text(
              badgeText,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 13, color: baseColor, fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }

  static Widget _buildCompanyBadge() => Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
            color: Colors.blue.shade100, borderRadius: BorderRadius.circular(4)),
        child: const Text('COMPANY',
            style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: Colors.blue)),
      );

  @override
  double get maxExtent => 54 + topSafe;
  @override
  double get minExtent => 54 + topSafe;
  @override
  bool shouldRebuild(covariant _BottomAlignedProfileHeaderDelegate old) =>
      vendor != old.vendor ||
      isCompany != old.isCompany ||
      totalSales != old.totalSales ||
      productsCount != old.productsCount ||
      badge != old.badge;
}

// ─── Flush tab bar – no white card, just tabs on the product‑list background ───
class _FlushTabBarDelegate extends SliverPersistentHeaderDelegate {
  final TabController tabController;
  final VoidCallback? onFilterTap;
  const _FlushTabBarDelegate({required this.tabController, this.onFilterTap});

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlapsContent) {
    return Container(
      color: AppColors.productListBackground,
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xxs),
      child: Row(
        children: [
          Expanded(
            child: TabBar(
              controller: tabController,
              isScrollable: true,
              tabAlignment: TabAlignment.start,
              labelPadding: const EdgeInsets.symmetric(horizontal: 16),
              indicator: UnderlineTabIndicator(
                borderSide: const BorderSide(color: AppColors.primary, width: 2.5),
                insets: const EdgeInsets.symmetric(horizontal: 8),
              ),
              indicatorSize: TabBarIndicatorSize.label,
              splashFactory: NoSplash.splashFactory,
              overlayColor: const WidgetStatePropertyAll(Colors.transparent),
              dividerColor: Colors.transparent,
              labelColor: AppColors.primary,
              unselectedLabelColor: AppColors.textMuted,
              labelStyle: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600, letterSpacing: 0.2),
              unselectedLabelStyle: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w500),
              tabs: const [
                Tab(text: 'Products'),
                Tab(text: 'Packages'),
                Tab(text: 'Discounts'),
                Tab(text: 'Reviews'),
                Tab(text: 'About'),
              ],
            ),
          ),
          if (onFilterTap != null)
            Padding(
              padding: const EdgeInsets.only(right: 6),
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: onFilterTap,
                  borderRadius: BorderRadius.circular(10),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: AppColors.primary.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: AppColors.primary.withOpacity(0.3)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.filter_list, size: 16, color: AppColors.primary),
                        const SizedBox(width: 4),
                        Text('Filters',
                            style: TextStyle(
                              color: AppColors.primary,
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            )),
                      ],
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  @override double get maxExtent => 50;
  @override double get minExtent => 50;
  @override bool shouldRebuild(covariant _FlushTabBarDelegate old) =>
      tabController != old.tabController || onFilterTap != old.onFilterTap;
}

// ─── Compact section header ──
class _CompactSectionHeader extends StatelessWidget {
  final String title;
  final bool open;
  final VoidCallback onTap;
  const _CompactSectionHeader({required this.title, required this.open, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          children: [
            Icon(open ? Icons.keyboard_arrow_down : Icons.chevron_right,
                size: 18, color: Colors.black54),
            const SizedBox(width: 6),
            Text(title,
                style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600, color: Colors.black)),
          ],
        ),
      ),
    );
  }
}

// ─── Round checkbox tile ──
class _RoundCheckboxTile extends StatelessWidget {
  final String? label;
  final Widget? labelWidget;
  final bool value;
  final ValueChanged<bool> onChanged;

  const _RoundCheckboxTile({
    Key? key,
    this.label,
    this.labelWidget,
    required this.value,
    required this.onChanged,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => onChanged(!value),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(
          children: [
            SizedBox(
              width: 24,
              height: 24,
              child: Checkbox(
                value: value,
                onChanged: (v) => onChanged(v ?? false),
                shape: const CircleBorder(),
                activeColor: AppColors.primary,
                side: BorderSide(color: Colors.grey[400]!),
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: labelWidget ??
                  Text(label ?? '',
                      style: const TextStyle(fontSize: 13, color: Colors.black)),
            ),
          ],
        ),
      ),
    );
  }
}
// lib/screens/company_profile_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:shimmer/shimmer.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter_map/flutter_map.dart';   // ★ OpenStreetMap
import 'package:latlong2/latlong.dart';          // ★ Coordinate types
import '../api/client.dart';
import '../models/product.dart';
import '../models/vendor.dart';
import '../widgets/product_card.dart';

// ── Helpers ──
double safeDouble(dynamic value) => double.tryParse('$value') ?? 0.0;
int safeInt(dynamic value) => int.tryParse('$value') ?? 0;

String formatPrice(double amount) {
  final parts = amount.toStringAsFixed(2).split('.');
  final integer = parts[0].replaceAllMapped(
    RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'),
    (Match m) => '${m[1]},',
  );
  return 'ETB $integer.${parts[1]}';
}

String variantNameFromAttributes(Map? attrs) {
  if (attrs == null || attrs.isEmpty) return 'Variant';
  return attrs.entries.map((e) => '${e.value}').join(' / ');
}

// ── Global category map (parent → ALL descendants) ──
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

// ── Filter state (identical to ShopDetailScreen) ──
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

final companyProvider = FutureProvider.family<Map<String, dynamic>, String>(
  (ref, id) async {
    final response = await ApiClient.instance.get('/api/v1/vendors/$id');
    return response.data as Map<String, dynamic>;
  },
);

class CompanyProfileScreen extends ConsumerStatefulWidget {
  final String companyId;
  const CompanyProfileScreen({Key? key, required this.companyId}) : super(key: key);

  @override
  ConsumerState<CompanyProfileScreen> createState() => _CompanyProfileScreenState();
}

class _CompanyProfileScreenState extends ConsumerState<CompanyProfileScreen> {
  bool _needsRefresh = true;

  VendorFilterState _productFilters = VendorFilterState();
  VendorFilterState _packageFilters = VendorFilterState();
  Map<String, dynamic> _filterMeta = {};

  final TextEditingController _minPriceController = TextEditingController();
  final TextEditingController _maxPriceController = TextEditingController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_needsRefresh) {
        ref.invalidate(companyProvider(widget.companyId));
        _needsRefresh = false;
      }
    });
    _fetchFilterMeta();
    _loadCategoryMap();
  }

  Future<void> _fetchFilterMeta() async {
    try {
      final response = await ApiClient.instance.get('/api/v1/vendors/${widget.companyId}/filter_options');
      final data = response.data as Map<String, dynamic>;
      if (mounted) setState(() => _filterMeta = data);
    } catch (_) {}
  }

  Future<void> _loadCategoryMap() async {
    await buildCategoryMap(ApiClient.instance);
  }

  // ── Client‑side filtering (matches web logic) ──
  List<Map<String, dynamic>> _applyFilters(List<Map<String, dynamic>> list, {required bool isPackage}) {
    if (list.isEmpty) return [];
    final filters = isPackage ? _packageFilters : _productFilters;
    final search = filters.search.toLowerCase();
    final sort = filters.sort;
    final selectedRatings = filters.selectedRatings;
    final selectedDelivery = filters.selectedDelivery;
    final selectedCategories = filters.selectedCategories;

    var filtered = List<Map<String, dynamic>>.from(list);

    // Search
    if (search.isNotEmpty) {
      filtered = filtered.where((p) {
        final title = (p['title'] ?? p['name'] ?? '').toString().toLowerCase();
        return title.contains(search);
      }).toList();
    }

    // Categories – parent expands to all descendants
    if (selectedCategories.isNotEmpty) {
      final expanded = <String>{};
      for (final cat in selectedCategories) {
        expanded.add(cat);
        if (categoryMap.containsKey(cat)) {
          expanded.addAll(categoryMap[cat]!);
        }
      }
      filtered = filtered.where((p) {
        final productCat = p['category'] is Map ? (p['category'] as Map)['name']?.toString() : null;
        final packageCats = (p['categories'] as List?)
            ?.map((c) => c is Map ? c['name'].toString() : c.toString())
            .toList() ?? [];
        final allItemCats = <String>[];
        if (productCat != null) allItemCats.add(productCat);
        allItemCats.addAll(packageCats);
        return allItemCats.any((c) => expanded.contains(c));
      }).toList();
    }

    // Delivery
    if (selectedDelivery.isNotEmpty) {
      filtered = filtered.where((p) {
        final label = p['delivery_label']?.toString() ?? 'Paid Shipping';
        return selectedDelivery.contains(label);
      }).toList();
    }

    // Price range
    final minP = double.tryParse(filters.minPrice);
    final maxP = double.tryParse(filters.maxPrice);
    if (minP != null || maxP != null) {
      filtered = filtered.where((p) {
        final price = double.tryParse((p['effective_price'] ?? p['price'] ?? '0').toString()) ?? 0;
        return (minP == null || price >= minP) && (maxP == null || price <= maxP);
      }).toList();
    }

    // Ratings
    if (selectedRatings.isNotEmpty) {
      final minRating = selectedRatings.reduce((a, b) => a < b ? a : b);
      filtered = filtered.where((p) {
        final rating = double.tryParse((p['rating'] ?? '0').toString()) ?? 0;
        return rating >= minRating;
      }).toList();
    }

    // Sort
    switch (sort) {
      case 'price_asc':
        filtered.sort((a, b) => (double.tryParse((a['effective_price'] ?? a['price'] ?? '0').toString()) ?? 0)
            .compareTo(double.tryParse((b['effective_price'] ?? b['price'] ?? '0').toString()) ?? 0));
        break;
      case 'price_desc':
        filtered.sort((a, b) => (double.tryParse((b['effective_price'] ?? b['price'] ?? '0').toString()) ?? 0)
            .compareTo(double.tryParse((a['effective_price'] ?? a['price'] ?? '0').toString()) ?? 0));
        break;
      case 'rating':
        filtered.sort((a, b) => (b['rating'] ?? 0).compareTo(a['rating'] ?? 0));
        break;
      case 'newest':
        filtered.sort((a, b) => (b['id'] ?? 0).compareTo(a['id'] ?? 0));
        break;
    }
    return filtered;
  }

  // ── Filter panel with Delivery and enriched categories ──
  void _openFilterPanel({required bool isPackage}) {
    final meta = isPackage ? (_filterMeta['packages'] ?? {}) : (_filterMeta['products'] ?? {});
    final vendorCategoriesRaw = (meta['categories'] as List<dynamic>?) ?? [];
    final ratings = (meta['ratings'] as List<dynamic>?) ?? [];
    final priceRange = meta['price_range'] as Map<String, dynamic>? ?? {};
    final deliveryOptions = (meta['delivery_options'] as List<dynamic>?) ?? [];
    final filters = isPackage ? _packageFilters : _productFilters;

    // Sync controllers
    _minPriceController.text = filters.minPrice;
    _maxPriceController.text = filters.maxPrice;

    // Enrich categories with parent counts
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
            countByName[parent] = (countByName[parent] ?? 0) + ((cat['count'] as num?)?.toInt() ?? 0);
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
            return Container(
              height: MediaQuery.of(context).size.height * 0.8,
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
              ),
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
                    child: Column(
                      children: [
                        Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.grey[300], borderRadius: BorderRadius.circular(2))),
                        const SizedBox(height: 16),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(isPackage ? 'Package Filters' : 'Product Filters',
                                style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: Colors.black)),
                            Row(
                              children: [
                                TextButton(
                                  onPressed: () {
                                    setSheetState(() {
                                      local = VendorFilterState();
                                      _minPriceController.text = '';
                                      _maxPriceController.text = '';
                                    });
                                    Navigator.pop(sheetContext);
                                  },
                                  child: const Text('Reset', style: TextStyle(color: Colors.black)),
                                ),
                                const SizedBox(width: 8),
                                ElevatedButton(
                                  onPressed: () {
                                    setState(() {
                                      if (isPackage) _packageFilters = local;
                                      else _productFilters = local;
                                    });
                                    Navigator.pop(sheetContext);
                                  },
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: const Color(0xFFF97519),
                                    foregroundColor: Colors.white,
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                  ),
                                  child: const Text('Apply'),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                  Expanded(
                    child: ListView(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      children: [
                        // Search
                        TextField(
                          decoration: InputDecoration(
                            labelText: 'Search', hintText: 'Name...', prefixIcon: const Icon(Icons.search, size: 20),
                            contentPadding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: Colors.grey[300]!)),
                          ),
                          controller: TextEditingController(text: local.search),
                          onChanged: (v) => setSheetState(() => local = local.copyWith(search: v)),
                        ),
                        const SizedBox(height: 12),
                        // Sort
                        DropdownButtonFormField<String>(
                          value: local.sort.isEmpty ? null : local.sort,
                          decoration: InputDecoration(labelText: 'Sort By', contentPadding: const EdgeInsets.symmetric(horizontal: 12), border: OutlineInputBorder(borderRadius: BorderRadius.circular(12))),
                          items: const [
                            DropdownMenuItem(value: '', child: Text('Default')),
                            DropdownMenuItem(value: 'price_asc', child: Text('Price: Low to High')),
                            DropdownMenuItem(value: 'price_desc', child: Text('Price: High to Low')),
                            DropdownMenuItem(value: 'rating', child: Text('Highest Rated')),
                            DropdownMenuItem(value: 'newest', child: Text('Newest')),
                          ],
                          onChanged: (v) => setSheetState(() => local = local.copyWith(sort: v ?? '')),
                        ),
                        const SizedBox(height: 12),
                        // Price Range
                        const _SectionTitle(title: 'Price Range (ETB)'),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Expanded(
                              child: TextField(
                                controller: _minPriceController,
                                keyboardType: TextInputType.number,
                                decoration: InputDecoration(
                                  hintText: 'Min (${priceRange['min'] ?? 0})',
                                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                                ),
                                onChanged: (v) => setSheetState(() => local = local.copyWith(minPrice: v)),
                              ),
                            ),
                            const SizedBox(width: 12),
                            const Text('–'),
                            const SizedBox(width: 12),
                            Expanded(
                              child: TextField(
                                controller: _maxPriceController,
                                keyboardType: TextInputType.number,
                                decoration: InputDecoration(
                                  hintText: 'Max (${priceRange['max'] ?? 0})',
                                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                                ),
                                onChanged: (v) => setSheetState(() => local = local.copyWith(maxPrice: v)),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        // Delivery Options
                        if (deliveryOptions.isNotEmpty) ...[
                          const _SectionTitle(title: 'Delivery'),
                          const SizedBox(height: 8),
                          ...deliveryOptions.map<Widget>((opt) {
                            final label = opt['label'] ?? '';
                            final count = opt['count'] ?? 0;
                            return CheckboxListTile(
                              contentPadding: EdgeInsets.zero,
                              controlAffinity: ListTileControlAffinity.leading,
                              dense: true,
                              title: Text('$label ($count)', style: const TextStyle(fontSize: 14, color: Colors.black)),
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
                        // Enriched Categories
                        if (enrichedCategories.isNotEmpty) ...[
                          const _SectionTitle(title: 'Category'),
                          const SizedBox(height: 8),
                          ...enrichedCategories.map<Widget>((cat) {
                            final name = cat['name'] ?? '';
                            final count = cat['count'] ?? 0;
                            return CheckboxListTile(
                              contentPadding: EdgeInsets.zero,
                              controlAffinity: ListTileControlAffinity.leading,
                              dense: true,
                              title: Text('$name ($count)', style: const TextStyle(fontSize: 14, color: Colors.black)),
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
                        // Ratings
                        if (ratings.isNotEmpty) ...[
                          const _SectionTitle(title: 'Rating'),
                          const SizedBox(height: 8),
                          ...ratings.map<Widget>((r) {
                            final star = r['star'] ?? 0;
                            final count = r['count'] ?? 0;
                            return CheckboxListTile(
                              contentPadding: EdgeInsets.zero,
                              controlAffinity: ListTileControlAffinity.leading,
                              dense: true,
                              title: Row(
                                children: [
                                  ...List.generate(star, (index) => const Icon(Icons.star, size: 18, color: Colors.amber)),
                                  const SizedBox(width: 4),
                                  Text('& up ($count)', style: const TextStyle(fontSize: 14, color: Colors.black)),
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
                        const SizedBox(height: 20),
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

  @override
  void dispose() {
    _minPriceController.dispose();
    _maxPriceController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final companyAsync = ref.watch(companyProvider(widget.companyId));

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      body: companyAsync.when(
        data: (vendorData) => _EnterpriseTabbedView(
          vendorData: vendorData,
          productFilters: _productFilters,
          packageFilters: _packageFilters,
          filterMeta: _filterMeta,
          onOpenFilter: _openFilterPanel,
          applyFilters: _applyFilters,
        ),
        loading: () => const _LoadingShimmer(),
        error: (_, __) => const Center(
          child: Text('Company not found',
              style: TextStyle(color: Colors.black, fontSize: 18)),
        ),
      ),
    );
  }
}

// ── _EnterpriseTabbedView ──
class _EnterpriseTabbedView extends StatefulWidget {
  final Map<String, dynamic> vendorData;
  final VendorFilterState productFilters;
  final VendorFilterState packageFilters;
  final Map<String, dynamic> filterMeta;
  final void Function({required bool isPackage}) onOpenFilter;
  final List<Map<String, dynamic>> Function(List<Map<String, dynamic>> list, {required bool isPackage}) applyFilters;

  const _EnterpriseTabbedView({
    required this.vendorData,
    required this.productFilters,
    required this.packageFilters,
    required this.filterMeta,
    required this.onOpenFilter,
    required this.applyFilters,
  });

  @override
  State<_EnterpriseTabbedView> createState() => _EnterpriseTabbedViewState();
}

class _EnterpriseTabbedViewState extends State<_EnterpriseTabbedView>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 5, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final vendorData = widget.vendorData;
    final vendor = Vendor.fromJson(vendorData);
    final phone = vendorData['phone']?.toString();
    final address = vendor.businessAddress ?? '';
    final rating = safeDouble(vendor.rating);
    final productsCount = safeInt(vendorData['products_count']);
    final totalSales = safeInt(vendorData['total_sales']);
    final reviewsCount = safeInt(vendorData['reviews_count']);
    final lat = vendorData['latitude'] != null ? safeDouble(vendorData['latitude']) : null;
    final lng = vendorData['longitude'] != null ? safeDouble(vendorData['longitude']) : null;

    final isVerified = vendorData['is_verified'] == true;
    final badge = vendorData['badge'] as String?;
    final bannerUrl = vendorData['banner_url'] as String?;
    final isClosed = vendor.acceptingOrders == false;
    final isBulkSupplier = vendorData['is_bulk_supplier'] == true;
    final isCompany = vendorData['is_company'] == true;

    final productsRaw = (vendorData['products'] as List<dynamic>?)
            ?.map((p) => Map<String, dynamic>.from(p))
            .toList() ??
        [];
    final discountsRaw = (vendorData['discounts'] as List<dynamic>?)
            ?.map((p) => Map<String, dynamic>.from(p))
            .toList() ??
        [];
    final packagesRaw = (vendorData['packages'] as List<dynamic>?)
            ?.map((pkg) => Map<String, dynamic>.from(pkg))
            .toList() ??
        [];

    final filteredProducts = widget.applyFilters(productsRaw, isPackage: false);
    final filteredDeals = widget.applyFilters(discountsRaw, isPackage: false);
    final filteredPackages = widget.applyFilters(packagesRaw, isPackage: true);

    final products = filteredProducts.map((m) => Product.fromJson(m)).toList();
    final deals = filteredDeals.map((m) => Product.fromJson(m)).toList();

    final categories = (vendorData['categories'] as List<dynamic>?)
            ?.map((c) => Map<String, dynamic>.from(c))
            .toList() ??
        [];
    final returnPolicy = vendorData['return_policy'] as String?;
    final shippingPolicy = vendorData['shipping_policy'] as String?;
    final paymentPolicy = vendorData['payment_policy'] as String?;
    final fullAddress = vendorData['full_address'] ?? address;

    return NestedScrollView(
      headerSliverBuilder: (context, innerBoxIsScrolled) => [
        _EnterpriseAppBar(phone: phone),
        SliverToBoxAdapter(
          child: _EnterpriseHero(
            bannerUrl: bannerUrl,
            logoUrl: vendorData['logo_url'],
            name: vendor.businessName,
            description: vendor.description,
            rating: rating,
            reviewsCount: reviewsCount,
            productsCount: productsCount,
            totalSales: totalSales,
            address: address,
            isVerified: isVerified,
            badge: badge,
            isClosed: isClosed,
            isBulkSupplier: isBulkSupplier,
            isCompany: isCompany,
          ),
        ),
        SliverToBoxAdapter(
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.08),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: _StatsRow(
              rating: rating,
              reviewsCount: reviewsCount,
              productsCount: productsCount,
              totalSales: totalSales,
            ),
          ),
        ),
        SliverPersistentHeader(
          pinned: true,
          delegate: _TabBarDelegate(
            Row(
              children: [
                Expanded(
                  child: TabBar(
                    controller: _tabController,
                    isScrollable: true,
                    tabAlignment: TabAlignment.start,
                    overlayColor: WidgetStateProperty.all(Colors.transparent),
                    splashFactory: NoSplash.splashFactory,
                    indicator: UnderlineTabIndicator(
                      borderSide: BorderSide(
                          color: const Color(0xFFF97519).withOpacity(0.7),
                          width: 2.5),
                      insets: const EdgeInsets.symmetric(horizontal: 12),
                    ),
                    indicatorWeight: 2.5,
                    labelColor: const Color(0xFFF97519),
                    unselectedLabelColor: Colors.black,
                    dividerColor: Colors.transparent,
                    labelStyle: const TextStyle(
                        fontWeight: FontWeight.w600, fontSize: 14),
                    tabs: const [
                      Tab(text: '🛍️ Products'),
                      Tab(text: '🔥 Deals'),
                      Tab(text: '📦 Packages'),
                      Tab(text: '📋 About'),
                      Tab(text: '⭐ Reviews'),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.filter_list),
                  onPressed: () => widget.onOpenFilter(
                      isPackage: _tabController.index == 2),
                  tooltip: 'Filters',
                ),
              ],
            ),
          ),
        ),
      ],
      body: TabBarView(
        controller: _tabController,
        children: [
          // Products tab
          products.isEmpty
              ? const Center(child: Text('No products yet', style: TextStyle(color: Colors.black)))
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
                  itemCount: products.length,
                  itemBuilder: (context, index) {
                    final product = products[index];
                    if (index % 2 == 0) {
                      return GestureDetector(
                        onTap: () => Navigator.of(context).pushNamed('/product', arguments: product.id),
                        child: _MagazineProductCard(product: product),
                      );
                    } else {
                      return GestureDetector(
                        onTap: () => Navigator.of(context).pushNamed('/product', arguments: product.id),
                        child: _RowProductCard(product: product),
                      );
                    }
                  },
                ),

          // Deals tab
          deals.isEmpty
              ? const Center(child: Text('No deals at the moment', style: TextStyle(color: Colors.black)))
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
                  itemCount: deals.length,
                  itemBuilder: (context, index) {
                    final product = deals[index];
                    return GestureDetector(
                      onTap: () => Navigator.of(context).pushNamed('/product', arguments: product.id),
                      child: ProductCard(product: product, isDeal: true),
                    );
                  },
                ),

          // Packages tab
          filteredPackages.isEmpty
              ? const Center(child: Text('No packages created', style: TextStyle(color: Colors.black)))
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
                  itemCount: filteredPackages.length,
                  itemBuilder: (context, index) {
                    final pkg = filteredPackages[index];
                    if (index % 2 == 0) {
                      return _MagazinePackageCard(package: pkg);
                    } else {
                      return _RowPackageCard(package: pkg);
                    }
                  },
                ),

          // About tab
          SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: _StoreDetailsCard(
              description: vendorData['long_description'] ?? vendor.description,
              fullAddress: fullAddress,
              phone: phone,
              categories: categories,
              isAcceptingOrders: !isClosed,
              returnPolicy: returnPolicy,
              shippingPolicy: shippingPolicy,
              paymentPolicy: paymentPolicy,
              lat: lat,
              lng: lng,
            ),
          ),

          // Reviews tab
          _StableReviewsTab(vendorId: vendor.id ?? 0),
        ],
      ),
    );
  }
}

// ── Tab Bar delegate ──
class _TabBarDelegate extends SliverPersistentHeaderDelegate {
  final Widget child;
  _TabBarDelegate(this.child);

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlapsContent) =>
      Container(color: Colors.white, child: child);

  @override
  double get maxExtent => 48;
  @override
  double get minExtent => 48;
  @override
  bool shouldRebuild(covariant _TabBarDelegate oldDelegate) => false;
}

// ── Section Title ──
class _SectionTitle extends StatelessWidget {
  final String title;
  const _SectionTitle({required this.title});
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 8),
    child: Text(title, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: Colors.black)),
  );
}

// ── Enterprise App Bar ──
class _EnterpriseAppBar extends StatelessWidget {
  final String? phone;
  const _EnterpriseAppBar({this.phone});

  @override
  Widget build(BuildContext context) {
    return SliverAppBar(
      backgroundColor: Colors.transparent,
      elevation: 0,
      pinned: true,
      flexibleSpace: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
              colors: [Color(0xFFFF7A00), Color(0xFFD84315)],
              begin: Alignment.centerLeft,
              end: Alignment.centerRight),
        ),
      ),
      leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded, color: Colors.white),
          onPressed: () => Navigator.of(context).pop()),
      title: const Text('Company',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 17)),
      actions: [
        if (phone != null)
          IconButton(
              icon: const Icon(Icons.phone_outlined, color: Colors.white),
              onPressed: () => launchUrl(Uri.parse('tel:$phone'))),
      ],
    );
  }
}

// ── Enterprise Hero (with shimmer badge) ──
class _EnterpriseHero extends StatelessWidget {
  final String? bannerUrl, logoUrl, name, description, address;
  final double rating;
  final int reviewsCount, productsCount, totalSales;
  final bool isVerified, isClosed, isBulkSupplier, isCompany;
  final String? badge;

  const _EnterpriseHero({
    this.bannerUrl, this.logoUrl, required this.name, this.description,
    required this.rating, required this.reviewsCount, required this.productsCount,
    required this.totalSales, required this.address, required this.isVerified,
    this.badge, required this.isClosed, required this.isBulkSupplier, required this.isCompany,
  });

  Widget _buildShimmerMembershipBadge(String badgeText) {
    final lower = badgeText.toLowerCase();
    String glyph; Color baseColor;
    if (lower.contains('platinum')) { glyph = '💎'; baseColor = Colors.blue.shade700; }
    else if (lower.contains('gold')) { glyph = '🏆'; baseColor = const Color(0xFFF59E0B); }
    else if (lower.contains('silver')) { glyph = '🥈'; baseColor = const Color(0xFF9CA3AF); }
    else { glyph = '✨'; baseColor = const Color(0xFF6B7280); }

    final highlightColor = Color.lerp(baseColor, Colors.white, 0.4)!;
    return Shimmer.fromColors(
      baseColor: baseColor, highlightColor: highlightColor,
      period: const Duration(milliseconds: 1500),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Text(glyph, style: TextStyle(fontSize: 14, color: baseColor)),
        const SizedBox(width: 3),
        Flexible(child: Text(badgeText, overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 13, color: baseColor, fontWeight: FontWeight.w700))),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      if (bannerUrl != null && bannerUrl!.isNotEmpty)
        SizedBox(height: 200, width: double.infinity, child: Stack(fit: StackFit.expand, children: [
          CachedNetworkImage(imageUrl: bannerUrl!, fit: BoxFit.cover),
          Container(decoration: BoxDecoration(gradient: LinearGradient(
            begin: Alignment.topCenter, end: Alignment.bottomCenter,
            colors: [Colors.black.withOpacity(0.1), Colors.black.withOpacity(0.4)],
          ))),
        ])),
      Container(
        color: Colors.white, padding: const EdgeInsets.fromLTRB(16, 16, 16, 20),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Container(width: 56, height: 56, decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              image: logoUrl != null && logoUrl!.isNotEmpty
                  ? DecorationImage(image: CachedNetworkImageProvider(logoUrl!), fit: BoxFit.cover)
                  : null,
              color: logoUrl == null || logoUrl!.isEmpty ? Colors.black : null,
            ),
            child: logoUrl == null || logoUrl!.isEmpty
                ? Center(child: Text(name!.isNotEmpty ? name![0].toUpperCase() : '?',
                    style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.white)))
                : null),
            const SizedBox(width: 16),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(name!, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.black)),
              const SizedBox(height: 4),
              Row(children: [
                Icon(Icons.star, size: 16, color: Colors.amber.shade700),
                const SizedBox(width: 4),
                Text(rating.toStringAsFixed(1), style: const TextStyle(color: Colors.black, fontWeight: FontWeight.w500)),
                const SizedBox(width: 4),
                Text('($reviewsCount reviews)', style: const TextStyle(color: Colors.black, fontSize: 13)),
              ]),
              const SizedBox(height: 4),
              if (address!.isNotEmpty) Row(children: [
                const Icon(Icons.location_on, size: 14, color: Colors.black),
                const SizedBox(width: 4),
                Flexible(child: Text(address!, style: const TextStyle(color: Colors.black, fontSize: 13))),
              ]),
            ])),
          ]),
          const SizedBox(height: 12),
          Wrap(spacing: 12, runSpacing: 6, children: [
            if (isVerified) _PlainBadge(icon: Icons.verified_user, label: 'Verified', color: Colors.green),
            if (badge != null) RepaintBoundary(child: _buildShimmerMembershipBadge(badge!)),
            if (isBulkSupplier) _PlainBadge(icon: Icons.inventory_2, label: 'Bulk Supplier', color: Colors.black),
            if (isCompany) _PlainBadge(icon: Icons.business, label: 'Enterprise', color: Colors.black),
            if (isClosed) _PlainBadge(icon: Icons.cancel, label: 'Closed', color: Colors.red),
          ]),
          if (description != null && description!.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(description!, style: const TextStyle(color: Colors.black, fontSize: 14, height: 1.4)),
          ],
        ]),
      ),
    ]);
  }
}

// ── Plain Badge ──
class _PlainBadge extends StatelessWidget {
  final IconData icon; final String label; final Color color;
  const _PlainBadge({required this.icon, required this.label, required this.color});
  @override
  Widget build(BuildContext context) => Row(mainAxisSize: MainAxisSize.min, children: [
    Icon(icon, size: 16, color: color),
    const SizedBox(width: 4),
    Text(label, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: color)),
  ]);
}

// ── Stats Row ──
class _StatsRow extends StatelessWidget {
  final double rating; final int reviewsCount, productsCount, totalSales;
  const _StatsRow({required this.rating, required this.reviewsCount, required this.productsCount, required this.totalSales});
  @override
  Widget build(BuildContext context) => Container(
    color: Colors.white, padding: const EdgeInsets.symmetric(vertical: 16),
    child: Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
      _StatColumn(label: 'Rating', value: rating.toStringAsFixed(1)),
      _StatColumn(label: 'Reviews', value: reviewsCount.toString()),
      _StatColumn(label: 'Products', value: productsCount.toString()),
      _StatColumn(label: 'Sales', value: totalSales.toString()),
    ]),
  );
}

class _StatColumn extends StatelessWidget {
  final String label, value;
  const _StatColumn({required this.label, required this.value});
  @override
  Widget build(BuildContext context) => Column(children: [
    Text(value, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.black)),
    Text(label, style: const TextStyle(fontSize: 13, color: Colors.black)),
  ]);
}

// ── Store Details Card (now with functional OpenStreetMap) ──
class _StoreDetailsCard extends StatelessWidget {
  final String? description, fullAddress, phone;
  final bool isAcceptingOrders;
  final List<Map<String, dynamic>> categories;
  final String? returnPolicy, shippingPolicy, paymentPolicy;
  final double? lat, lng;

  const _StoreDetailsCard({
    this.description, this.fullAddress, this.phone,
    required this.categories, required this.isAcceptingOrders,
    this.returnPolicy, this.shippingPolicy, this.paymentPolicy,
    this.lat, this.lng,
  });

  @override
  Widget build(BuildContext context) {
    final address = fullAddress ?? '';
    final localLat = lat;
    final localLng = lng;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white, borderRadius: BorderRadius.circular(12),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 8, offset: const Offset(0, 2))],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        if (description != null && description!.isNotEmpty) ...[
          const Text('About', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.black)),
          const SizedBox(height: 8),
          Text(description!, style: const TextStyle(color: Colors.black, height: 1.5, fontSize: 14)),
          const Divider(height: 24),
        ],
        if (address.isNotEmpty) _DetailRow(icon: Icons.location_on_outlined, text: address),
        if (phone != null && phone!.isNotEmpty) _DetailRow(icon: Icons.phone_outlined, text: phone!),
        const SizedBox(height: 8),
        Row(children: [
          const Icon(Icons.circle, size: 8, color: Colors.green),
          const SizedBox(width: 8),
          Text(isAcceptingOrders ? 'Accepting orders' : 'Not accepting orders',
              style: const TextStyle(color: Colors.black, fontSize: 14)),
        ]),
        const SizedBox(height: 12),
        if (categories.isNotEmpty) ...[
          const Text('Categories', style: TextStyle(fontWeight: FontWeight.w600, color: Colors.black)),
          const SizedBox(height: 8),
          Wrap(spacing: 8, runSpacing: 6, children: categories.map((c) => Chip(
            label: Text(c['name'] ?? '', style: const TextStyle(fontSize: 12)),
            backgroundColor: Colors.grey.shade100,
            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
          )).toList()),
          const SizedBox(height: 12),
        ],
        // ★ Functional OpenStreetMap
        if (localLat != null && localLng != null) ...[
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: SizedBox(
              height: 200,
              child: FlutterMap(
                options: MapOptions(
                  initialCenter: LatLng(localLat, localLng),
                  initialZoom: 15.0,
                  interactionOptions: const InteractionOptions(
                    flags: InteractiveFlag.all,
                  ),
                ),
                children: [
                  TileLayer(
                    urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                    userAgentPackageName: 'com.et_marketplace.app',
                  ),
                  MarkerLayer(
                    markers: [
                      Marker(
                        point: LatLng(localLat, localLng),
                        width: 80,
                        height: 80,
                        child: const Icon(Icons.location_on, color: Colors.red, size: 40),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
        const SizedBox(height: 16),
        const Text('Policies', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.black)),
        const SizedBox(height: 8),
        if (returnPolicy != null && returnPolicy!.isNotEmpty) _PolicyText(label: 'Returns', value: returnPolicy!),
        if (shippingPolicy != null && shippingPolicy!.isNotEmpty) _PolicyText(label: 'Shipping', value: shippingPolicy!),
        if (paymentPolicy != null && paymentPolicy!.isNotEmpty) _PolicyText(label: 'Payment', value: paymentPolicy!),
        if (returnPolicy == null && shippingPolicy == null && paymentPolicy == null)
          const Text('No policies specified.', style: TextStyle(color: Colors.black)),
      ]),
    );
  }
}

class _DetailRow extends StatelessWidget {
  final IconData icon; final String text;
  const _DetailRow({required this.icon, required this.text});
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Row(children: [
      Icon(icon, size: 18, color: Colors.black),
      const SizedBox(width: 8),
      Expanded(child: Text(text, style: const TextStyle(color: Colors.black, fontSize: 14))),
    ]),
  );
}

class _PolicyText extends StatelessWidget {
  final String label, value;
  const _PolicyText({required this.label, required this.value});
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 4),
    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('$label: ', style: const TextStyle(fontWeight: FontWeight.w600, color: Colors.black)),
      Expanded(child: Text(value, style: const TextStyle(color: Colors.black))),
    ]),
  );
}

// ── Reviews Tab ──
class _StableReviewsTab extends StatefulWidget {
  final int vendorId;
  const _StableReviewsTab({required this.vendorId});
  @override
  _StableReviewsTabState createState() => _StableReviewsTabState();
}

class _StableReviewsTabState extends State<_StableReviewsTab> {
  List<Map<String, dynamic>>? _reviews; bool _isLoading = true;

  @override
  void initState() { super.initState(); _loadReviews(); }
  Future<void> _loadReviews() async {
    try {
      final response = await ApiClient.instance.get('/api/v1/reviews?vendor_id=${widget.vendorId}');
      final data = response.data as Map<String, dynamic>;
      final list = (data['reviews'] as List<dynamic>?)?.map((e) => Map<String, dynamic>.from(e)).toList() ?? [];
      if (mounted) setState(() { _reviews = list; _isLoading = false; });
    } catch (_) { if (mounted) setState(() => _isLoading = false); }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) return const Center(child: CircularProgressIndicator());
    if (_reviews == null || _reviews!.isEmpty) return const Center(child: Text('No reviews yet.', style: TextStyle(color: Colors.black)));
    return RefreshIndicator(
      onRefresh: _loadReviews,
      child: ListView.builder(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
        itemCount: _reviews!.length,
        itemBuilder: (context, index) => _ReviewCard(review: _reviews![index]),
      ),
    );
  }
}

class _ReviewCard extends StatelessWidget {
  final Map<String, dynamic> review;
  const _ReviewCard({required this.review});
  @override
  Widget build(BuildContext context) {
    final userName = review['user']?['name'] ?? 'Anonymous';
    final rating = safeDouble(review['rating']);
    final comment = review['comment'] ?? '';
    final date = review['created_at'] ?? '';
    return Container(
      margin: const EdgeInsets.only(bottom: 8), padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(8),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 4, offset: const Offset(0, 2))]),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          CircleAvatar(radius: 14, backgroundColor: Colors.black, child: Text(userName.isNotEmpty ? userName[0].toUpperCase() : '?', style: const TextStyle(color: Colors.white))),
          const SizedBox(width: 8),
          Expanded(child: Text(userName, style: const TextStyle(fontWeight: FontWeight.w500, color: Colors.black))),
          if (date.isNotEmpty) Text(date, style: const TextStyle(fontSize: 12, color: Colors.black)),
        ]),
        const SizedBox(height: 6),
        Row(children: List.generate(5, (i) => Icon(i < rating.floor() ? Icons.star : Icons.star_border, size: 16, color: Colors.amber))),
        if (comment.isNotEmpty) ...[
          const SizedBox(height: 6),
          Text(comment, style: const TextStyle(color: Colors.black, fontSize: 13, height: 1.4)),
        ],
      ]),
    );
  }
}

// ── Loading Shimmer ──
class _LoadingShimmer extends StatelessWidget {
  const _LoadingShimmer();
  @override
  Widget build(BuildContext context) => Shimmer.fromColors(
    baseColor: Colors.grey[300]!, highlightColor: Colors.grey[200]!,
    child: Column(children: [
      Container(height: 200, color: Colors.white), const SizedBox(height: 12),
      Container(height: 24, width: 150, color: Colors.white), const SizedBox(height: 8),
      Container(height: 14, width: 250, color: Colors.white), const SizedBox(height: 20),
      Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: List.generate(4, (_) => Container(width: 60, height: 20, color: Colors.white))),
      const SizedBox(height: 30),
      Expanded(child: GridView.count(crossAxisCount: 2, padding: const EdgeInsets.all(16), children: List.generate(6, (_) => Container(margin: const EdgeInsets.all(8), color: Colors.white)))),
    ]),
  );
}

// ── Magazine / Row product & package cards ──
class _MagazineProductCard extends StatelessWidget {
  final Product product;
  const _MagazineProductCard({required this.product});

  @override
  Widget build(BuildContext context) {
    final price = safeDouble(product.effectivePrice);
    final imageUrl = product.images.isNotEmpty ? product.images.first : null;
    final desc = product.description?.isNotEmpty == true ? product.description! : '';
    final specs = product.specifications;
    final variants = product.variants;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white, borderRadius: BorderRadius.circular(16),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.06), blurRadius: 12, offset: const Offset(0, 4))],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        ClipRRect(
          borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
          child: imageUrl != null
              ? CachedNetworkImage(imageUrl: imageUrl, width: double.infinity, height: 200, fit: BoxFit.cover, memCacheWidth: 400)
              : Container(height: 200, color: Colors.black, child: const Center(child: Icon(Icons.image_outlined, size: 40, color: Colors.white))),
        ),
        Padding(
          padding: const EdgeInsets.all(16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(product.title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.black)),
            if (desc.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(desc, maxLines: 3, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 14, color: Colors.black, height: 1.4)),
            ],
            if (specs.isNotEmpty) ...[
              const SizedBox(height: 12),
              const Text('Specifications', style: TextStyle(fontWeight: FontWeight.w600, color: Colors.black, fontSize: 15)),
              const SizedBox(height: 6),
              ...specs.entries.map((e) => Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Row(children: [
                  Text('${e.key}: ', style: const TextStyle(fontWeight: FontWeight.w500, color: Colors.black, fontSize: 13)),
                  Expanded(child: Text(e.value, style: const TextStyle(color: Colors.black, fontSize: 13))),
                ]),
              )),
            ],
            if (variants.isNotEmpty) ...[
              const SizedBox(height: 12),
              const Text('Variants', style: TextStyle(fontWeight: FontWeight.w600, color: Colors.black, fontSize: 15)),
              const SizedBox(height: 8),
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: variants.map((v) {
                final name = variantNameFromAttributes(v['attributes'] as Map?);
                final varPrice = safeDouble(v['price']);
                return Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Row(children: [
                    Text('$name: ', style: const TextStyle(fontWeight: FontWeight.w500, color: Colors.black, fontSize: 13)),
                    Text(formatPrice(varPrice), style: const TextStyle(color: Colors.black, fontSize: 13)),
                  ]),
                );
              }).toList()),
            ],
            const SizedBox(height: 12),
            Row(children: [
              Icon(Icons.star, size: 16, color: Colors.amber.shade700),
              const SizedBox(width: 4),
              Text(product.rating.toStringAsFixed(1), style: const TextStyle(fontSize: 14, color: Colors.black)),
              const SizedBox(width: 4),
              Text('(${product.reviewsCount})', style: const TextStyle(fontSize: 13, color: Colors.black)),
              if (product.soldCount > 0) ...[
                const SizedBox(width: 12),
                Text('${product.soldCount} sold', style: const TextStyle(fontSize: 13, color: Colors.black)),
              ],
              const Spacer(),
              Text(formatPrice(price), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: Color(0xFFF97519))),
            ]),
            if (product.freeShipping == true) ...[
              const SizedBox(height: 4),
              Row(children: const [
                Icon(Icons.local_shipping, size: 14, color: Colors.green),
                SizedBox(width: 4),
                Text('Free Shipping', style: TextStyle(color: Colors.green, fontSize: 13)),
              ]),
            ],
          ]),
        ),
      ]),
    );
  }
}

class _RowProductCard extends StatelessWidget {
  final Product product;
  const _RowProductCard({required this.product});

  @override
  Widget build(BuildContext context) {
    final price = safeDouble(product.effectivePrice);
    final imageUrl = product.images.isNotEmpty ? product.images.first : null;
    final desc = product.description?.isNotEmpty == true ? product.description! : '';

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white, borderRadius: BorderRadius.circular(12),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 8, offset: const Offset(0, 2))],
      ),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        ClipRRect(
          borderRadius: const BorderRadius.horizontal(left: Radius.circular(12)),
          child: imageUrl != null
              ? CachedNetworkImage(imageUrl: imageUrl, width: 120, height: 120, fit: BoxFit.cover, memCacheWidth: 240)
              : Container(width: 120, height: 120, color: Colors.black, child: const Icon(Icons.image_outlined, size: 28, color: Colors.white)),
        ),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(product.title, maxLines: 2, overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15, color: Colors.black)),
              if (desc.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(desc, maxLines: 2, overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 13, color: Colors.black, height: 1.3)),
              ],
              const SizedBox(height: 8),
              Row(children: [
                Icon(Icons.star, size: 14, color: Colors.amber.shade700),
                const SizedBox(width: 4),
                Text(product.rating.toStringAsFixed(1), style: const TextStyle(fontSize: 13, color: Colors.black)),
                const SizedBox(width: 4),
                Text('(${product.reviewsCount})', style: const TextStyle(fontSize: 12, color: Colors.black)),
                if (product.soldCount > 0) ...[
                  const SizedBox(width: 8),
                  Text('${product.soldCount} sold', style: const TextStyle(fontSize: 12, color: Colors.black)),
                ],
                const Spacer(),
                Text(formatPrice(price), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Color(0xFFF97519))),
              ]),
              if (product.freeShipping == true) ...[
                const SizedBox(height: 4),
                Row(children: const [
                  Icon(Icons.local_shipping, size: 12, color: Colors.green),
                  SizedBox(width: 4),
                  Text('Free Shipping', style: TextStyle(color: Colors.green, fontSize: 12)),
                ]),
              ],
            ]),
          ),
        ),
      ]),
    );
  }
}

class _MagazinePackageCard extends StatelessWidget {
  final Map<String, dynamic> package;
  const _MagazinePackageCard({required this.package});

  @override
  Widget build(BuildContext context) {
    final name = package['name'] ?? 'Package';
    final price = safeDouble(package['price']);
    final imageUrl = (package['image_urls'] as List?)?.firstOrNull ?? '';
    final itemsCount = safeInt(package['items_count']);
    final original = safeDouble(package['original_price']);
    final desc = package['description'] ?? '';

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white, borderRadius: BorderRadius.circular(16),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.06), blurRadius: 12, offset: const Offset(0, 4))],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        ClipRRect(
          borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
          child: imageUrl.isNotEmpty
              ? CachedNetworkImage(imageUrl: imageUrl, width: double.infinity, height: 200, fit: BoxFit.cover, memCacheWidth: 400)
              : Container(height: 200, color: Colors.black, child: const Center(child: Icon(Icons.inventory_2, size: 40, color: Colors.white))),
        ),
        Padding(
          padding: const EdgeInsets.all(16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(name, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.black)),
            if (desc.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(desc, maxLines: 3, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 14, color: Colors.black, height: 1.4)),
            ],
            const SizedBox(height: 8),
            Text('$itemsCount items', style: const TextStyle(fontSize: 14, color: Colors.black)),
            const SizedBox(height: 12),
            Row(children: [
              Text(formatPrice(price), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: Color(0xFFF97519))),
              if (original > price) ...[
                const SizedBox(width: 8),
                Text(formatPrice(original), style: const TextStyle(fontSize: 14, color: Colors.black, decoration: TextDecoration.lineThrough)),
              ],
            ]),
          ]),
        ),
      ]),
    );
  }
}

class _RowPackageCard extends StatelessWidget {
  final Map<String, dynamic> package;
  const _RowPackageCard({required this.package});

  @override
  Widget build(BuildContext context) {
    final name = package['name'] ?? 'Package';
    final price = safeDouble(package['price']);
    final imageUrl = (package['image_urls'] as List?)?.firstOrNull ?? '';
    final itemsCount = safeInt(package['items_count']);
    final original = safeDouble(package['original_price']);
    final desc = package['description'] ?? '';

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white, borderRadius: BorderRadius.circular(12),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 8, offset: const Offset(0, 2))],
      ),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        ClipRRect(
          borderRadius: const BorderRadius.horizontal(left: Radius.circular(12)),
          child: imageUrl.isNotEmpty
              ? CachedNetworkImage(imageUrl: imageUrl, width: 120, height: 120, fit: BoxFit.cover, memCacheWidth: 240)
              : Container(width: 120, height: 120, color: Colors.black, child: const Icon(Icons.inventory_2, size: 28, color: Colors.white)),
        ),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(name, maxLines: 2, overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15, color: Colors.black)),
              if (desc.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(desc, maxLines: 2, overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 13, color: Colors.black, height: 1.3)),
              ],
              const SizedBox(height: 8),
              Text('$itemsCount items', style: const TextStyle(fontSize: 13, color: Colors.black)),
              const SizedBox(height: 8),
              Row(children: [
                Text(formatPrice(price), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Color(0xFFF97519))),
                if (original > price) ...[
                  const SizedBox(width: 8),
                  Text(formatPrice(original), style: const TextStyle(fontSize: 13, color: Colors.black, decoration: TextDecoration.lineThrough)),
                ],
              ]),
            ]),
          ),
        ),
      ]),
    );
  }
}
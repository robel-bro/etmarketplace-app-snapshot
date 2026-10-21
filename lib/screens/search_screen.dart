// lib/screens/search_screen.dart
import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../api/client.dart';
import '../api/filter_options_service.dart';
import '../models/product.dart';
import '../models/filter_params.dart';
import '../theme/app_theme.dart';
import '../utils/format_utils.dart';
import '../widgets/product_card.dart';
import '../widgets/package_card.dart';
import '../widgets/flash_deal_card.dart';
import '../widgets/super_deal_card.dart';
import '../widgets/hot_deal_card.dart';
import 'product_detail_screen.dart';
import 'package_detail_screen.dart';
import '../widgets/sort_sheet.dart';

// ------------------------------------------------------------
// FLOATING FILTER CHIP (unchanged)
// ------------------------------------------------------------
class _FloatingFilterChip extends StatelessWidget {
  final String label;
  final String? selectedValue;
  final VoidCallback onTap;
  final bool showClear;
  final VoidCallback? onClear;

  const _FloatingFilterChip({
    required this.label,
    this.selectedValue,
    required this.onTap,
    this.showClear = false,
    this.onClear,
    Key? key,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final hasValue = selectedValue != null && selectedValue!.isNotEmpty;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(right: 6),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        decoration: BoxDecoration(
          color: hasValue ? AppColors.primary.withOpacity(0.08) : AppColors.cardBackground,
          borderRadius: BorderRadius.circular(AppShapes.radiusSm),
          border: Border.all(
            color: hasValue ? AppColors.primary : AppColors.borderLight,
            width: 1,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.03),
              blurRadius: 4,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              hasValue ? selectedValue! : label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: hasValue ? AppColors.primary : AppColors.textPrimary,
              ),
            ),
            if (showClear && hasValue) ...[
              const SizedBox(width: 4),
              GestureDetector(
                onTap: onClear,
                child: const Icon(Icons.close, size: 14, color: Colors.grey),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ------------------------------------------------------------
// MAIN SEARCH SCREEN
// ------------------------------------------------------------
class SearchScreen extends StatefulWidget {
  const SearchScreen({Key? key}) : super(key: key);
  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _focusNode = FocusNode();

  FilterParams _currentFilters = FilterParams();
  String _sortBy = 'relevance';

  List<Map<String, dynamic>> _suggestions = [];
  Timer? _suggestionDebounce;

  List<Map<String, dynamic>> _results = [];
  List<Map<String, dynamic>> _sponsoredProducts = [];
  List<Map<String, dynamic>> _featuredProducts = [];
  bool _isLoading = false;
  bool _isLoadingMore = false;
  int _currentPage = 1;
  bool _hasMore = true;

  List<Map<String, dynamic>> _trendingProducts = [];
  List<Map<String, dynamic>> _trendingCategories = [];
  List<Map<String, dynamic>> _trendingTerms = [];

  String? _spellSuggestion;
  int? _suggestionProductId;
  int? _dominantCategoryId;

  // ---- Inline filter data ----
  List<String> _availableBrands = [];
  List<Map<String, dynamic>> _availableCategories = [];
  List<double> _availableRatings = [];
  double _globalMinPrice = 0;
  double _globalMaxPrice = 100000;
  List<String> _availableShipping = [];
  Map<String, List<String>> _availableDynamicAttrs = {};
  Timer? _filterRefreshTimer;

  // ---- Hint rotation ----
  List<String> _hints = ['Search products...'];
  int _currentHintIndex = 0;
  Timer? _hintTimer;

  static const LinearGradient _headerGradient = LinearGradient(
    colors: [Color(0xFFFF7A00), Color(0xFFD84315)],
    begin: Alignment.centerLeft,
    end: Alignment.centerRight,
  );

  static const Map<String, String> _attributeNames = {
    'os': 'Operating System',
    'battery_capacity_mah': 'Battery Capacity',
    'screen_type': 'Screen Type',
    'processor': 'Processor',
    'graphics': 'Graphics',
    'connectivity': 'Connectivity',
    'resolution': 'Resolution',
    'megapixels': 'Megapixels',
    'material': 'Material',
    'skin_type': 'Skin Type',
    'energy_rating': 'Energy Rating',
    'condition': 'Condition',
    'style': 'Style',
    'dimensions': 'Dimensions',
  };

  String _displayAttrName(String key) =>
      _attributeNames[key] ?? key.replaceAll('_', ' ').split(' ').map((w) => w.isNotEmpty ? '${w[0].toUpperCase()}${w.substring(1)}' : w).join(' ');

  @override
  void initState() {
    super.initState();
    _focusNode.requestFocus();
    _fetchPopularSearches();
    _startHintRotation();
  }

  void _startHintRotation() {
    _hintTimer?.cancel();
    _hintTimer = Timer.periodic(const Duration(seconds: 3), (_) {
      if (!mounted) return;
      setState(() => _currentHintIndex = (_currentHintIndex + 1) % _hints.length);
    });
  }

  Future<void> _fetchPopularSearches() async {
    try {
      final res = await ApiClient.instance.get('/api/v1/popular_searches');
      final List data = res.data is List ? res.data : [];
      final allItems = data
          .where((item) => item is Map && item['query'] != null)
          .map((item) => item as Map<String, dynamic>)
          .toList();
      if (!mounted) return;
      setState(() {
        _trendingProducts = allItems.where((i) => i['type'] == 'product').toList();
        _trendingCategories = allItems.where((i) => i['type'] == 'category').toList();
        _trendingTerms = allItems.where((i) => i['type'] == 'trending').toList();
        final queries = allItems.map((i) => i['query']?.toString() ?? '').where((q) => q.isNotEmpty).toList();
        if (queries.isNotEmpty) _hints = queries;
      });
    } catch (_) {}
  }

  // ---------- DATA FETCHING ----------
  Future<void> _fetchSuggestions(String query) async {
    if (query.trim().length < 2) {
      setState(() => _suggestions = []);
      return;
    }
    try {
      final res = await ApiClient.instance.get('/api/v1/suggestions', queryParameters: {'q': query});
      final d = res.data;
      final list = <Map<String, dynamic>>[];

      void addSafely(List? raw, String type) {
        if (raw == null) return;
        for (final item in raw) {
          if (item is! Map) continue;
          final id = item['id'];
          final title = (item['title'] ?? item['name'])?.toString();
          final queryText = item['query']?.toString();
          final imageUrl = item['image_url']?.toString() ?? '';
          final price = item['price']?.toString() ?? '0';

          if (type == 'category') {
            if (id != null && title != null) list.add({'type': 'category', 'id': id, 'name': title});
          } else if (type == 'product') {
            if (id != null && title != null) list.add({'type': 'product', 'id': id, 'title': title, 'image_url': imageUrl, 'price': price});
          } else if (type == 'package') {
            if (id != null && title != null) list.add({'type': 'package', 'id': id, 'title': title, 'image_url': imageUrl, 'price': price});
          } else if (type == 'brand') {
            if (title != null) list.add({'type': 'brand', 'name': title});
          } else if (type == 'popular') {
            if (queryText != null) list.add({'type': 'popular', 'query': queryText});
          }
        }
      }

      addSafely(d['categories'] as List?, 'category');
      addSafely(d['products'] as List?, 'product');
      addSafely(d['packages'] as List?, 'package');
      addSafely(d['brands'] as List?, 'brand');
      addSafely(d['popular_searches'] as List?, 'popular');

      if (mounted) setState(() => _suggestions = list);
    } catch (_) {
      _suggestions = [];
    }
  }

  void _onSearchTextChanged(String value) {
    _suggestionDebounce?.cancel();
    if (value.trim().isEmpty) {
      setState(() {
        _suggestions = [];
        _results = [];
        _sponsoredProducts = [];
        _featuredProducts = [];
        _spellSuggestion = null;
        _suggestionProductId = null;
      });
      return;
    }
    if (_results.isNotEmpty || _spellSuggestion != null) {
      setState(() {
        _results = [];
        _sponsoredProducts = [];
        _featuredProducts = [];
        _spellSuggestion = null;
        _suggestionProductId = null;
      });
    }
    _suggestionDebounce = Timer(const Duration(milliseconds: 400), () {
      _fetchSuggestions(value);
    });
  }

  Future<void> _fetchInlineFilterOptions() async {
    try {
      final ctx = <String, String>{};
      final query = _searchController.text.trim();
      if (query.isNotEmpty) ctx['q'] = query;
      if (_dominantCategoryId != null) ctx['category'] = _dominantCategoryId!.toString();

      final data = await FilterOptionsService.fetchFilterOptions(
        context: ctx,
        currentFilters: _currentFilters.toQueryParams(),
      );
      if (!mounted) return;

      _availableBrands = ((data['brands'] as List?) ?? [])
          .map((e) => (e is Map ? e['name']?.toString() : e.toString()) ?? '')
          .where((s) => s.isNotEmpty)
          .toList();

      _availableCategories = ((data['categories'] as List?) ?? [])
          .where((e) => e is Map && e['id'] != null)
          .map((e) => {
                'id': e['id'],
                'name': e['name']?.toString() ?? '',
                'count': int.tryParse((e['count'] ?? 0).toString()) ?? 0,
              })
          .toList();

      _availableRatings = ((data['ratings'] as List?) ?? [])
          .map((e) => double.tryParse((e is Map ? (e['value'] ?? e['name']).toString() : e.toString())) ?? 0.0)
          .where((r) => r > 0)
          .toList();

      final pr = data['price_range'];
      if (pr is Map) {
        _globalMinPrice = _parseNum(pr['min'], 0);
        _globalMaxPrice = _parseNum(pr['max'], 100000);
        if (_globalMinPrice > _globalMaxPrice) {
          final tmp = _globalMinPrice; _globalMinPrice = _globalMaxPrice; _globalMaxPrice = tmp;
        }
        if (_globalMinPrice == _globalMaxPrice) _globalMaxPrice += 1.0;
      }

      _availableShipping = ((data['delivery_options'] as List?) ?? [])
          .map((e) => (e is Map ? e['label']?.toString() : e.toString()) ?? '')
          .where((s) => s.isNotEmpty)
          .toList();

      final dynAttrs = data['attributes'] ?? data['dynamic'];
      _availableDynamicAttrs = {};
      if (dynAttrs is Map) {
        dynAttrs.forEach((key, val) {
          if (val is List) {
            _availableDynamicAttrs[key.toString()] = val
                .map((e) => (e is Map ? (e['value'] ?? e['name']).toString() : e.toString()))
                .where((s) => s.isNotEmpty)
                .toList();
          }
        });
      }

      setState(() {});
    } catch (_) {
      setState(() {});
    }
  }

  double _parseNum(dynamic v, double fallback) {
    if (v == null) return fallback;
    if (v is num) return v.toDouble();
    if (v is String) return double.tryParse(v) ?? fallback;
    return fallback;
  }

  void _onFilterChanged() {
    _filterRefreshTimer?.cancel();
    _filterRefreshTimer = Timer(const Duration(milliseconds: 300), () {
      _fetchInlineFilterOptions();
      _executeSearch();
    });
  }

  void _resetFiltersInline() {
    setState(() => _currentFilters = FilterParams());
    _onFilterChanged();
  }

  Future<void> _executeSearch({bool loadMore = false}) async {
    final rawQuery = _searchController.text.trim();
    if (!loadMore && rawQuery.isEmpty) return;
    if (!loadMore && rawQuery.length < 2) {
      setState(() { _results = []; _sponsoredProducts = []; _featuredProducts = []; _isLoading = false; });
      return;
    }

    _suggestions = [];

    if (!loadMore) {
      _currentPage = 1; _hasMore = true;
      setState(() { _isLoading = true; _results = []; _sponsoredProducts = []; _featuredProducts = []; _spellSuggestion = null; _suggestionProductId = null; });
    } else {
      if (_isLoadingMore || !_hasMore) return;
      setState(() => _isLoadingMore = true);
    }

    final params = <String, dynamic>{
      'q': rawQuery,
      'page': _currentPage,
      'per_page': '28',
      'sort': _sortBy,
      ..._currentFilters.toQueryParams(),
    };

    try {
      final res = await ApiClient.instance.get('/api/v1/search', queryParameters: params);
      final List rawData = (res.data['data'] ?? []).where((e) => e != null).toList();
      final List<Map<String, dynamic>> results = rawData
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();

      final meta = res.data['meta'];
      final sponsoredRaw = (meta?['sponsored'] as List?)?.map((e) => Map<String, dynamic>.from(e)).toList() ?? [];
      final featuredRaw = (meta?['featured'] as List?)?.map((e) => Map<String, dynamic>.from(e)).toList() ?? [];

      setState(() {
        if (!loadMore) {
          _results = results;
          _sponsoredProducts = sponsoredRaw;
          _featuredProducts = featuredRaw;
          _currentPage = 2;
        } else {
          _results.addAll(results);
          _currentPage++;
        }
        _hasMore = rawData.length == 28;
        _isLoading = false; _isLoadingMore = false;
        _spellSuggestion = meta?['suggestion'];
        _suggestionProductId = meta?['suggestion_product_id'] as int?;
        _dominantCategoryId = meta?['dominant_category']?['id'] as int?;

        if (_results.isEmpty && _suggestionProductId != null) {
          _results = [{
            'type': 'suggestion',
            'id': _suggestionProductId,
            'title': _spellSuggestion ?? '',
            'price': '0',
            'image_urls': [],
          }];
          _sponsoredProducts = [];
          _featuredProducts = [];
        }
      });
      _fetchInlineFilterOptions();
    } catch (_) {
      setState(() { _isLoading = false; _isLoadingMore = false; });
    }
  }

  void _onSearchSubmitted(String value) => _executeSearch();

  void _onSuggestionTap(Map<String, dynamic> s) {
    final text = s['title'] ?? s['name'] ?? s['query'] ?? '';
    if (text is String && text.isNotEmpty) {
      _searchController.text = text;
      _executeSearch();
    }
  }

  void _clearSearch() {
    _searchController.clear();
    _suggestionDebounce?.cancel();
    _filterRefreshTimer?.cancel();
    setState(() {
      _currentFilters = FilterParams();
      _results = [];
      _sponsoredProducts = [];
      _featuredProducts = [];
      _suggestions = [];
      _sortBy = 'relevance';
      _isLoading = false;
      _dominantCategoryId = null;
      _spellSuggestion = null;
      _suggestionProductId = null;
    });
    _focusNode.requestFocus();
  }

  void _onPopularTap(String query) {
    _searchController.text = query;
    _executeSearch();
  }

  void _showSortSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => SortSheet(
        selectedSort: _sortBy,
        onSortSelected: (value) {
          setState(() => _sortBy = value);
          _executeSearch();
        },
      ),
    );
  }

  // ==============================================
  // FILTER BOTTOM SHEETS (unchanged)
  // ==============================================
  String _capitalizeFirst(String s) {
    if (s.isEmpty) return s;
    return '${s[0].toUpperCase()}${s.substring(1).toLowerCase()}';
  }

  Widget _buildSheetHeader(String title, String? count) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
      child: Row(
        children: [
          Expanded(child: Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: AppColors.textPrimary))),
          if (count != null) Text(count, style: const TextStyle(fontSize: 13, color: AppColors.textSecondary)),
        ],
      ),
    );
  }

  void _pickBrand() {
    final selectedBrands = <String>{..._currentFilters.brands};
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => StatefulBuilder(
        builder: (context, setModalState) {
          return Container(
            constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.7),
            decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _buildSheetHeader('Brand', '${_availableBrands.length} brands'),
                Flexible(
                  child: ListView.builder(
                    shrinkWrap: true,
                    padding: const EdgeInsets.only(bottom: 8),
                    itemCount: _availableBrands.length,
                    itemBuilder: (_, i) {
                      final brand = _availableBrands[i];
                      final selected = selectedBrands.contains(brand);
                      final display = _capitalizeFirst(brand);
                      return InkWell(
                        onTap: () {
                          setModalState(() {
                            if (selected) selectedBrands.remove(brand);
                            else selectedBrands.add(brand);
                          });
                        },
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                          child: Row(
                            children: [
                              Icon(selected ? Icons.check_circle : Icons.circle_outlined, color: selected ? AppColors.primary : Colors.grey, size: 22),
                              const SizedBox(width: 12),
                              Expanded(child: Text(display, style: TextStyle(fontSize: 15, fontWeight: selected ? FontWeight.w600 : FontWeight.w400, color: selected ? AppColors.primary : AppColors.textPrimary))),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: ElevatedButton(
                    onPressed: () {
                      setState(() { _currentFilters.brands = selectedBrands.toList(); });
                      _onFilterChanged();
                      Navigator.pop(context);
                    },
                    child: const Text('Apply'),
                    style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary, foregroundColor: Colors.white, minimumSize: const Size(double.infinity, 44)),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  void _pickCategory() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => StatefulBuilder(
        builder: (context, setModalState) {
          final selectedIds = <int>{..._currentFilters.categoryIds};
          return Container(
            constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.7),
            decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _buildSheetHeader('Category', '${_availableCategories.length} categories'),
                Flexible(
                  child: ListView.builder(
                    shrinkWrap: true,
                    padding: const EdgeInsets.only(bottom: 8),
                    itemCount: _availableCategories.length,
                    itemBuilder: (_, i) {
                      final cat = _availableCategories[i];
                      final id = cat['id'] as int;
                      final selected = selectedIds.contains(id);
                      final name = cat['name'] ?? '';
                      return InkWell(
                        onTap: () {
                          setModalState(() {
                            if (selected) selectedIds.remove(id);
                            else selectedIds.add(id);
                          });
                        },
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                          child: Row(
                            children: [
                              Icon(selected ? Icons.check_circle : Icons.circle_outlined, color: selected ? AppColors.primary : Colors.grey, size: 22),
                              const SizedBox(width: 12),
                              Expanded(child: Text(name, style: TextStyle(fontSize: 15, fontWeight: selected ? FontWeight.w600 : FontWeight.w400, color: selected ? AppColors.primary : AppColors.textPrimary))),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: ElevatedButton(
                    onPressed: () {
                      setState(() { _currentFilters.categoryIds = selectedIds.toList(); });
                      _onFilterChanged();
                      Navigator.pop(context);
                    },
                    child: const Text('Apply'),
                    style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary, foregroundColor: Colors.white, minimumSize: const Size(double.infinity, 44)),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  void _pickRating() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => Container(
        constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.4),
        decoration: const BoxDecoration(color: Colors.white, borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildSheetHeader('Minimum Rating', null),
            Flexible(
              child: ListView.builder(
                shrinkWrap: true,
                padding: const EdgeInsets.only(bottom: 8),
                itemCount: _availableRatings.length + 1,
                itemBuilder: (_, i) {
                  if (i == 0) {
                    final noneSelected = _currentFilters.ratingMin == null;
                    return InkWell(
                      onTap: () {
                        setState(() { _currentFilters.ratingMin = null; _onFilterChanged(); });
                        Navigator.pop(context);
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                        color: noneSelected ? AppColors.primary.withOpacity(0.08) : null,
                        child: Row(
                          children: [
                            Icon(noneSelected ? Icons.radio_button_checked : Icons.radio_button_off, color: noneSelected ? AppColors.primary : Colors.grey, size: 22),
                            const SizedBox(width: 12),
                            const Text('Any Rating', style: TextStyle(fontSize: 15)),
                          ],
                        ),
                      ),
                    );
                  }
                  final r = _availableRatings[i-1];
                  final selected = _currentFilters.ratingMin == r;
                  return InkWell(
                    onTap: () {
                      setState(() { _currentFilters.ratingMin = selected ? null : r; _onFilterChanged(); });
                      Navigator.pop(context);
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                      color: selected ? AppColors.primary.withOpacity(0.08) : null,
                      child: Row(
                        children: [
                          Icon(selected ? Icons.radio_button_checked : Icons.radio_button_off, color: selected ? AppColors.primary : Colors.grey, size: 22),
                          const SizedBox(width: 12),
                          const Icon(Icons.star, size: 16, color: Color(0xFFFFC107)),
                          const SizedBox(width: 4),
                          Text('$r+', style: TextStyle(fontSize: 15, color: selected ? AppColors.primary : AppColors.textPrimary, fontWeight: selected ? FontWeight.w600 : FontWeight.w400)),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _pickPrice() {
    double start = (_currentFilters.priceMin ?? _globalMinPrice).clamp(_globalMinPrice, _globalMaxPrice);
    double end = (_currentFilters.priceMax ?? _globalMaxPrice).clamp(_globalMinPrice, _globalMaxPrice);
    final minCtrl = TextEditingController(text: start.toInt().toString());
    final maxCtrl = TextEditingController(text: end.toInt().toString());

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => StatefulBuilder(
        builder: (context, setModalState) {
          return Padding(
            padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
            child: Container(
              constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.45),
              decoration: const BoxDecoration(color: Colors.white, borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _buildSheetHeader('Price Range', null),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                    child: Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: minCtrl,
                            decoration: InputDecoration(labelText: 'Min', border: OutlineInputBorder(borderRadius: BorderRadius.circular(8))),
                            keyboardType: TextInputType.number,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: TextField(
                            controller: maxCtrl,
                            decoration: InputDecoration(labelText: 'Max', border: OutlineInputBorder(borderRadius: BorderRadius.circular(8))),
                            keyboardType: TextInputType.number,
                          ),
                        ),
                      ],
                    ),
                  ),
                  RangeSlider(
                    values: RangeValues(start, end),
                    min: _globalMinPrice,
                    max: _globalMaxPrice,
                    divisions: 100,
                    labels: RangeLabels('ETB ${start.toInt()}', 'ETB ${end.toInt()}'),
                    onChanged: (v) {
                      setModalState(() {
                        start = v.start;
                        end = v.end;
                        minCtrl.text = v.start.toInt().toString();
                        maxCtrl.text = v.end.toInt().toString();
                      });
                    },
                  ),
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: ElevatedButton(
                      onPressed: () {
                        final min = double.tryParse(minCtrl.text);
                        final max = double.tryParse(maxCtrl.text);
                        if (min != null && max != null) {
                          setState(() {
                            _currentFilters.priceMin = min.clamp(_globalMinPrice, _globalMaxPrice);
                            _currentFilters.priceMax = max.clamp(_globalMinPrice, _globalMaxPrice);
                          });
                          _onFilterChanged();
                        }
                        Navigator.pop(context);
                      },
                      child: const Text('Apply'),
                      style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary, foregroundColor: Colors.white, minimumSize: const Size(double.infinity, 44)),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  void _pickShipping() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => Container(
        constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.4),
        decoration: const BoxDecoration(color: Colors.white, borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildSheetHeader('Shipping', null),
            Flexible(
              child: ListView.builder(
                shrinkWrap: true,
                padding: const EdgeInsets.only(bottom: 8),
                itemCount: _availableShipping.length,
                itemBuilder: (_, i) {
                  final opt = _availableShipping[i];
                  final selected = _currentFilters.deliveryOptions.contains(opt);
                  return InkWell(
                    onTap: () {
                      setState(() {
                        if (selected) _currentFilters.deliveryOptions.remove(opt);
                        else _currentFilters.deliveryOptions.add(opt);
                        _onFilterChanged();
                      });
                      Navigator.pop(context);
                    },
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                      child: Row(
                        children: [
                          Icon(selected ? Icons.check_circle : Icons.circle_outlined, color: selected ? AppColors.primary : Colors.grey, size: 22),
                          const SizedBox(width: 12),
                          Expanded(child: Text(opt, style: TextStyle(fontSize: 15, fontWeight: selected ? FontWeight.w600 : FontWeight.w400, color: selected ? AppColors.primary : AppColors.textPrimary))),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _pickAttributes() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => StatefulBuilder(
        builder: (context, setModalState) {
          return Container(
            constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.8),
            decoration: const BoxDecoration(color: Colors.white, borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _buildSheetHeader('Attributes', null),
                Flexible(
                  child: ListView.builder(
                    shrinkWrap: true,
                    itemCount: _availableDynamicAttrs.entries.length,
                    itemBuilder: (context, index) {
                      final entry = _availableDynamicAttrs.entries.elementAt(index);
                      return _AttributeSection(
                        title: _displayAttrName(entry.key),
                        values: entry.value,
                        selectedValues: _currentFilters.dynamicAttributes[entry.key] ?? [],
                        onChanged: (value) {
                          setModalState(() {
                            final list = _currentFilters.dynamicAttributes[entry.key] ?? [];
                            if (list.contains(value)) {
                              list.remove(value);
                              if (list.isEmpty) _currentFilters.dynamicAttributes.remove(entry.key);
                            } else {
                              _currentFilters.dynamicAttributes.putIfAbsent(entry.key, () => []);
                              _currentFilters.dynamicAttributes[entry.key]!.add(value);
                            }
                            setState(() {});
                          });
                        },
                      );
                    },
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: ElevatedButton(
                    onPressed: () { _onFilterChanged(); Navigator.pop(context); },
                    child: const Text('Apply'),
                    style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary, foregroundColor: Colors.white, minimumSize: const Size(double.infinity, 44)),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildCompactFilterBar() {
    if (_availableBrands.isEmpty && _availableCategories.isEmpty && _availableRatings.isEmpty && _availableShipping.isEmpty && _availableDynamicAttrs.isEmpty) {
      return const SizedBox.shrink();
    }

    final chips = <Widget>[
      if (_hasActiveFilters)
        GestureDetector(
          onTap: _resetFiltersInline,
          child: Container(
            margin: const EdgeInsets.only(right: 6),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(color: AppColors.error.withOpacity(0.08), borderRadius: BorderRadius.circular(AppShapes.radiusSm), border: Border.all(color: AppColors.error, width: 1)),
            child: Row(mainAxisSize: MainAxisSize.min, children: const [Icon(Icons.close, size: 14, color: AppColors.error), SizedBox(width: 2), Text('Clear', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: AppColors.error))]),
          ),
        ),
      _FloatingFilterChip(label: 'Brand', selectedValue: _currentFilters.brands.isNotEmpty ? _currentFilters.brands.join(', ') : null, onTap: _pickBrand, showClear: _currentFilters.brands.isNotEmpty, onClear: () { setState(() { _currentFilters.brands.clear(); _onFilterChanged(); }); }),
      _FloatingFilterChip(label: 'Category', selectedValue: _currentFilters.categoryIds.isNotEmpty ? _availableCategories.where((c) => _currentFilters.categoryIds.contains(c['id'])).map((c) => c['name'].toString()).join(', ') : null, onTap: _pickCategory, showClear: _currentFilters.categoryIds.isNotEmpty, onClear: () { setState(() { _currentFilters.categoryIds.clear(); _onFilterChanged(); }); }),
      if (_availableRatings.isNotEmpty)
        _FloatingFilterChip(label: 'Rating', selectedValue: _currentFilters.ratingMin != null ? '${_currentFilters.ratingMin}+' : null, onTap: _pickRating, showClear: _currentFilters.ratingMin != null, onClear: () { setState(() { _currentFilters.ratingMin = null; _onFilterChanged(); }); }),
      if (_globalMinPrice < _globalMaxPrice)
        _FloatingFilterChip(label: 'Price', selectedValue: (_currentFilters.priceMin != null && _currentFilters.priceMax != null) ? 'ETB ${_currentFilters.priceMin!.toInt()}-${_currentFilters.priceMax!.toInt()}' : null, onTap: _pickPrice, showClear: _currentFilters.priceMin != null, onClear: () { setState(() { _currentFilters.priceMin = null; _currentFilters.priceMax = null; _onFilterChanged(); }); }),
      if (_availableShipping.isNotEmpty)
        _FloatingFilterChip(label: 'Shipping', selectedValue: _currentFilters.deliveryOptions.isNotEmpty ? _currentFilters.deliveryOptions.join(', ') : null, onTap: _pickShipping, showClear: _currentFilters.deliveryOptions.isNotEmpty, onClear: () { setState(() { _currentFilters.deliveryOptions.clear(); _onFilterChanged(); }); }),
      if (_availableDynamicAttrs.isNotEmpty)
        _FloatingFilterChip(label: 'Attributes', selectedValue: _currentFilters.dynamicAttributes.isNotEmpty ? '${_currentFilters.dynamicAttributes.length} selected' : null, onTap: _pickAttributes, showClear: _currentFilters.dynamicAttributes.isNotEmpty, onClear: () { setState(() { _currentFilters.dynamicAttributes.clear(); _onFilterChanged(); }); }),
      _FloatingFilterChip(label: 'Sort', selectedValue: _sortBy == 'relevance' ? null : _sortBy.replaceAll('_', ' '), onTap: _showSortSheet, showClear: _sortBy != 'relevance', onClear: () { setState(() { _sortBy = 'relevance'; _executeSearch(); }); }),
    ];

    return Container(height: 36, margin: const EdgeInsets.only(bottom: 10), child: ListView(scrollDirection: Axis.horizontal, children: chips));
  }

  bool get _hasActiveFilters => _currentFilters.hasActiveFilters;

  @override
  void dispose() {
    _hintTimer?.cancel();
    _suggestionDebounce?.cancel();
    _filterRefreshTimer?.cancel();
    _focusNode.dispose();
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final rawQuery = _searchController.text.trim();
    final showResults = _results.isNotEmpty && (rawQuery.isNotEmpty || _results.any((r) => r['type'] != null));

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: const SystemUiOverlayStyle(statusBarColor: Colors.transparent, statusBarIconBrightness: Brightness.light),
      child: Scaffold(
        backgroundColor: AppColors.cardBackground,
        body: Column(
          children: [
            Container(
              decoration: const BoxDecoration(gradient: _headerGradient),
              child: SafeArea(
                bottom: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(8, 2, 8, 2),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      SizedBox(
                        width: 32, height: 40,
                        child: InkWell(
                          onTap: () => Navigator.pop(context),
                          borderRadius: BorderRadius.circular(8),
                          child: const Icon(Icons.arrow_back_ios_new_rounded, size: 18, color: Colors.white),
                        ),
                      ),
                      const SizedBox(width: 2),
                      Expanded(child: _buildSearchField()),
                    ],
                  ),
                ),
              ),
            ),
            Expanded(
              child: Container(color: AppColors.productListBackground, child: _buildContent(textTheme, rawQuery)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSearchField() {
    final hint = _hints.isEmpty ? 'Search products...' : _hints[_currentHintIndex];
    final rawQuery = _searchController.text.trim();
    return Container(
      height: 40,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(color: const Color(0xFFF5F5F5), borderRadius: BorderRadius.circular(14), border: Border.all(color: const Color(0xFFE0E0E0), width: 1)),
      child: TextField(
        controller: _searchController,
        focusNode: _focusNode,
        autofocus: true,
        cursorColor: AppColors.primary,
        style: const TextStyle(fontSize: 13, fontFamily: 'Inter', color: AppColors.textPrimary, fontWeight: FontWeight.w500),
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: TextStyle(fontSize: 13, fontFamily: 'Inter', color: Colors.grey.shade500),
          prefixIcon: const Padding(padding: EdgeInsets.only(left: 0, right: 8), child: Icon(Icons.search_rounded, size: 18, color: AppColors.primary)),
          prefixIconConstraints: const BoxConstraints(minWidth: 0, minHeight: 0),
          suffixIcon: rawQuery.isNotEmpty
              ? GestureDetector(onTap: _clearSearch, child: const Padding(padding: EdgeInsets.all(10), child: Icon(Icons.clear_rounded, color: AppColors.textMuted, size: 16)))
              : null,
          suffixIconConstraints: const BoxConstraints(minWidth: 0, minHeight: 0),
          filled: true,
          fillColor: const Color(0xFFF5F5F5),
          border: InputBorder.none,
          enabledBorder: InputBorder.none,
          focusedBorder: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(vertical: 0, horizontal: 0),
        ),
        onSubmitted: _onSearchSubmitted,
        onChanged: _onSearchTextChanged,
      ),
    );
  }

  Widget _buildContent(TextTheme textTheme, String rawQuery) {
    final showSuggestions = _suggestions.isNotEmpty && rawQuery.isNotEmpty && (_results.isEmpty && _spellSuggestion == null);
    if (_isLoading) return const Center(child: CircularProgressIndicator(color: AppColors.primary));
    if (showSuggestions) {
      return ListView.builder(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs),
        itemCount: _suggestions.length,
        itemBuilder: (_, i) => _suggestionTile(_suggestions[i], textTheme),
      );
    }
    if (_results.isEmpty && rawQuery.isEmpty) return SingleChildScrollView(child: _buildPopularSearches());
    if (_results.isEmpty && rawQuery.isNotEmpty) {
      return Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.search_off_rounded, size: 64, color: Colors.grey),
          const SizedBox(height: 16),
          Text('No products found', style: textTheme.bodyLarge?.copyWith(color: AppColors.textMuted)),
          if (_spellSuggestion != null) ...[
            const SizedBox(height: 8),
            TextButton.icon(
              onPressed: () { _searchController.text = _spellSuggestion!; _executeSearch(); },
              icon: const Icon(Icons.autorenew, size: 18),
              label: Text('Did you mean "$_spellSuggestion"?'),
              style: TextButton.styleFrom(foregroundColor: AppColors.primary),
            ),
          ],
        ]),
      );
    }
    if (_results.length == 1 && _results[0]['type'] == 'suggestion') {
      final product = _buildSuggestionProduct(_results[0]);
      return SingleChildScrollView(
        child: Column(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(AppSpacing.xs, 12, AppSpacing.xs, 4),
            child: Row(children: [
              const Icon(Icons.auto_awesome, size: 16, color: AppColors.primary),
              const SizedBox(width: 6),
              Text('Best match', style: textTheme.bodySmall?.copyWith(color: AppColors.primary, fontWeight: FontWeight.w600)),
              const Spacer(),
              TextButton(onPressed: _executeSearch, child: Text('Search instead', style: textTheme.bodySmall?.copyWith(color: AppColors.primary))),
            ]),
          ),
          Padding(
            padding: const EdgeInsets.all(AppSpacing.xs),
            child: GestureDetector(
              onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => ProductDetailScreen(productId: product.id))),
              child: ProductCard(product: product, isDeal: false),
            ),
          ),
        ]),
      );
    }

    final deals = _results.where((item) => item['type'] == 'product' && (item['is_flash_sale'] == true || item['is_super_deal'] == true || item['is_hot_deal'] == true)).toList();
    final packages = _results.where((item) => item['type'] == 'package').toList();
    final sponsoredIds = _sponsoredProducts.map((e) => e['id']).toSet();
    final featuredIds = _featuredProducts.map((e) => e['id']).toSet();
    final dealIds = deals.map((e) => e['id']).toSet();
    final packageIds = packages.map((e) => e['id']).toSet();
    final excludedIds = {...sponsoredIds, ...featuredIds, ...dealIds, ...packageIds};
    final mainResults = _results.where((item) => !excludedIds.contains(item['id'])).toList();

    final List<Widget> contentItems = [];
    contentItems.add(_buildCompactFilterBar());

    if (_sponsoredProducts.isNotEmpty) contentItems.add(_buildSponsoredSection());
    if (_featuredProducts.isNotEmpty) contentItems.add(_buildFeaturedSection());
    if (deals.isNotEmpty) contentItems.add(_buildDealsSection(deals));
    if (packages.isNotEmpty) contentItems.add(_buildPackagesSection(packages));

    for (final item in mainResults) {
      if (item['type'] == 'package') {
        contentItems.add(_buildPackageResult(item));
      } else {
        final product = _buildProductFromJson(item);
        contentItems.add(_buildRichSearchResultCard(product));
      }
    }

    if (_hasMore) contentItems.add(_buildLoadMore());

    return ListView(
      padding: EdgeInsets.fromLTRB(AppSpacing.xs, 8, AppSpacing.xs, MediaQuery.of(context).padding.bottom + 16),
      children: contentItems,
    );
  }

  // ==============================================
  // REUSABLE SECTION WITH DIVERSIFIED ICON BACKGROUND
  // ==============================================
  Widget _buildSectionWithIconBackground({
    required String title,
    required IconData titleIcon,
    required Color iconColor,
    required List<Map<String, dynamic>> items,
    required List<IconData> patternIcons,
  }) {
    final textTheme = Theme.of(context).textTheme;
    const double cardHeight = 200.0;
    const double titleHeight = 36.0;
    const double totalHeight = titleHeight + cardHeight + 8;

    final random = Random(42); // fixed seed for consistent, non‑flashing patterns
    final List<Widget> backgroundIcons = [];
    for (int i = 0; i < 250; i++) {
      final icon = patternIcons[random.nextInt(patternIcons.length)];
      final size = [10.0, 14.0, 18.0, 22.0, 26.0][random.nextInt(5)];
      final opacity = [0.06, 0.09, 0.12, 0.15][random.nextInt(4)];
      backgroundIcons.add(
        Opacity(
          opacity: opacity,
          child: Icon(icon, size: size, color: iconColor),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 4),
        ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: SizedBox(
            height: totalHeight,
            child: Stack(
              children: [
                Positioned.fill(
                  child: Wrap(
                    spacing: 2,
                    runSpacing: 2,
                    children: backgroundIcons,
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      child: Row(
                        children: [
                          Icon(titleIcon, size: 16, color: iconColor),
                          const SizedBox(width: 4),
                          Text(
                            title,
                            style: textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700, color: AppColors.textPrimary),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 4),
                    SizedBox(
                      height: cardHeight,
                      child: ListView.separated(
                        scrollDirection: Axis.horizontal,
                        clipBehavior: Clip.hardEdge,
                        itemCount: items.length,
                        separatorBuilder: (_, __) => const SizedBox(width: 8),
                        itemBuilder: (context, index) {
                          final item = items[index];
                          final product = _buildProductFromJson(item);
                          return SizedBox(
                            width: 140,
                            height: cardHeight,
                            child: FittedBox(
                              fit: BoxFit.scaleDown,
                              child: GestureDetector(
                                onTap: () => Navigator.push(
                                  context,
                                  MaterialPageRoute(builder: (_) => ProductDetailScreen(productId: product.id)),
                                ),
                                child: SuperDealCard(product: product),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  // ★ Sponsored section – dedicated pattern & color
  Widget _buildSponsoredSection() {
    return _buildSectionWithIconBackground(
      title: 'Sponsored',
      titleIcon: Icons.auto_awesome,
      iconColor: Colors.amber,
      items: _sponsoredProducts,
      patternIcons: const [
        Icons.auto_awesome,
        Icons.star,
        Icons.bolt,
        Icons.whatshot,
        Icons.rocket_launch,
        Icons.emoji_events,
        Icons.local_offer,
        Icons.verified,
      ],
    );
  }

  // ★ Featured section – dedicated pattern & color
  Widget _buildFeaturedSection() {
    return _buildSectionWithIconBackground(
      title: 'Featured',
      titleIcon: Icons.auto_awesome,
      iconColor: Colors.purple,
      items: _featuredProducts,
      patternIcons: const [
        Icons.auto_awesome,
        Icons.star,
        Icons.diamond,
        Icons.trending_up,
        Icons.new_releases,
        Icons.verified,
        Icons.bolt,
        Icons.whatshot,
      ],
    );
  }

  // ★ Deals section – unchanged
  Widget _buildDealsSection(List<Map<String, dynamic>> deals) {
    final textTheme = Theme.of(context).textTheme;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const SizedBox(height: 4),
      Row(children: [const Icon(Icons.local_offer, size: 16, color: Colors.red), const SizedBox(width: 4), Text('Deals', style: textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700, color: AppColors.textPrimary))]),
      const SizedBox(height: 4),
      SizedBox(
        height: 200,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          clipBehavior: Clip.hardEdge,
          itemCount: deals.length,
          separatorBuilder: (_, __) => const SizedBox(width: 8),
          itemBuilder: (context, index) {
            final item = deals[index];
            final product = _buildProductFromJson(item);
            Widget dealWidget;
            if (item['is_flash_sale'] == true) {
              dealWidget = FlashDealCard(product: product);
            } else if (item['is_super_deal'] == true) {
              dealWidget = SuperDealCard(product: product);
            } else {
              dealWidget = HotDealCard(product: product);
            }
            return SizedBox(
              width: 140,
              height: 200,
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: GestureDetector(
                  onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => ProductDetailScreen(productId: product.id))),
                  child: dealWidget,
                ),
              ),
            );
          },
        ),
      ),
    ]);
  }

  // ★ Packages section – larger image, compact text
  Widget _buildPackagesSection(List<Map<String, dynamic>> packages) {
    final textTheme = Theme.of(context).textTheme;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const SizedBox(height: 4),
      Row(children: [const Icon(Icons.inventory_2, size: 16, color: Colors.green), const SizedBox(width: 4), Text('Packages', style: textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700, color: AppColors.textPrimary))]),
      const SizedBox(height: 4),
      SizedBox(
        height: 200,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          itemCount: packages.length,
          separatorBuilder: (_, __) => const SizedBox(width: 8),
          itemBuilder: (context, index) {
            final item = packages[index];
            final String title = item['title']?.toString() ?? item['name']?.toString() ?? '';
            final double price = double.tryParse(item['price']?.toString() ?? '') ?? 0.0;
            final int packageId = (item['id'] is int) ? item['id'] : int.tryParse(item['id'].toString()) ?? 0;

            String imageUrl = '';
            if (item['image_urls'] is List && (item['image_urls'] as List).isNotEmpty) {
              imageUrl = (item['image_urls'] as List).first.toString();
            }

            return GestureDetector(
              onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => PackageDetailScreen(packageId: packageId))),
              child: Container(
                width: 160,
                decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(AppShapes.radiusSm), boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 4, offset: Offset(0,2))]),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.vertical(top: Radius.circular(AppShapes.radiusSm)),
                      child: imageUrl.isNotEmpty
                          ? Image.network(imageUrl, height: 140, width: double.infinity, fit: BoxFit.cover)
                          : Container(height: 140, color: Colors.grey.shade200, child: const Icon(Icons.inventory_2, size: 32, color: Colors.grey)),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                        const SizedBox(height: 2),
                        Text('ETB ${price.toStringAsFixed(0)}', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.black)),
                      ]),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    ]);
  }

  // ★ Single package result card
  Widget _buildPackageResult(Map<String, dynamic> item) {
    final String title = item['title']?.toString() ?? item['name']?.toString() ?? '';
    final double price = double.tryParse(item['price']?.toString() ?? '') ?? 0.0;
    final int packageId = (item['id'] is int) ? item['id'] : int.tryParse(item['id'].toString()) ?? 0;

    String imageUrl = '';
    if (item['image_urls'] is List && (item['image_urls'] as List).isNotEmpty) {
      imageUrl = (item['image_urls'] as List).first.toString();
    }

    return GestureDetector(
      onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => PackageDetailScreen(packageId: packageId))),
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(AppShapes.radiusSm), boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 4, offset: Offset(0,2))]),
        child: Row(children: [
          ClipRRect(
            borderRadius: BorderRadius.only(topLeft: Radius.circular(AppShapes.radiusSm), bottomLeft: Radius.circular(AppShapes.radiusSm)),
            child: imageUrl.isNotEmpty
                ? Image.network(imageUrl, width: 80, height: 80, fit: BoxFit.cover)
                : Container(width: 80, height: 80, color: Colors.grey.shade200, child: const Icon(Icons.inventory_2, size: 32)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(title, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                const SizedBox(height: 4),
                Text('ETB ${price.toStringAsFixed(0)}', style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.black)),
              ]),
            ),
          ),
        ]),
      ),
    );
  }

  // ------------------------------------------------------------
  // RICH SEARCH RESULT CARD (hardened with backend delivery_label & stock fields)
  // ------------------------------------------------------------
  Widget _buildRichSearchResultCard(Product product) {
    final textTheme = Theme.of(context).textTheme;
    final effectivePrice = product.effectivePrice ?? product.price;
    final price = FormatUtils.price(effectivePrice);
    final hasDiscount = product.discountPercentage > 0;

    double? displayOriginalPrice;
    if (product.originalPrice != null && product.originalPrice! > effectivePrice && product.originalPrice! > 0) {
      displayOriginalPrice = product.originalPrice;
    } else if (hasDiscount) {
      final discountFraction = product.discountPercentage / 100.0;
      if (discountFraction < 1.0) {
        displayOriginalPrice = effectivePrice / (1 - discountFraction);
      }
    }

    final attrs = product.productAttributes;
    final brand = attrs['brand'] as String?;
    final condition = attrs['condition'] as String?;

    final extraSpecs = <String>[];
    if (attrs.isNotEmpty) {
      attrs.forEach((key, value) {
        if (key != 'brand' && key != 'condition' && value != null && value.toString().isNotEmpty) {
          extraSpecs.add('${_displayAttrName(key)}: ${value.toString()}');
        }
      });
    }
    final showSpecs = extraSpecs.take(2).toList();

    // ★ Stock display – use availableStock and outOfStock if available
    String stockText;
    final availStock = product.availableStock;
    final outOfStock = product.outOfStock;
    final bulk = product.bulkEnabled;
    if (bulk && product.stock == null) {
      stockText = 'Unlimited';
    } else if (outOfStock == true) {
      stockText = 'Out of stock';
    } else if (availStock != null && availStock > 0) {
      stockText = 'In stock';
    } else {
      stockText = 'Out of stock';
    }

    // ★ Delivery label – prefer backend field, fallback to manual calculation
    String? deliveryLabel;
    if (product.deliveryLabel != null && product.deliveryLabel!.isNotEmpty) {
      deliveryLabel = product.deliveryLabel;
    } else {
      if (product.freeShipping) {
        deliveryLabel = 'Free Delivery';
      } else if (product.sellerPaysShipping && product.shippingSubsidyType != null && product.shippingSubsidyValue != null) {
        final valueNum = (product.shippingSubsidyValue ?? 0).round();
        if (product.shippingSubsidyType == 'percentage') {
          deliveryLabel = '$valueNum% off Delivery';
        } else if (product.shippingSubsidyType == 'fixed') {
          deliveryLabel = 'ETB $valueNum off Delivery';
        }
      }
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: InkWell(
        onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => ProductDetailScreen(productId: product.id))),
        borderRadius: BorderRadius.circular(AppShapes.radiusSm),
        child: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(color: const Color(0xFFF5F5F5), borderRadius: BorderRadius.circular(AppShapes.radiusSm), border: Border.all(color: const Color(0xFFE0E0E0), width: 0.5)),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(AppShapes.radiusSm),
                child: Image.network(
                  product.imageUrl, width: 120, height: 120, fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => Container(width: 120, height: 120, color: AppColors.hoverState, child: const Icon(Icons.image_not_supported, color: AppColors.textMuted, size: 24)),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(product.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: textTheme.headlineMedium?.copyWith(fontSize: 14, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 4),
                  if (brand != null && brand.isNotEmpty)
                    Padding(padding: const EdgeInsets.only(bottom: 2), child: Text('Brand: ${_capitalizeFirst(brand)}', style: textTheme.bodySmall?.copyWith(fontSize: 12, color: AppColors.textSecondary), maxLines: 1, overflow: TextOverflow.ellipsis)),
                  if (condition != null && condition.isNotEmpty)
                    Padding(padding: const EdgeInsets.only(bottom: 2), child: Text('Condition: $condition', style: textTheme.bodySmall?.copyWith(fontSize: 11, color: AppColors.textSecondary), maxLines: 1, overflow: TextOverflow.ellipsis)),
                  if (showSpecs.isNotEmpty)
                    Padding(padding: const EdgeInsets.only(bottom: 2), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: showSpecs.map((spec) => Padding(padding: const EdgeInsets.only(bottom: 1), child: Text(spec, style: textTheme.bodySmall?.copyWith(fontSize: 10, color: AppColors.textSecondary), maxLines: 1, overflow: TextOverflow.ellipsis))).toList())),
                  Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
                    Text(price, style: textTheme.titleMedium?.copyWith(fontSize: 16, fontWeight: FontWeight.w700)),
                    if (hasDiscount) ...[
                      const SizedBox(width: 6),
                      Container(padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1), decoration: BoxDecoration(color: AppColors.error.withOpacity(0.1), borderRadius: BorderRadius.circular(3)), child: Text('${product.discountPercentage}% off', style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: AppColors.error))),
                    ],
                  ]),
                  if (displayOriginalPrice != null)
                    Padding(padding: const EdgeInsets.only(top: 2), child: Text(FormatUtils.price(displayOriginalPrice), style: textTheme.bodySmall?.copyWith(fontSize: 11, color: AppColors.textMuted, decoration: TextDecoration.lineThrough))),
                  const SizedBox(height: 4),
                  Row(children: [
                    if (product.rating > 0) ...[
                      Row(children: List.generate(5, (i) { final filled = i < product.rating.round(); return Icon(filled ? Icons.star : Icons.star_border, size: 13, color: filled ? AppColors.starGold : Colors.grey.shade300); })),
                      const SizedBox(width: 4),
                      Text('(${product.reviewsCount})', style: textTheme.bodySmall?.copyWith(fontSize: 11, color: AppColors.textSecondary)),
                    ],
                    if (deliveryLabel != null)
                      Container(padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2), margin: const EdgeInsets.only(left: 6), decoration: BoxDecoration(color: AppColors.success.withOpacity(0.1), borderRadius: BorderRadius.circular(4)), child: Text(deliveryLabel, style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: AppColors.success))),
                    const SizedBox(width: 6),
                    Container(padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2), decoration: BoxDecoration(color: stockText == 'Out of stock' ? Colors.red.withOpacity(0.1) : Colors.green.withOpacity(0.1), borderRadius: BorderRadius.circular(4)), child: Text(stockText, style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: stockText == 'Out of stock' ? Colors.red : Colors.green))),
                  ]),
                ]),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ---------- HELPERS ----------
  Widget _buildLoadMore() => Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 16),
          child: _isLoadingMore ? const CircularProgressIndicator(color: AppColors.primary) : TextButton(onPressed: () => _executeSearch(loadMore: true), child: Text('Load More', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: AppColors.primary))),
        ),
      );

  double _toDouble(dynamic v) {
    if (v == null) return 0.0;
    if (v is double) return v;
    if (v is int) return v.toDouble();
    return double.tryParse(v.toString()) ?? 0.0;
  }

  Product _buildSuggestionProduct(Map item) {
    return Product(
      id: item['id'] as int? ?? 0,
      title: item['title']?.toString() ?? '',
      price: _toDouble(item['price']),
      imageUrl: (item['image_urls'] is List && (item['image_urls'] as List).isNotEmpty) ? (item['image_urls'] as List).first.toString() : '',
      rating: 0, reviewsCount: 0, soldCount: 0, freeShipping: false, discountPercentage: 0,
      images: item['image_urls'] is List ? List<String>.from(item['image_urls'] ?? []) : [],
      effectivePrice: _toDouble(item['price']),
    );
  }

  Product _buildProductFromJson(Map<String, dynamic> json) {
    return Product.fromJson(json);
  }

  Widget _suggestionTile(Map<String, dynamic> s, TextTheme textTheme) {
    final title = s['title']?.toString() ?? s['name']?.toString() ?? s['query']?.toString() ?? '';
    final price = _toDouble(s['price']);
    return ListTile(
      dense: true,
      visualDensity: VisualDensity.compact,
      leading: const Icon(Icons.search, size: 20, color: AppColors.primary),
      title: Text(title, style: textTheme.bodyMedium?.copyWith(fontSize: 14, fontWeight: FontWeight.w500, color: AppColors.textPrimary)),
      subtitle: price > 0 ? Text('ETB ${price.toStringAsFixed(2)}', style: textTheme.bodySmall?.copyWith(color: AppColors.textMuted)) : null,
      trailing: const Icon(Icons.arrow_forward_ios, size: 14, color: AppColors.textMuted),
      onTap: () => _onSuggestionTap(s),
    );
  }

  Widget _buildPopularSearches() {
    final textTheme = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(AppSpacing.xs, 24, AppSpacing.xs, 24),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        if (_trendingProducts.isNotEmpty) ...[
          Text('🔥 Trending Products', style: textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
          const SizedBox(height: 12),
          Wrap(spacing: 6, runSpacing: 6, children: _trendingProducts.map((i) => _subChip(i['query'] ?? '', onTap: () => _onPopularTap(i['query'] ?? ''))).toList()),
          const SizedBox(height: 20),
        ],
        if (_trendingCategories.isNotEmpty) ...[
          Text('📂 Popular Categories', style: textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
          const SizedBox(height: 12),
          Wrap(spacing: 6, runSpacing: 6, children: _trendingCategories.map((i) => _subChip(i['query'] ?? '', onTap: () => _onPopularTap(i['query'] ?? ''))).toList()),
          const SizedBox(height: 20),
        ],
        if (_trendingTerms.isNotEmpty) ...[
          Text('🔍 Trending Searches', style: textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
          const SizedBox(height: 12),
          Wrap(spacing: 6, runSpacing: 6, children: _trendingTerms.map((i) => _subChip(i['query'] ?? '', onTap: () => _onPopularTap(i['query'] ?? ''))).toList()),
        ],
        if (_trendingProducts.isEmpty && _trendingCategories.isEmpty && _trendingTerms.isEmpty)
          Center(child: Text('Start typing to search', style: textTheme.bodySmall?.copyWith(color: AppColors.textMuted))),
      ]),
    );
  }

  Widget _subChip(String label, {VoidCallback? onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(color: AppColors.cardBackground, borderRadius: BorderRadius.circular(AppShapes.radiusSm), border: Border.all(color: AppColors.borderLight, width: 1)),
        child: Text(label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: AppColors.textPrimary)),
      ),
    );
  }
}

// ------------------------------------------------------------
// Custom fast attribute section (unchanged)
// ------------------------------------------------------------
class _AttributeSection extends StatefulWidget {
  final String title;
  final List<String> values;
  final List<String> selectedValues;
  final ValueChanged<String> onChanged;

  const _AttributeSection({required this.title, required this.values, required this.selectedValues, required this.onChanged, Key? key}) : super(key: key);

  @override
  State<_AttributeSection> createState() => _AttributeSectionState();
}

class _AttributeSectionState extends State<_AttributeSection> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      InkWell(
        onTap: () => setState(() => _expanded = !_expanded),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          child: Row(children: [
            Expanded(child: Text(widget.title, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: AppColors.textPrimary))),
            if (widget.selectedValues.isNotEmpty)
              Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2), decoration: BoxDecoration(color: AppColors.primary.withOpacity(0.1), borderRadius: BorderRadius.circular(12)), child: Text('${widget.selectedValues.length}', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.primary))),
            const SizedBox(width: 8),
            AnimatedRotation(turns: _expanded ? 0.5 : 0, duration: const Duration(milliseconds: 200), child: const Icon(Icons.keyboard_arrow_down, size: 22, color: Colors.grey)),
          ]),
        ),
      ),
      if (_expanded)
        ...widget.values.map((v) {
          final selected = widget.selectedValues.contains(v);
          return InkWell(
            onTap: () => widget.onChanged(v),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10).copyWith(left: 52),
              child: Row(children: [
                Icon(selected ? Icons.check_circle : Icons.circle_outlined, color: selected ? AppColors.primary : Colors.grey, size: 22),
                const SizedBox(width: 12),
                Expanded(child: Text(v, style: TextStyle(fontSize: 14, fontWeight: selected ? FontWeight.w500 : FontWeight.w400, color: selected ? AppColors.primary : AppColors.textPrimary))),
              ]),
            ),
          );
        }),
    ]);
  }
}
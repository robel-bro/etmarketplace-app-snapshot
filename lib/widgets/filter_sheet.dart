// 📁 lib/widgets/filter_sheet.dart
import 'dart:async';
import 'package:flutter/material.dart';
import '../api/filter_options_service.dart';
import '../models/filter_params.dart';
import '../theme/app_theme.dart';

class FilterSheet extends StatefulWidget {
  final FilterParams initialParams;
  final Map<String, String> context;
  final ValueChanged<FilterParams> onApply;
  final int? totalCount;

  const FilterSheet({
    Key? key,
    required this.initialParams,
    required this.context,
    required this.onApply,
    this.totalCount,
  }) : super(key: key);

  @override
  State<FilterSheet> createState() => _FilterSheetState();
}

class _FilterSheetState extends State<FilterSheet> with TickerProviderStateMixin {
  late FilterParams _localParams;

  // ---------- Category state ----------
  List<Map<String, dynamic>> _displayCategories = [];
  bool _showCategoryRow = false;
  String? _categoryContextId;

  // ---------- Other filter data ----------
  List<Map<String, dynamic>> _brands = [];
  double _globalMinPrice = 0;
  double _globalMaxPrice = 100000;
  List<Map<String, dynamic>> _ratings = [];
  List<Map<String, dynamic>> _deliveryOptions = [];
  Map<String, List<Map<String, dynamic>>> _dynamicAttrs = {};
  List<Map<String, dynamic>> _discountTypes = [];

  bool _loading = true;
  String _brandSearch = '';
  Timer? _debounceTimer;

  final Map<String, bool> _expandedSections = {};

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

  String _displayName(String key) =>
      _attributeNames[key] ?? key.replaceAll('_', ' ').split(' ').map((w) => w.isNotEmpty ? '${w[0].toUpperCase()}${w.substring(1)}' : w).join(' ');

  final TextEditingController _minPriceController = TextEditingController();
  final TextEditingController _maxPriceController = TextEditingController();
  bool _controllersInitialised = false;

  @override
  void initState() {
    super.initState();
    _localParams = widget.initialParams.copyWith();
    _categoryContextId = widget.context['category'];
    _initData();
  }

  @override
  void dispose() {
    _minPriceController.dispose();
    _maxPriceController.dispose();
    _debounceTimer?.cancel();
    super.dispose();
  }

  Future<void> _initData() async {
    setState(() => _loading = true);
    if (_categoryContextId != null) {
      await _fetchSubCategories(int.parse(_categoryContextId!));
    } else {
      await _fetchMainCategories();
    }
    await _fetchFilterData();
    _initPriceControllers();
    if (mounted) setState(() => _loading = false);
  }

  void _initPriceControllers() {
    if (_controllersInitialised) return;
    _minPriceController.text = (_localParams.priceMin ?? _globalMinPrice).toInt().toString();
    _maxPriceController.text = (_localParams.priceMax ?? _globalMaxPrice).toInt().toString();
    _controllersInitialised = true;
  }

  // ---------- API helpers (unchanged) ----------
  Future<void> _fetchMainCategories() async {
    try {
      final Map<String, String> ctx = Map.from(widget.context);
      ctx.remove('q');
      ctx.remove('parent_category');
      final data = await FilterOptionsService.fetchFilterOptions(context: ctx, currentFilters: _localParams.toQueryParams());
      if (!mounted) return;
      final list = _toCategoryList(data['categories']);
      setState(() { _displayCategories = list; _showCategoryRow = list.isNotEmpty; });
    } catch (_) {}
  }

  Future<void> _fetchSubCategories(int parentId) async {
    try {
      final Map<String, String> ctx = Map.from(widget.context);
      ctx.remove('q');
      ctx['parent_category'] = parentId.toString();
      final data = await FilterOptionsService.fetchFilterOptions(context: ctx, currentFilters: _localParams.toQueryParams());
      if (!mounted) return;
      final seen = <int>{};
      final list = _toCategoryList(data['categories']).where((c) {
        final id = c['id'] as int? ?? int.tryParse(c['id'].toString()) ?? 0;
        return seen.add(id);
      }).toList();
      setState(() { _displayCategories = list; _showCategoryRow = list.isNotEmpty; });
    } catch (_) {}
  }

  Future<void> _fetchFilterData() async {
    try {
      final Map<String, String> ctx = Map.from(widget.context);
      ctx.remove('q');
      if (_categoryContextId != null) { ctx['category'] = _categoryContextId!; } else { ctx.remove('category'); }
      final data = await FilterOptionsService.fetchFilterOptions(context: ctx, currentFilters: _localParams.toQueryParams());
      if (!mounted) return;
      setState(() {
        _brands = _parseCountList(data['brands'], nameKey: 'name');
        final pr = data['price_range'];
        if (pr is Map) {
          _globalMinPrice = _parseNum(pr['min'], 0);
          _globalMaxPrice = _parseNum(pr['max'], 100000);
          if (_globalMinPrice > _globalMaxPrice) { final tmp = _globalMinPrice; _globalMinPrice = _globalMaxPrice; _globalMaxPrice = tmp; }
          if (_globalMinPrice == _globalMaxPrice) _globalMaxPrice += 1.0;
        }
        _ratings = _parseCountList(data['ratings'], nameKey: 'value');
        _deliveryOptions = _parseCountList(data['delivery_options'], nameKey: 'label');
        _dynamicAttrs = _parseDynamicAttrs(data['attributes'] ?? data['dynamic']);
        _discountTypes = _parseCountList(data['discount_types'] ?? [], nameKey: 'name');
      });
    } catch (_) {}
  }

  double _parseNum(dynamic v, double fallback) {
    if (v == null) return fallback;
    if (v is num) return v.toDouble();
    if (v is String) return double.tryParse(v) ?? fallback;
    return fallback;
  }

  List<Map<String, dynamic>> _parseCountList(dynamic source, {String nameKey = 'name'}) {
    if (source is! List) return [];
    return source.map((e) {
      if (e is Map) {
        final name = (e[nameKey] ?? e['name'] ?? e['value'] ?? e['label'] ?? '').toString();
        final count = int.tryParse((e['count'] ?? 0).toString()) ?? 0;
        return {'name': name, 'count': count};
      }
      return {'name': e.toString(), 'count': 0};
    }).toList();
  }

  Map<String, List<Map<String, dynamic>>> _parseDynamicAttrs(dynamic source) {
    if (source is! Map) return {};
    final result = <String, List<Map<String, dynamic>>>{};
    source.forEach((key, val) {
      if (val is List) {
        result[key.toString()] = val.map((e) {
          if (e is Map) {
            final name = (e['value'] ?? e['name'] ?? '').toString();
            final count = int.tryParse((e['count'] ?? 0).toString()) ?? 0;
            return {'name': name, 'count': count};
          }
          return {'name': e.toString(), 'count': 0};
        }).toList();
      }
    });
    return result;
  }

  List<Map<String, dynamic>> _toCategoryList(dynamic v) {
    if (v is! List) return [];
    return v.whereType<Map>().map((e) => {
      'id': e['id'],
      'name': e['name'],
      'count': int.tryParse((e['count'] ?? 0).toString()) ?? 0,
      'image_url': e['image_url']?.toString(),
    }).toList();
  }

  bool get _hasActiveFilters => _localParams.hasActiveFilters;

  void _apply() {
    widget.onApply(_localParams);
    Navigator.pop(context);
  }

  void _resetAll() {
    setState(() {
      _localParams = FilterParams();
      _brandSearch = '';
      _minPriceController.text = _globalMinPrice.toInt().toString();
      _maxPriceController.text = _globalMaxPrice.toInt().toString();
    });
    _scheduleRefresh(resetContext: true);
  }

  void _scheduleRefresh({bool resetContext = false}) {
    _debounceTimer?.cancel();
    _debounceTimer = Timer(const Duration(milliseconds: 300), () {
      _fetchFilterData();
      if (!resetContext && _categoryContextId != null) {
        _fetchSubCategories(int.parse(_categoryContextId!));
      } else if (_categoryContextId == null) {
        _fetchMainCategories();
      }
    });
  }

  void _selectCategory(int id) {
    setState(() {
      if (_localParams.categoryIds.contains(id)) {
        _localParams.categoryIds.remove(id);
      } else {
        _localParams.categoryIds.clear();
        _localParams.categoryIds.add(id);
      }
    });
    _scheduleRefresh();
  }

  // ---------- Circular indicator (replaces checkbox) ----------
  Widget _circleIndicator({required bool selected, double size = 20}) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: selected ? AppColors.primary : Colors.transparent,
        border: Border.all(
          color: selected ? AppColors.primary : AppColors.borderLight,
          width: 2,
        ),
      ),
      child: selected
          ? const Icon(Icons.check, size: 14, color: Colors.white)
          : null,
    );
  }

  // ---------- Typography‑aware helpers ----------
  Widget _sectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.xs),
      child: Text(
        title,
        style: Theme.of(context).textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w700, color: AppColors.textPrimary),
      ),
    );
  }

  // Category items – uses cardTitle size (13) for name, cardMeta (11) for count
  Widget _categoryItem(Map<String, dynamic> cat, bool selected, VoidCallback onTap) {
    final name = cat['name']?.toString() ?? '';
    final count = cat['count'] as int? ?? 0;
    final imageUrl = cat['image_url']?.toString();
    return GestureDetector(
      onTap: onTap,
      child: SizedBox(
        width: 72,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 44, height: 44,
              decoration: BoxDecoration(
                color: selected ? AppColors.primary.withOpacity(0.08) : AppColors.hoverState,
                borderRadius: BorderRadius.circular(AppShapes.radiusMd),
              ),
              child: Center(
                child: imageUrl != null && imageUrl.isNotEmpty
                    ? ClipRRect(
                        borderRadius: BorderRadius.circular(AppShapes.radiusMd - 2),
                        child: Image.network(imageUrl, width: 30, height: 30, fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => _fallbackIcon(name),
                        ),
                      )
                    : _fallbackIcon(name),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              name,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                color: selected ? AppColors.primary : AppColors.textPrimary,
                height: 1.2,
              ),
            ),
            if (count > 0)
              Text(
                '($count)',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  fontSize: 10,
                  color: selected ? AppColors.primary : AppColors.textMuted,
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _fallbackIcon(String name) {
    final lower = name.toLowerCase();
    IconData icon;
    if (lower.contains('electron')) icon = Icons.devices;
    else if (lower.contains('fashion') || lower.contains('cloth')) icon = Icons.checkroom;
    else if (lower.contains('home')) icon = Icons.home;
    else if (lower.contains('sport')) icon = Icons.fitness_center;
    else if (lower.contains('beauty')) icon = Icons.face;
    else icon = Icons.category;
    return Icon(icon, size: 22, color: AppColors.textMuted);
  }

  // Brand section – uses headlineMedium (13) for chip text
  Widget _buildBrandSection() {
    final filtered = _brands.where((b) => b['name'].toLowerCase().contains(_brandSearch.toLowerCase())).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionTitle('Brand'),
        Container(
          height: 40,
          margin: const EdgeInsets.only(bottom: AppSpacing.sm),
          decoration: BoxDecoration(
            color: AppColors.hoverState,
            borderRadius: BorderRadius.circular(AppShapes.radiusSm),
          ),
          child: TextField(
            decoration: InputDecoration(
              hintText: 'Search brands…',
              hintStyle: Theme.of(context).textTheme.bodySmall?.copyWith(color: AppColors.textMuted),
              prefixIcon: const Icon(Icons.search, size: 18, color: AppColors.textMuted),
              border: InputBorder.none,
              contentPadding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
            ),
            style: Theme.of(context).textTheme.headlineMedium?.copyWith(
              fontWeight: FontWeight.w400,
              color: AppColors.textPrimary,
            ),
            onChanged: (v) => setState(() => _brandSearch = v),
          ),
        ),
        SizedBox(
          height: 36,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: filtered.length,
            separatorBuilder: (_, __) => const SizedBox(width: AppSpacing.xs),
            itemBuilder: (context, index) {
              final brand = filtered[index];
              final name = brand['name'] as String;
              final count = brand['count'] as int? ?? 0;
              final selected = _localParams.brands.contains(name);
              return GestureDetector(
                onTap: () => setState(() {
                  if (selected) { _localParams.brands.remove(name); } else { _localParams.brands.add(name); }
                  _scheduleRefresh();
                }),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: selected ? AppColors.primary.withOpacity(0.08) : AppColors.cardBackground,
                    borderRadius: BorderRadius.circular(AppShapes.radiusSm),
                  ),
                  child: Text(
                    '$name${count > 0 ? ' ($count)' : ''}',
                    style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                      fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                      color: selected ? AppColors.primary : AppColors.textPrimary,
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  // Rating section – uses headlineMedium (13) for text
  Widget _buildRatingSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionTitle('Rating'),
        Wrap(
          spacing: AppSpacing.xs,
          runSpacing: AppSpacing.xs,
          children: _ratings.map((r) {
            final name = r['name'] as String? ?? '';
            final ratingValue = double.tryParse(name) ?? 0;
            final count = r['count'] as int? ?? 0;
            final selected = _localParams.ratingMin == ratingValue;
            return GestureDetector(
              onTap: () {
                setState(() => _localParams.ratingMin = selected ? null : ratingValue);
                _scheduleRefresh();
              },
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: selected ? AppColors.primary.withOpacity(0.08) : AppColors.cardBackground,
                  borderRadius: BorderRadius.circular(AppShapes.radiusSm),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.star, size: 14, color: AppColors.starGold),
                    const SizedBox(width: 4),
                    Text(
                      '$name & up${count > 0 ? ' ($count)' : ''}',
                      style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                        fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                        color: selected ? AppColors.primary : AppColors.textPrimary,
                      ),
                    ),
                  ],
                ),
              ),
            );
          }).toList(),
        ),
      ],
    );
  }

  // Checkbox list – item text uses headlineMedium (13)
  Widget _buildCheckboxList(String title, List<Map<String, dynamic>> items, List<String> selectedItems, Function(String) toggle) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionTitle(title),
        ...items.map((item) {
          final name = item['name'] as String? ?? '';
          final count = item['count'] as int? ?? 0;
          final selected = selectedItems.contains(name);
          return InkWell(
            onTap: () => toggle(name),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Row(
                children: [
                  _circleIndicator(selected: selected, size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '$name${count > 0 ? ' ($count)' : ''}',
                      style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                        fontWeight: FontWeight.w400,
                        color: AppColors.textPrimary,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        }),
      ],
    );
  }

  Widget _buildDiscountSection() {
    return _buildCheckboxList(
      'Discount',
      _discountTypes,
      _localParams.dynamicAttributes['discount_type'] ?? [],
      (item) {
        setState(() {
          final list = _localParams.dynamicAttributes['discount_type'] ?? [];
          if (list.contains(item)) {
            list.remove(item);
          } else {
            list.add(item);
          }
          if (list.isEmpty) {
            _localParams.dynamicAttributes.remove('discount_type');
          } else {
            _localParams.dynamicAttributes['discount_type'] = list;
          }
          _scheduleRefresh();
        });
      },
    );
  }

  Widget _expandableTile(String title, List<Widget> children) {
    final expanded = _expandedSections[title] ?? false;
    return Column(
      children: [
        InkWell(
          onTap: () => setState(() => _expandedSections[title] = !expanded),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
            child: Row(
              children: [
                Text(title, style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
                const Spacer(),
                AnimatedRotation(
                  turns: expanded ? 0.5 : 0,
                  duration: const Duration(milliseconds: 250),
                  child: const Icon(Icons.keyboard_arrow_down, size: 20, color: AppColors.textMuted),
                ),
              ],
            ),
          ),
        ),
        AnimatedCrossFade(
          firstChild: const SizedBox.shrink(),
          secondChild: Column(children: children),
          crossFadeState: expanded ? CrossFadeState.showSecond : CrossFadeState.showFirst,
          duration: const Duration(milliseconds: 250),
        ),
      ],
    );
  }

  Widget _buildPriceSection() {
    double start = (_localParams.priceMin ?? _globalMinPrice).clamp(_globalMinPrice, _globalMaxPrice);
    double end   = (_localParams.priceMax ?? _globalMaxPrice).clamp(_globalMinPrice, _globalMaxPrice);
    if (start > end) { final tmp = start; start = end; end = tmp; }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionTitle('Price Range'),
        Row(
          children: [
            Expanded(child: _priceField('Min', _minPriceController)),
            const SizedBox(width: AppSpacing.sm),
            Expanded(child: _priceField('Max', _maxPriceController)),
          ],
        ),
        const SizedBox(height: AppSpacing.md),
        SliderTheme(
          data: SliderTheme.of(context).copyWith(
            activeTrackColor: AppColors.primary,
            inactiveTrackColor: Colors.grey.shade200,
            thumbColor: AppColors.primary,
            overlayColor: AppColors.primary.withOpacity(0.1),
            thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 10),
            trackHeight: 4,
          ),
          child: RangeSlider(
            values: RangeValues(start, end),
            min: _globalMinPrice,
            max: _globalMaxPrice,
            divisions: 100.clamp(0, (_globalMaxPrice - _globalMinPrice).toInt()),
            labels: RangeLabels('ETB ${start.toInt()}', 'ETB ${end.toInt()}'),
            onChanged: (v) {
              _localParams.priceMin = v.start;
              _localParams.priceMax = v.end;
              _minPriceController.text = v.start.toInt().toString();
              _maxPriceController.text = v.end.toInt().toString();
              setState(() {});
            },
            onChangeEnd: (_) => _scheduleRefresh(),
          ),
        ),
        const SizedBox(height: 4),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('ETB ${start.toInt()}', style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AppColors.textMuted)),
            Text('ETB ${end.toInt()}', style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AppColors.textMuted)),
          ],
        ),
      ],
    );
  }

  Widget _priceField(String label, TextEditingController controller) {
    return Container(
      height: 40,
      decoration: BoxDecoration(
        color: AppColors.hoverState,
        borderRadius: BorderRadius.circular(AppShapes.radiusSm),
      ),
      child: TextField(
        keyboardType: TextInputType.number,
        style: Theme.of(context).textTheme.headlineMedium?.copyWith(
          fontWeight: FontWeight.w500,
          color: AppColors.textPrimary,
        ),
        decoration: InputDecoration(
          labelText: label,
          labelStyle: Theme.of(context).textTheme.bodySmall,
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(horizontal: 12),
        ),
        controller: controller,
        onChanged: (value) {
          final val = double.tryParse(value);
          if (val != null) {
            if (label == 'Min') {
              _localParams.priceMin = val.clamp(_globalMinPrice, _globalMaxPrice);
              _minPriceController.text = _localParams.priceMin!.toInt().toString();
            } else {
              _localParams.priceMax = val.clamp(_globalMinPrice, _globalMaxPrice);
              _maxPriceController.text = _localParams.priceMax!.toInt().toString();
            }
            _scheduleRefresh();
          }
        },
      ),
    );
  }

  Widget _buildBottomBar() {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
      decoration: BoxDecoration(
        color: AppColors.cardBackground,
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 12, offset: const Offset(0, -2))],
      ),
      child: Row(
        children: [
          Expanded(
            child: OutlinedButton(
              onPressed: _resetAll,
              style: AppComponentStyles.secondaryButton.copyWith(
                padding: const WidgetStatePropertyAll(EdgeInsets.symmetric(vertical: 14)),
                shape: WidgetStatePropertyAll(RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppShapes.radiusSm))),
              ),
              child: const Text('Reset', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            flex: 2,
            child: ElevatedButton(
              onPressed: _apply,
              style: AppComponentStyles.primaryButton.copyWith(
                padding: const WidgetStatePropertyAll(EdgeInsets.symmetric(vertical: 14)),
                shape: WidgetStatePropertyAll(RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppShapes.radiusSm))),
              ),
              child: const Text('Apply Filters'),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: MediaQuery.of(context).size.height * 0.88,
      decoration: const BoxDecoration(
        color: AppColors.cardBackground,
        borderRadius: BorderRadius.only(topLeft: Radius.circular(28), topRight: Radius.circular(28)),
        boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 24, offset: Offset(0, -6))],
      ),
      child: ClipRRect(
        borderRadius: const BorderRadius.only(topLeft: Radius.circular(28), topRight: Radius.circular(28)),
        child: Scaffold(
          backgroundColor: Colors.transparent,
          body: Column(
            children: [
              Container(
                margin: const EdgeInsets.only(top: 12),
                width: 36, height: 4,
                decoration: BoxDecoration(color: Colors.grey.shade400, borderRadius: BorderRadius.circular(100)),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
                child: Row(
                  children: [
                    Text('Filters', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
                    if (widget.totalCount != null && widget.totalCount! > 0) ...[
                      const SizedBox(width: 8),
                      Text('${_formatNumber(widget.totalCount!)} items', style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AppColors.textMuted)),
                    ],
                    const Spacer(),
                    if (_hasActiveFilters)
                      TextButton(
                        onPressed: _resetAll,
                        style: TextButton.styleFrom(
                          foregroundColor: AppColors.primary,
                          padding: EdgeInsets.zero,
                          minimumSize: Size.zero,
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                        child: Text('Clear All', style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600, color: AppColors.primary)),
                      ),
                  ],
                ),
              ),
              Expanded(
                child: _loading
                    ? const Center(child: CircularProgressIndicator(color: AppColors.primary))
                    : SingleChildScrollView(
                        padding: const EdgeInsets.fromLTRB(20, 8, 20, 80),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (_showCategoryRow && _displayCategories.isNotEmpty) ...[
                              _sectionTitle(_categoryContextId != null ? 'Sub Category' : 'Main Category'),
                              SizedBox(
                                height: 92,   // fixed: increased from 86 to prevent 1px overflow
                                child: ListView.builder(
                                  scrollDirection: Axis.horizontal,
                                  itemCount: _displayCategories.length,
                                  itemBuilder: (context, index) {
                                    final cat = _displayCategories[index];
                                    final id = cat['id'] as int? ?? 0;
                                    final selected = _localParams.categoryIds.contains(id);
                                    return Padding(
                                      padding: const EdgeInsets.only(right: 12),
                                      child: _categoryItem(cat, selected, () => _selectCategory(id)),
                                    );
                                  },
                                ),
                              ),
                              const SizedBox(height: AppSpacing.md),
                            ],
                            if (_brands.isNotEmpty) ...[
                              _buildBrandSection(),
                              const SizedBox(height: AppSpacing.md),
                            ],
                            _buildPriceSection(),
                            const SizedBox(height: AppSpacing.md),
                            if (_ratings.isNotEmpty) ...[
                              _buildRatingSection(),
                              const SizedBox(height: AppSpacing.md),
                            ],
                            if (_deliveryOptions.isNotEmpty) ...[
                              _buildCheckboxList('Delivery', _deliveryOptions, _localParams.deliveryOptions,
                                  (item) => setState(() {
                                        if (_localParams.deliveryOptions.contains(item)) {
                                          _localParams.deliveryOptions.remove(item);
                                        } else {
                                          _localParams.deliveryOptions.add(item);
                                        }
                                        _scheduleRefresh();
                                      })),
                              const SizedBox(height: AppSpacing.md),
                            ],
                            if (_discountTypes.isNotEmpty) ...[
                              _buildDiscountSection(),
                              const SizedBox(height: AppSpacing.md),
                            ],
                            ..._dynamicAttrs.entries.map((entry) {
                              final items = entry.value;
                              return _expandableTile(
                                _displayName(entry.key),
                                items.map((v) {
                                  final name = v['name'] as String? ?? '';
                                  final count = v['count'] as int? ?? 0;
                                  final list = _localParams.dynamicAttributes[entry.key] ?? [];
                                  final selected = list.contains(name);
                                  return _checkboxOption(
                                    label: '$name${count > 0 ? ' ($count)' : ''}',
                                    selected: selected,
                                    onChanged: () => setState(() {
                                      if (selected) {
                                        list.remove(name);
                                      } else {
                                        list.add(name);
                                      }
                                      if (list.isEmpty) {
                                        _localParams.dynamicAttributes.remove(entry.key);
                                      } else {
                                        _localParams.dynamicAttributes[entry.key] = list;
                                      }
                                      _scheduleRefresh();
                                    }),
                                  );
                                }).toList(),
                              );
                            }),
                          ],
                        ),
                      ),
              ),
              _buildBottomBar(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _checkboxOption({required String label, required bool selected, required VoidCallback onChanged}) {
    return InkWell(
      onTap: onChanged,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(
          children: [
            _circleIndicator(selected: selected, size: 18),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                label,
                style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                  fontWeight: FontWeight.w400,
                  color: AppColors.textPrimary,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _formatNumber(int n) {
    if (n >= 1000) return '${(n / 1000).toStringAsFixed(1)}k';
    return n.toString();
  }
}
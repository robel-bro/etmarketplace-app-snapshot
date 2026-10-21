// lib/widgets/active_inline_filter.dart
import 'package:flutter/material.dart';
import 'package:et_marketplace_app/utils/translations.dart';


/// A reusable, context‑aware inline filter bar with expandable rows.
/// All parameters are optional – the widget will silently ignore missing data.
class ActiveInlineFilter extends StatefulWidget {
  final List<String> availableBrands;
  final List<String> selectedBrands;
  final void Function(String brand)? onBrandToggle;

  final List<Map<String, dynamic>> availableCategories;
  final List<int> selectedCategoryIds;
  final void Function(int categoryId)? onCategoryToggle;

  final List<double> availableRatings;
  final double? selectedRatingMin;
  final void Function(double? rating)? onRatingChanged;

  final String? priceMinDisplay;
  final String? priceMaxDisplay;
  final void Function(String? min, String? max)? onPriceChanged;

  final List<String> availableShippingOptions;
  final List<String> selectedShippingOptions;
  final void Function(String option)? onShippingToggle;

  final Map<String, List<String>> availableDynamicAttrs;
  final Map<String, List<String>> selectedDynamicAttrs;
  final void Function(String key, String value)? onDynamicAttrToggle;

  final bool hasActiveFilters;
  final VoidCallback? onClearAll;

  ActiveInlineFilter({
    Key? key,
    this.availableBrands = const [],
    this.selectedBrands = const [],
    this.onBrandToggle,
    this.availableCategories = const [],
    this.selectedCategoryIds = const [],
    this.onCategoryToggle,
    this.availableRatings = const [],
    this.selectedRatingMin,
    this.onRatingChanged,
    this.priceMinDisplay,
    this.priceMaxDisplay,
    this.onPriceChanged,
    this.availableShippingOptions = const [],
    this.selectedShippingOptions = const [],
    this.onShippingToggle,
    this.availableDynamicAttrs = const {},
    this.selectedDynamicAttrs = const {},
    this.onDynamicAttrToggle,
    this.hasActiveFilters = false,
    this.onClearAll,
  }) : super(key: key);

  @override
  State<ActiveInlineFilter> createState() => _ActiveInlineFilterState();
}

class _ActiveInlineFilterState extends State<ActiveInlineFilter> {
  String _expandedFilter = '';

  void _toggleFilterRow(String key) {
    setState(() {
      _expandedFilter = _expandedFilter == key ? '' : key;
    });
  }

  // Safe integer parsing
  int? _safeInt(dynamic value) {
    if (value == null) return null;
    if (value is int) return value;
    if (value is double) return value.toInt();
    if (value is String) {
      final parsed = int.tryParse(value);
      if (parsed == null) {
        debugPrint('[ActiveInlineFilter] Could not parse int from: "$value"');
      }
      return parsed;
    }
    debugPrint('[ActiveInlineFilter] Unexpected type for ID: ${value.runtimeType}');
    return null;
  }

  Widget _filterButton(String label, String key, {String? displayLabel}) {
    final isExpanded = _expandedFilter == key;
    return GestureDetector(
      onTap: () => _toggleFilterRow(key),
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(8),
          boxShadow: [
            BoxShadow(
                color: Colors.black.withOpacity(0.06),
                blurRadius: 8,
                offset: Offset(0, 2)),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(displayLabel ?? label,
                style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: Colors.black)),
            SizedBox(width: 4),
            Icon(isExpanded ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down,
                size: 14, color: Colors.black54),
          ],
        ),
      ),
    );
  }

  Widget _subChip(String label, {bool selected = false, VoidCallback? onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(8),
          boxShadow: [
            BoxShadow(
              color: selected
                  ? Color(0xFFFF4400).withOpacity(0.15)
                  : Colors.black.withOpacity(0.05),
              blurRadius: 8,
              offset: Offset(0, 2),
            ),
          ],
          border: selected
              ? Border(
                  bottom:
                      BorderSide(color: Color(0xFFFF4400), width: 2))
              : null,
        ),
        child: Text(label,
            style: TextStyle(
                fontSize: 13,
                fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                color: selected ? Color(0xFFFF4400) : Colors.black87)),
      ),
    );
  }

  Widget _activeChip(String label, VoidCallback onDelete) {
    return Padding(
      padding: EdgeInsets.only(right: 8),
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(10),
          boxShadow: [
            BoxShadow(
                color: Colors.black.withOpacity(0.04),
                blurRadius: 6,
                offset: Offset(0, 2))
          ],
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Text(label,
              style: TextStyle(
                  fontSize: 13,
                  color: Colors.black,
                  fontWeight: FontWeight.w500)),
          SizedBox(width: 8),
          GestureDetector(
              onTap: onDelete,
              child:
                  Icon(Icons.close, size: 16, color: Colors.black54)),
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // ---- Expandable filter buttons ----
        SizedBox(
          height: 42,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: EdgeInsets.symmetric(horizontal: 16),
            children: [
              _filterButton('Category', 'category',
                  displayLabel: _categoryLabel),
              SizedBox(width: 8),
              _filterButton('Brand', 'brand', displayLabel: _brandLabel),
              SizedBox(width: 8),
              _filterButton('Rating', 'rating', displayLabel: _ratingLabel),
              SizedBox(width: 8),
              _filterButton('Price', 'price', displayLabel: _priceLabel),
              SizedBox(width: 8),
              _filterButton('Shipping', 'shipping',
                  displayLabel: _shippingLabel),
              ...widget.availableDynamicAttrs.keys.map((key) => Padding(
                    padding: EdgeInsets.only(left: 8),
                    child: _filterButton(key, 'attr_$key', displayLabel: key),
                  )),
              if (widget.hasActiveFilters && widget.onClearAll != null)
                Padding(
                  padding: EdgeInsets.only(left: 8),
                  child: GestureDetector(
                    onTap: widget.onClearAll,
                    child: Container(
                      padding: EdgeInsets.symmetric(
                          horizontal: 14, vertical: 8),
                      child: Text('Clear all',
                          style: TextStyle(
                              fontSize: 13,
                              color: Color(0xFFFF4400),
                              fontWeight: FontWeight.w500)),
                    ),
                  ),
                ),
            ],
          ),
        ),

        // ---- Expanded sub‑filter panel ----
        if (_expandedFilter.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: SizedBox(
              height: 38,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                children: _buildSubFilterPanel(),
              ),
            ),
          ),

        // ---- Active filter chips ----
        if (widget.hasActiveFilters)
          Container(
            height: 52,
            padding:
                const EdgeInsets.only(left: 16, right: 16, top: 6, bottom: 4),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(children: _buildActiveFilterChips()),
            ),
          ),
      ],
    );
  }

  List<Widget> _buildSubFilterPanel() {
    switch (_expandedFilter) {
      case 'category':
        return widget.availableCategories.map((c) {
          final id = _safeInt(c['id']);
          if (id == null) return const SizedBox.shrink();
          final selected = widget.selectedCategoryIds.contains(id);
          final name = c['name']?.toString() ?? '';
          if (name.isEmpty) return const SizedBox.shrink();
          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: _subChip(name,
                selected: selected,
                onTap: () => widget.onCategoryToggle?.call(id)),
          );
        }).toList();
      case 'brand':
        return widget.availableBrands.map((b) {
          final selected = widget.selectedBrands.contains(b);
          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: _subChip(b,
                selected: selected,
                onTap: () => widget.onBrandToggle?.call(b)),
          );
        }).toList();
      case 'rating':
        return widget.availableRatings.map((r) {
          final selected = widget.selectedRatingMin == r;
          return Padding(
            padding: EdgeInsets.only(right: 8),
            child: _subChip('${r.toInt()}★ & up',
                selected: selected,
                onTap: () =>
                    widget.onRatingChanged?.call(selected ? null : r)),
          );
        }).toList();
      case 'price':
        return [
          SizedBox(
            width: 80,
            child: TextField(
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                  hintText: 'Min',
                  border: OutlineInputBorder(),
                  contentPadding:
                      EdgeInsets.symmetric(horizontal: 8, vertical: 4)),
              onChanged: (v) => widget.onPriceChanged
                  ?.call(v.isNotEmpty ? v : null, widget.priceMaxDisplay),
            ),
          ),
          SizedBox(width: 8),
          Text('–'),
          SizedBox(width: 8),
          SizedBox(
            width: 80,
            child: TextField(
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                  hintText: 'Max',
                  border: OutlineInputBorder(),
                  contentPadding:
                      EdgeInsets.symmetric(horizontal: 8, vertical: 4)),
              onChanged: (v) => widget.onPriceChanged
                  ?.call(widget.priceMinDisplay, v.isNotEmpty ? v : null),
            ),
          ),
          SizedBox(width: 8),
          TextButton(
            onPressed: () => widget.onPriceChanged?.call(null, null),
            child: Text('Reset'),
          ),
        ];
      case 'shipping':
        return widget.availableShippingOptions.map((opt) {
          final selected = widget.selectedShippingOptions.contains(opt);
          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: _subChip(opt,
                selected: selected,
                onTap: () => widget.onShippingToggle?.call(opt)),
          );
        }).toList();
      default:
        if (_expandedFilter.startsWith('attr_')) {
          final key = _expandedFilter.substring(5);
          final values = widget.availableDynamicAttrs[key] ?? [];
          final selectedVals = widget.selectedDynamicAttrs[key] ?? [];
          return values.map((v) {
            final selected = selectedVals.contains(v);
            return Padding(
              padding: const EdgeInsets.only(right: 8),
              child: _subChip(v,
                  selected: selected,
                  onTap: () => widget.onDynamicAttrToggle?.call(key, v)),
            );
          }).toList();
        }
        return [];
    }
  }

  List<Widget> _buildActiveFilterChips() {
    final chips = <Widget>[];
    for (final b in widget.selectedBrands) {
      chips.add(_activeChip(b, () => widget.onBrandToggle?.call(b)));
    }
    for (final id in widget.selectedCategoryIds) {
      final cat = widget.availableCategories.firstWhere(
        (c) => _safeInt(c['id']) == id,
        orElse: () => {'name': id.toString()},
      );
      chips.add(_activeChip(cat['name']?.toString() ?? id.toString(),
          () => widget.onCategoryToggle?.call(id)));
    }
    if (widget.selectedRatingMin != null) {
      chips.add(_activeChip('${widget.selectedRatingMin!.toInt()}★ & up',
          () => widget.onRatingChanged?.call(null)));
    }
    if (widget.priceMinDisplay != null || widget.priceMaxDisplay != null) {
      chips.add(_activeChip(
          'ETB ${widget.priceMinDisplay ?? '0'} – ${widget.priceMaxDisplay ?? '∞'}',
          () => widget.onPriceChanged?.call(null, null)));
    }
    for (final opt in widget.selectedShippingOptions) {
      chips.add(
          _activeChip(opt, () => widget.onShippingToggle?.call(opt)));
    }
    widget.selectedDynamicAttrs.forEach((key, values) {
      for (final v in values) {
        chips.add(_activeChip(
            '$key: $v', () => widget.onDynamicAttrToggle?.call(key, v)));
      }
    });
    return chips;
  }

  // Display helpers
  String get _categoryLabel {
    if (widget.selectedCategoryIds.isEmpty) return 'Category';
    final count = widget.selectedCategoryIds.length;
    if (count == 1) {
      final cat = widget.availableCategories.firstWhere(
          (c) => _safeInt(c['id']) == widget.selectedCategoryIds.first,
          orElse: () => {'name': 'Category'});
      return cat['name']?.toString() ?? 'Category';
    }
    return 'Category ($count)';
  }

  String get _brandLabel {
    if (widget.selectedBrands.isEmpty) return 'Brand';
    return 'Brand (${widget.selectedBrands.length})';
  }

  String get _ratingLabel {
    if (widget.selectedRatingMin == null) return 'Rating';
    return '${widget.selectedRatingMin!.toInt()}★+';
  }

  String get _priceLabel {
    if (widget.priceMinDisplay == null && widget.priceMaxDisplay == null) {
      return 'Price';
    }
    return 'ETB ${widget.priceMinDisplay ?? '0'} – ${widget.priceMaxDisplay ?? '∞'}';
  }

  String get _shippingLabel {
    if (widget.selectedShippingOptions.isEmpty) return 'Shipping';
    return widget.selectedShippingOptions.join(', ');
  }
}
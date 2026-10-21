// lib/screens/create_package_screen.dart (hardened – weight/dimensions required for new products, delivery subsidy aligned)
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:dio/dio.dart';
import '../api/client.dart';
import '../utils/url_utils.dart';
import '../theme/app_theme.dart';
import '../l10n/app_localizations.dart';

class PositiveDecimalInputFormatter extends TextInputFormatter {
  final double? maxValue;
  PositiveDecimalInputFormatter({this.maxValue});

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final newText = newValue.text;
    if (newText.isEmpty) return newValue;
    if (newText.contains('-')) return oldValue;
    if (maxValue != null) {
      final parsed = double.tryParse(newText);
      if (parsed != null && parsed > maxValue!) return oldValue;
    }
    return newValue;
  }
}

class CreatePackageScreen extends StatefulWidget {
  final Map<String, dynamic>? packageData;
  const CreatePackageScreen({Key? key, this.packageData}) : super(key: key);
  @override
  State<CreatePackageScreen> createState() => _CreatePackageScreenState();
}

class _CreatePackageScreenState extends State<CreatePackageScreen> {
  final _formKey = GlobalKey<FormState>();
  final ImagePicker _picker = ImagePicker();

  bool _fromExisting = true;

  final _nameCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  final _priceCtrl = TextEditingController();
  final _stockCtrl = TextEditingController();
  final _discountValueCtrl = TextEditingController();

  bool _sellerPaysDelivery = false;
  String _deliverySubsidyType = 'full';
  final _deliverySubsidyValueCtrl = TextEditingController();

  String _discountType = 'percentage';
  String _status = 'active';

  List<XFile> _newPkgImages = [];
  List<String> _existingImageUrls = [];
  List<int> _existingImageIds = [];

  List<XFile> _newPkgVideos = [];
  List<String> _existingVideoUrls = [];
  List<int> _existingVideoIds = [];

  List<Map<String, dynamic>> _mainCategories = [];
  List<Map<String, dynamic>> _subCategories = [];
  int? _selectedMainCategoryId;
  int? _selectedSubCategoryId;
  bool _isLoadingCategories = true;

  List<Map<String, dynamic>> _existingProducts = [];
  Set<int> _selectedProductIds = {};
  bool _isLoadingProducts = true;

  Map<int, Map<String, String>> _selectedProductVariants = {};

  List<_InlineProduct> _inlineProducts = [];

  bool _isSubmitting = false;

  static const int _UNLIMITED_STOCK = 999999;

  int? parseVariantStock(dynamic stockValue) {
    if (stockValue == null) return null;
    if (stockValue is int) return stockValue;
    if (stockValue is double) return stockValue.toInt();
    if (stockValue is String) {
      final parsed = int.tryParse(stockValue);
      return parsed;
    }
    return null;
  }

  double parsePrice(dynamic priceValue) {
    if (priceValue == null) return 0.0;
    if (priceValue is num) return priceValue.toDouble();
    if (priceValue is String) {
      final parsed = double.tryParse(priceValue);
      return parsed ?? 0.0;
    }
    return 0.0;
  }

  bool hasSelectableVariants(Map<String, dynamic> product) {
    final variants = product['variants'];
    if (variants == null || variants is! List || variants.isEmpty) return false;
    return variants.any((v) {
      if (v is! Map) return false;
      final attrs = v['attributes'];
      return attrs is Map && attrs.isNotEmpty;
    });
  }

  String computeStockDisplay(Map<String, dynamic> product, Map<String, String>? selectedVariant) {
    if (selectedVariant != null && product['variants'] is List) {
      final variants = product['variants'] as List;
      for (final v in variants) {
        if (v is! Map) continue;
        final attrs = v['attributes'];
        if (attrs is Map && selectedVariant.entries.every((e) => attrs[e.key] == e.value)) {
          if (v['unlimited_stock'] == true || v['stock'] == null || v['stock'] == '') {
            return 'Unlimited';
          }
          if (v.containsKey('stock')) {
            final stockVal = parseVariantStock(v['stock']);
            return stockVal != null ? stockVal.toString() : (product['stock_display']?.toString() ?? '0');
          }
          return product['stock_display']?.toString() ?? '0';
        }
      }
      return '0';
    }
    if (product['available_stock'] == null || product['available_stock'] == '') {
      return 'Unlimited';
    }
    return product['available_stock'].toString();
  }

  String formatCurrency(double value) {
    final parts = value.toStringAsFixed(2).split('.');
    final integerPart = parts[0];
    final decimalPart = parts[1];
    final formattedInteger = integerPart.replaceAllMapped(
      RegExp(r'(\d)(?=(\d{3})+(?!\d))'),
      (match) => '${match[1]},',
    );
    return '$formattedInteger.$decimalPart';
  }

  int? _getProductStockForPackage(Map<String, dynamic> product, int productId) {
    final variantAttrs = _selectedProductVariants[productId];
    if (variantAttrs != null &&
        product['variants'] is List &&
        (product['variants'] as List).isNotEmpty) {
      final variant = _findVariantForSelection(
        List<Map<String, dynamic>>.from(product['variants']),
        variantAttrs,
      );
      if (variant != null) {
        if (variant['unlimited_stock'] == true ||
            variant['stock'] == null ||
            variant['stock'] == '') {
          return null;
        }
        return parseVariantStock(variant['stock']);
      }
      return 0;
    }
    final available = product['available_stock'];
    if (available == null || available == '') return null;
    if (available is String) {
      final parsed = int.tryParse(available);
      return parsed;
    }
    return available is int ? available : null;
  }

  int get _maxPossibleStock {
    if (!_fromExisting || _selectedProductIds.isEmpty) return _UNLIMITED_STOCK;
    int? minFiniteStock;
    bool hasUnlimited = false;
    for (final pid in _selectedProductIds) {
      final product = _existingProducts.firstWhereOrNull((p) => p['id'] == pid);
      if (product == null) continue;
      final stock = _getProductStockForPackage(product, pid);
      if (stock == null) {
        hasUnlimited = true;
      } else {
        if (minFiniteStock == null || stock < minFiniteStock) {
          minFiniteStock = stock;
        }
      }
    }
    if (minFiniteStock == null) {
      return _UNLIMITED_STOCK;
    }
    return minFiniteStock;
  }

  List<String> get _limitingProducts {
    if (!_fromExisting || _selectedProductIds.isEmpty) return [];
    final max = _maxPossibleStock;
    if (max == _UNLIMITED_STOCK) return [];
    final List<String> limiters = [];
    for (final pid in _selectedProductIds) {
      final product = _existingProducts.firstWhereOrNull((p) => p['id'] == pid);
      if (product == null) continue;
      final stock = _getProductStockForPackage(product, pid);
      if (stock != null && stock == max) {
        String displayName = product['title'] ?? 'Unknown';
        final variantAttrs = _selectedProductVariants[pid];
        if (variantAttrs != null && variantAttrs.isNotEmpty) {
          displayName += ' (${variantAttrs.entries.map((e) => '${e.key}: ${e.value}').join(', ')})';
        }
        limiters.add('$displayName ($stock left)');
      }
    }
    return limiters;
  }

  void _autoCapStock() {
    final max = _maxPossibleStock;
    if (max == _UNLIMITED_STOCK) return;
    final current = int.tryParse(_stockCtrl.text.trim()) ?? 0;
    if (current > max) {
      _stockCtrl.text = max.toString();
      _showSnack(
        AppLocalizations.of(context).translate('stock_capped').replaceAll('{max}', max.toString()),
        AppColors.info,
      );
    }
  }

  void _onProductSelectionChanged() {
    setState(() {
      _autoCapStock();
    });
  }

  bool get _canSubmit {
    if (_fromExisting) return _selectedProductIds.length >= 2;
    return _inlineProducts.length >= 2;
  }

  double get _totalProductPrice {
    double total = 0.0;
    if (_fromExisting) {
      for (final pid in _selectedProductIds) {
        final product = _existingProducts.firstWhere(
          (p) => p['id'] == pid,
          orElse: () => {'price': 0.0},
        );
        total += parsePrice(product['price']);
      }
    } else {
      for (final p in _inlineProducts) {
        total += double.tryParse(p.priceCtrl.text) ?? 0.0;
      }
    }
    return total;
  }

  @override
  void initState() {
    super.initState();
    _loadCategories();
    _loadProducts();
    _inlineProducts = [_InlineProduct(), _InlineProduct()];

    if (widget.packageData != null) {
      _prefillFromPackage(widget.packageData!);
    }
  }

  void _prefillFromPackage(Map<String, dynamic> pkg) {
    _nameCtrl.text = pkg['name'] ?? '';
    _descCtrl.text = pkg['description'] ?? '';
    _priceCtrl.text = pkg['price']?.toString() ?? '';
    _stockCtrl.text = pkg['stock']?.toString() ?? '';
    _status = pkg['status'] ?? 'active';
    if (pkg['discount_type'] != null) {
      _discountType = pkg['discount_type'];
      _discountValueCtrl.text = pkg['discount_value']?.toString() ?? '';
    }
    _sellerPaysDelivery = pkg['seller_pays_shipping'] ?? false;
    final rawSubsidy = pkg['shipping_subsidy_type'];
    if (rawSubsidy == 'percent' || rawSubsidy == 'percentage') {
      _deliverySubsidyType = 'percent';
    } else {
      _deliverySubsidyType = 'full';
    }
    _deliverySubsidyValueCtrl.text = pkg['shipping_subsidy_value']?.toString() ?? '';

    if (pkg['categories'] != null && (pkg['categories'] as List).isNotEmpty) {
      final cat = pkg['categories'][0];
      if (cat['parent_id'] != null) {
        _selectedMainCategoryId = cat['parent_id'];
        _selectedSubCategoryId = cat['id'];
      } else {
        _selectedMainCategoryId = cat['id'];
        _selectedSubCategoryId = null;
      }
      if (_selectedMainCategoryId != null) {
        _loadSubCategories(_selectedMainCategoryId!);
      }
    }

    if (pkg['products'] != null && (pkg['products'] as List).isNotEmpty) {
      final productList = pkg['products'] as List;
      _selectedProductIds = Set.from(productList.map((p) => p['id']));
      for (final p in productList) {
        if (p['variant_attributes'] is Map && (p['variant_attributes'] as Map).isNotEmpty) {
          _selectedProductVariants[p['id']] = Map<String, String>.from(p['variant_attributes']);
        }
      }
      _fromExisting = true;
    }

    if (pkg['image_urls'] != null) {
      _existingImageUrls = List<String>.from(pkg['image_urls']);
    }
    if (pkg['image_ids'] != null) {
      _existingImageIds = List<int>.from(pkg['image_ids']);
    }
    if (pkg['video_urls'] != null) {
      _existingVideoUrls = List<String>.from(pkg['video_urls']);
    }
    if (pkg['video_ids'] != null) {
      _existingVideoIds = List<int>.from(pkg['video_ids']);
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _onProductSelectionChanged();
    });
    setState(() {});
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _descCtrl.dispose();
    _priceCtrl.dispose();
    _stockCtrl.dispose();
    _discountValueCtrl.dispose();
    _deliverySubsidyValueCtrl.dispose();
    for (final p in _inlineProducts) {
      p.titleCtrl.dispose();
      p.descCtrl.dispose();
      p.priceCtrl.dispose();
      p.stockCtrl.dispose();
      p.weightCtrl.dispose();
      p.lengthCtrl.dispose();
      p.widthCtrl.dispose();
      p.heightCtrl.dispose();
    }
    super.dispose();
  }

  Future<void> _loadCategories() async {
    try {
      final response = await ApiClient.instance.get('/categories');
      final dynamic raw = response.data;
      final List data = raw is List ? raw : (raw['data'] is List ? raw['data'] as List : []);
      final List<Map<String, dynamic>> all = data.map((c) {
        return {
          'id': c['id'],
          'name': c['name'],
          'parent_id': c['parent_id'],
        };
      }).toList();
      final mains = all.where((c) => c['parent_id'] == null).toList();
      if (mounted) {
        setState(() {
          _mainCategories = mains;
          _isLoadingCategories = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _isLoadingCategories = false);
    }
  }

  Future<void> _loadSubCategories(int mainId) async {
    try {
      final response = await ApiClient.instance.get('/categories');
      final dynamic raw = response.data;
      final List data = raw is List ? raw : (raw['data'] is List ? raw['data'] as List : []);
      final List<Map<String, dynamic>> all = data.map((c) {
        return {
          'id': c['id'],
          'name': c['name'],
          'parent_id': c['parent_id'],
        };
      }).toList();
      final subs = all.where((c) => c['parent_id'] == mainId).toList();
      if (mounted) setState(() => _subCategories = subs);
    } catch (_) {}
  }

  Future<void> _loadProducts() async {
    try {
      final response = await ApiClient.instance.get('/products?vendor=me');
      final dynamic raw = response.data;
      final List data = raw is List ? raw : (raw['data'] is List ? raw['data'] as List : []);
      if (mounted) {
        setState(() {
          _existingProducts = data.map((p) {
            final Map<String, dynamic> productMap = Map<String, dynamic>.from(p as Map);
            return {
              'id': productMap['id'],
              'title': productMap['title'] ?? '',
              'price': productMap['effective_price'] ?? productMap['price'] ?? 0,
              'stock': productMap['stock'],
              'stock_display': productMap['stock_display'] ?? '0',
              'available_stock': productMap['available_stock'],
              'has_variants': productMap['has_variants'] ?? false,
              'variants': (productMap['variants'] as List?) ?? [],
              'bulk_enabled': productMap['bulk_enabled'] ?? false,
              'orderable': productMap['orderable'] ?? true,
              'unavailable_reason': productMap['unavailable_reason'],
              'image_url': (productMap['image_urls'] is List && (productMap['image_urls'] as List).isNotEmpty)
                  ? productMap['image_urls'][0]
                  : 'https://via.placeholder.com/150?text=No+Image',
            };
          }).toList();
          _isLoadingProducts = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _isLoadingProducts = false);
    }
  }

  Future<void> _pickImagesForProduct(int index) async {
    final List<XFile> files = await _picker.pickMultiImage(imageQuality: 85, maxWidth: 1200) ?? [];
    if (files.isNotEmpty) {
      final current = _inlineProducts[index].images;
      if (current.length + files.length > 4) {
        _showSnack('Maximum 4 images per product', AppColors.error);
        return;
      }
      setState(() {
        _inlineProducts[index].images.addAll(files);
      });
    }
  }

  void _removeProductImage(int productIndex, int imageIndex) {
    setState(() {
      _inlineProducts[productIndex].images.removeAt(imageIndex);
    });
  }

  void _addInlineProduct() => setState(() => _inlineProducts.add(_InlineProduct()));

  void _removeInlineProduct(int index) {
    final l10n = AppLocalizations.of(context);
    if (_inlineProducts.length <= 2) {
      _showSnack(l10n.translate('need_at_least_two_products'), AppColors.error);
      return;
    }
    setState(() => _inlineProducts.removeAt(index));
  }

  Future<void> _pickPackageImages() async {
    final int remaining = 3 - _newPkgImages.length - _existingImageUrls.length;
    if (remaining <= 0) {
      _showSnack('Maximum 3 package images', AppColors.error);
      return;
    }
    try {
      final List<XFile>? files = await _picker.pickMultiImage(imageQuality: 85, maxWidth: 1200);
      if (files != null && files.isNotEmpty) {
        final toAdd = files.take(remaining).toList();
        setState(() => _newPkgImages.addAll(toAdd));
        return;
      }
    } catch (_) {}
    final XFile? file = await _picker.pickImage(source: ImageSource.gallery, imageQuality: 85, maxWidth: 1200);
    if (file != null) {
      setState(() => _newPkgImages.add(file));
    }
  }

  void _removeNewImage(int index) => setState(() => _newPkgImages.removeAt(index));

  Future<void> _pickPackageVideo() async {
    final l10n = AppLocalizations.of(context);
    if (_newPkgVideos.length + _existingVideoUrls.length >= 1) {
      _showSnack('Maximum 1 package video', AppColors.error);
      return;
    }
    final XFile? file = await _picker.pickVideo(source: ImageSource.gallery);
    if (file != null) {
      final size = await file.length();
      if (size > 50 * 1024 * 1024) {
        _showSnack(l10n.translate('video_too_large'), AppColors.error);
        return;
      }
      setState(() => _newPkgVideos.add(file));
    }
  }

  void _removeNewVideo(int index) => setState(() => _newPkgVideos.removeAt(index));

  int get _totalProducts => _fromExisting ? _selectedProductIds.length : _inlineProducts.length;
  int? get _selectedCategoryId => _selectedSubCategoryId ?? _selectedMainCategoryId;

  Map<String, dynamic>? _findVariantForSelection(
      List<Map<String, dynamic>> variants, Map<String, String> selection) {
    if (variants.isEmpty || selection.isEmpty) return null;
    for (final v in variants) {
      final attrs = v['attributes'] as Map<String, dynamic>? ?? {};
      if (selection.entries.every((e) => attrs[e.key] == e.value)) return v;
    }
    return null;
  }

  List<String> _allowedValuesForSelection(
      List<Map<String, dynamic>> variants, Map<String, String> selection, String key) {
    final available = variants.where((v) {
      final attrs = v['attributes'] as Map<String, dynamic>? ?? {};
      return selection.entries.every((e) => e.key == key || e.value.isEmpty || attrs[e.key] == e.value);
    }).toList();
    return available
        .map((v) => (v['attributes'] as Map<String, dynamic>?)?[key]?.toString() ?? '')
        .where((v) => v.isNotEmpty)
        .toSet()
        .toList();
  }

  void _openVariantSelection(Map<String, dynamic> product) {
    final variantsRaw = (product['variants'] as List<dynamic>?) ?? [];
    final variants = variantsRaw.cast<Map<String, dynamic>>();
    if (!hasSelectableVariants(product)) {
      setState(() {
        if (_selectedProductIds.contains(product['id'])) {
          _selectedProductIds.remove(product['id']);
          _selectedProductVariants.remove(product['id']);
        } else {
          _selectedProductIds.add(product['id']);
        }
        _onProductSelectionChanged();
      });
      return;
    }

    final variantKeys = <String>[];
    for (final v in variants) {
      final attrs = v['attributes'] as Map<String, dynamic>? ?? {};
      for (final entry in attrs.entries) {
        if (entry.value.toString().isNotEmpty && !variantKeys.contains(entry.key)) {
          variantKeys.add(entry.key);
        }
      }
    }
    if (variantKeys.isEmpty) return;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        Map<String, String> localVariant = {};
        List<String> localOrder = [];
        return StatefulBuilder(
          builder: (context, setSheetState) {
            final allMap = <String, List<String>>{};
            for (final key in variantKeys) {
              allMap[key] = variants
                  .map((v) => (v['attributes'] as Map<String, dynamic>?)?[key]?.toString() ?? '')
                  .where((v) => v.isNotEmpty)
                  .toSet()
                  .toList();
            }

            final available = variants.where((v) {
              final attrs = v['attributes'] as Map<String, dynamic>? ?? {};
              return localVariant.entries.every(
                (e) => e.value.isEmpty || attrs[e.key] == e.value);
            }).toList();
            final allowedMap = <String, List<String>>{};
            for (final key in variantKeys) {
              allowedMap[key] = available
                  .map((v) => (v['attributes'] as Map<String, dynamic>?)?[key]?.toString() ?? '')
                  .where((v) => v.isNotEmpty)
                  .toSet()
                  .toList();
            }

            final active = _findVariantForSelection(variants, localVariant);
            final complete = active != null;
            final displayPrice = complete ? parsePrice(active!['price']) : 0.0;
            final displayStock = complete
                ? (active!['unlimited_stock'] == true || active['stock'] == null)
                    ? null
                    : parseVariantStock(active['stock'])
                : null;

            return Container(
              constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.8),
              decoration: const BoxDecoration(
                color: AppColors.cardBackground,
                borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
              ),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.grey.shade400, borderRadius: BorderRadius.circular(2))),
                    const SizedBox(height: 16),
                    Text('Select variant for ${product['title']}', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
                    const SizedBox(height: 16),
                    ...variantKeys.map((key) {
                      final allValues = allMap[key] ?? [];
                      final allowed = allowedMap[key] ?? [];
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(key, style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
                          const SizedBox(height: 8),
                          SingleChildScrollView(
                            scrollDirection: Axis.horizontal,
                            child: Row(
                              children: allValues.map((val) {
                                final isSelected = localVariant[key] == val;
                                final isAvailable = allowed.contains(val);
                                return GestureDetector(
                                  onTap: isAvailable
                                      ? () => setSheetState(() => _handleOptionTap(localVariant, localOrder, key, val, variantKeys, variants))
                                      : null,
                                  child: Container(
                                    margin: const EdgeInsets.only(right: 8),
                                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                                    decoration: BoxDecoration(
                                      color: !isAvailable ? Colors.grey.shade100 : isSelected ? Colors.blue.shade50 : AppColors.cardBackground,
                                      borderRadius: BorderRadius.circular(AppShapes.radiusSm),
                                      border: Border.all(
                                        color: !isAvailable ? Colors.grey.shade200 : isSelected ? Colors.blue.shade400 : AppColors.borderLight,
                                      ),
                                    ),
                                    child: Text(
                                      val,
                                      style: TextStyle(
                                        fontSize: 14,
                                        fontWeight: FontWeight.w500,
                                        color: !isAvailable
                                            ? Colors.grey.shade400
                                            : isSelected
                                                ? Colors.blue.shade800
                                                : AppColors.textPrimary,
                                      ),
                                    ),
                                  ),
                                );
                              }).toList(),
                            ),
                          ),
                        ]),
                      );
                    }).toList(),
                    const SizedBox(height: 8),
                    if (complete) ...[
                      Text('ETB ${formatCurrency(displayPrice)}', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: AppColors.primary)),
                      const SizedBox(height: 8),
                      Text(
                        'Stock: ${displayStock == null ? 'Unlimited' : displayStock}',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AppColors.textMuted),
                      ),
                    ] else
                      Text(AppLocalizations.of(context).translate('select_all_options'), style: const TextStyle(color: AppColors.textMuted)),
                    const SizedBox(height: 20),
                    Row(
                      children: [
                        Expanded(
                          child: ElevatedButton(
                            onPressed: () => Navigator.pop(context),
                            child: Text(AppLocalizations.of(context).translate('cancel')),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.grey.shade300,
                              foregroundColor: AppColors.textPrimary,
                              elevation: 0,
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppShapes.radiusSm)),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: ElevatedButton(
                            onPressed: complete
                                ? () {
                                    Navigator.pop(context, active!['attributes']);
                                  }
                                : null,
                            child: Text('Confirm'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: complete ? AppColors.primary : Colors.grey.shade300,
                              foregroundColor: complete ? Colors.white : AppColors.textMuted,
                              elevation: 2,
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppShapes.radiusSm)),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                  ],
                ),
              ),
            );
          },
        );
      },
    ).then((selectedVariant) {
      if (selectedVariant != null && mounted) {
        setState(() {
          _selectedProductIds.add(product['id']);
          _selectedProductVariants[product['id']] = Map<String, String>.from(selectedVariant);
          _onProductSelectionChanged();
        });
      }
    });
  }

  void _handleOptionTap(Map<String, String> localVariant, List<String> localOrder,
      String key, String value, List<String> variantKeys, List<Map<String, dynamic>> variants) {
    if (localVariant[key] == value) {
      final idx = localOrder.indexOf(key);
      if (idx != -1) {
        final keysToRemove = localOrder.sublist(idx);
        keysToRemove.forEach((k) => localVariant.remove(k));
        localOrder.removeRange(idx, localOrder.length);
      }
    } else {
      if (localVariant.containsKey(key)) {
        final idx = localOrder.indexOf(key);
        if (idx != -1) {
          final keysToRemove = localOrder.sublist(idx);
          keysToRemove.forEach((k) => localVariant.remove(k));
          localOrder.removeRange(idx, localOrder.length);
        }
      }
      localVariant[key] = value;
      localOrder.remove(key);
      localOrder.add(key);
      for (final k in variantKeys) {
        if (localVariant[k] != null && localVariant[k]!.isNotEmpty) {
          final newAllowed = _allowedValuesForSelection(variants, localVariant, k);
          if (!newAllowed.contains(localVariant[k])) {
            localVariant.remove(k);
            localOrder.remove(k);
          }
        }
      }
    }
  }

  Future<void> _submit() async {
    final l10n = AppLocalizations.of(context);
    if (!_formKey.currentState!.validate()) return;
    _formKey.currentState!.save();

    if (_discountValueCtrl.text.isNotEmpty) {
      final val = double.tryParse(_discountValueCtrl.text.trim());
      if (val == null || val <= 0) {
        _showSnack('Discount value must be greater than 0', AppColors.error);
        return;
      }
      if (_discountType == 'percentage' && val > 100) {
        _showSnack('Percentage discount cannot exceed 100%', AppColors.error);
        return;
      }
    }

    if (_sellerPaysDelivery && _deliverySubsidyType == 'percent') {
      final val = double.tryParse(_deliverySubsidyValueCtrl.text.trim());
      if (val == null || val <= 0 || val > 100) {
        _showSnack('Shipping subsidy percentage must be between 1 and 100', AppColors.error);
        return;
      }
    }

    if (_fromExisting && _selectedProductIds.isEmpty) {
      _showSnack(l10n.translate('select_at_least_one_product'), AppColors.error);
      return;
    }
    if (!_fromExisting) {
      for (final p in _inlineProducts) {
        if (p.titleCtrl.text.trim().isEmpty || p.priceCtrl.text.trim().isEmpty) {
          _showSnack(l10n.translate('all_product_fields_required'), AppColors.error);
          return;
        }
        // ★ Validate weight & dimensions
        if (p.weightCtrl.text.trim().isEmpty || double.tryParse(p.weightCtrl.text.trim()) == null || double.tryParse(p.weightCtrl.text.trim())! <= 0) {
          _showSnack('Weight is required for all products.', AppColors.error);
          return;
        }
        if (p.lengthCtrl.text.trim().isEmpty || double.tryParse(p.lengthCtrl.text.trim()) == null || double.tryParse(p.lengthCtrl.text.trim())! <= 0 ||
            p.widthCtrl.text.trim().isEmpty || double.tryParse(p.widthCtrl.text.trim()) == null || double.tryParse(p.widthCtrl.text.trim())! <= 0 ||
            p.heightCtrl.text.trim().isEmpty || double.tryParse(p.heightCtrl.text.trim()) == null || double.tryParse(p.heightCtrl.text.trim())! <= 0) {
          _showSnack('Dimensions are required for all products.', AppColors.error);
          return;
        }
      }
    }

    if (_fromExisting) {
      for (final pid in _selectedProductIds) {
        final product = _existingProducts.firstWhereOrNull((p) => p['id'] == pid);
        if (product != null && hasSelectableVariants(product) && _selectedProductVariants[pid] == null) {
          _showSnack('Please select a variant for "${product['title']}".', AppColors.error);
          return;
        }
      }
    }

    _autoCapStock();

    setState(() => _isSubmitting = true);
    try {
      final List<Map<String, dynamic>> productsData = [];

      if (_fromExisting) {
        if (_selectedProductIds.length < 2) {
          _showSnack('Please select at least 2 products', AppColors.error);
          setState(() => _isSubmitting = false);
          return;
        }
        for (final productId in _selectedProductIds) {
          productsData.add({
            'product_id': productId,
            'variant_attributes': _selectedProductVariants[productId] ?? {},
          });
        }
      } else {
        if (_inlineProducts.length < 2) {
          _showSnack('Please add at least 2 products', AppColors.error);
          setState(() => _isSubmitting = false);
          return;
        }
        for (final product in _inlineProducts) {
          final fields = <String, dynamic>{
            'product[title]': product.titleCtrl.text.trim(),
            'product[description]': product.descCtrl.text.trim(),
            'product[price]': product.priceCtrl.text.trim(),
            'product[status]': 'active',
            'product[stock]': product.stockCtrl.text.trim().isEmpty ? '0' : product.stockCtrl.text.trim(),
            'product[weight_kg]': product.weightCtrl.text.trim(),
            'product[length_cm]': product.lengthCtrl.text.trim(),
            'product[width_cm]': product.widthCtrl.text.trim(),
            'product[height_cm]': product.heightCtrl.text.trim(),
          };

          if (product.images.isNotEmpty) {
            final List<MultipartFile> imgParts = [];
            for (final img in product.images) {
              if (kIsWeb) {
                final bytes = await img.readAsBytes();
                imgParts.add(MultipartFile.fromBytes(bytes, filename: img.name));
              } else {
                imgParts.add(await MultipartFile.fromFile(img.path, filename: img.name));
              }
            }
            fields['product[images][]'] = imgParts;
          }
          final res = await ApiClient.instance.post('/products', data: FormData.fromMap(fields));
          final newProductId = res.data['id'];

          productsData.add({
            'product_id': newProductId,
            'variant_attributes': <String, String>{},
          });
        }
      }

      final pkgFields = <String, dynamic>{
        'package[name]': _nameCtrl.text.trim(),
        'package[description]': _descCtrl.text.trim(),
        'package[price]': _priceCtrl.text.trim(),
        'package[status]': _status,
      };
      if (_stockCtrl.text.trim().isNotEmpty) {
        pkgFields['package[stock]'] = _stockCtrl.text.trim();
      }
      pkgFields['package[products]'] = jsonEncode(productsData);

      if (_selectedCategoryId != null) pkgFields['package[category_ids][]'] = _selectedCategoryId.toString();
      if (_discountValueCtrl.text.isNotEmpty) {
        pkgFields['package[discount_type]'] = _discountType;
        pkgFields['package[discount_value]'] = _discountValueCtrl.text;
      }

      pkgFields['package[seller_pays_shipping]'] = _sellerPaysDelivery ? 'true' : 'false';
      if (_sellerPaysDelivery) {
        if (_deliverySubsidyType == 'percent' && _deliverySubsidyValueCtrl.text.trim() == '100') {
          pkgFields['package[shipping_subsidy_type]'] = 'full';
          pkgFields['package[shipping_subsidy_value]'] = '';
        } else {
          pkgFields['package[shipping_subsidy_type]'] = _deliverySubsidyType;
          pkgFields['package[shipping_subsidy_value]'] = _deliverySubsidyType == 'percent'
              ? _deliverySubsidyValueCtrl.text.trim()
              : '';
        }
      }

      if (widget.packageData != null) {
        if (_existingImageIds.isNotEmpty) {
          pkgFields['package[keep_image_ids]'] = _existingImageIds.join(',');
        }
        if (_existingVideoIds.isNotEmpty) {
          pkgFields['package[keep_video_ids]'] = _existingVideoIds.join(',');
        }
      }

      if (_newPkgImages.isNotEmpty) {
        final List<MultipartFile> imageParts = [];
        for (final file in _newPkgImages) {
          if (kIsWeb) {
            final bytes = await file.readAsBytes();
            imageParts.add(MultipartFile.fromBytes(bytes, filename: file.name));
          } else {
            imageParts.add(await MultipartFile.fromFile(file.path, filename: file.name));
          }
        }
        pkgFields['package[images][]'] = imageParts;
      }

      if (_newPkgVideos.isNotEmpty) {
        final List<MultipartFile> videoParts = [];
        for (final file in _newPkgVideos) {
          if (kIsWeb) {
            final bytes = await file.readAsBytes();
            videoParts.add(MultipartFile.fromBytes(bytes, filename: file.name));
          } else {
            videoParts.add(await MultipartFile.fromFile(file.path, filename: file.name));
          }
        }
        pkgFields['package[videos][]'] = videoParts;
      }

      final url = widget.packageData != null ? '/packages/${widget.packageData!['id']}' : '/packages';
      if (widget.packageData != null) {
        await ApiClient.instance.put(url, data: FormData.fromMap(pkgFields));
      } else {
        await ApiClient.instance.post(url, data: FormData.fromMap(pkgFields));
      }

      _showSnack(
        widget.packageData != null ? l10n.translate('package_updated') : l10n.translate('package_created'),
        AppColors.textPrimary,
      );
      if (mounted) Navigator.pop(context);
    } catch (e) {
      _showSnack(l10n.translate('submit_failed').replaceAll('{error}', e.toString()), AppColors.error);
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  void _showSnack(String msg, Color color) =>
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(msg),
          backgroundColor: color,
          behavior: SnackBarBehavior.floating,
          elevation: 0,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppShapes.radiusSm)),
          margin: const EdgeInsets.all(AppSpacing.lg),
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg, vertical: AppSpacing.md),
          duration: const Duration(seconds: 2),
        ),
      );

  PreferredSizeWidget _buildAppBar(String title, String subtitle, {bool loading = false}) {
    final textTheme = Theme.of(context).textTheme;
    return AppBar(
      toolbarHeight: 52,
      automaticallyImplyLeading: true,
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
      iconTheme: const IconThemeData(color: AppColors.white),
      title: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: textTheme.titleMedium?.copyWith(
              color: AppColors.white,
              fontWeight: FontWeight.w700,
              fontSize: 17,
            ),
          ),
          if (subtitle.isNotEmpty)
            Text(
              subtitle,
              style: textTheme.bodySmall?.copyWith(
                color: AppColors.white.withOpacity(0.85),
                fontSize: 12,
                height: 1.2,
              ),
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final isEditing = widget.packageData != null;
    final textTheme = Theme.of(context).textTheme;

    if (_isLoadingCategories || _isLoadingProducts) {
      return Scaffold(
        backgroundColor: AppColors.pageBackground,
        appBar: _buildAppBar(
          isEditing ? l10n.translate('edit_package_title') : l10n.translate('create_package_title'),
          '',
        ),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      backgroundColor: AppColors.pageBackground,
      appBar: _buildAppBar(
        isEditing ? l10n.translate('edit_package_title') : l10n.translate('create_package_title'),
        isEditing ? l10n.translate('update_package_subtitle') : l10n.translate('build_package_subtitle'),
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(8, 12, 8, 30),
          children: [
            // Mode Toggle
            Container(
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                color: AppColors.cardBackground,
                borderRadius: BorderRadius.circular(AppShapes.radiusMd),
              ),
              child: Row(children: [
                Expanded(child: _modeTab(l10n.translate('existing_products_tab'), _fromExisting, () => setState(() { _fromExisting = true; _onProductSelectionChanged(); }))),
                Expanded(child: _modeTab(l10n.translate('create_new_tab'), !_fromExisting, () => setState(() { _fromExisting = false; }))),
              ]),
            ),
            const SizedBox(height: 12),

            // Products Section
            if (_fromExisting) ...[
              _sectionHeader(l10n.translate('select_products')),
              const SizedBox(height: AppSpacing.sm),
              if (_selectedProductIds.length < 2)
                Padding(
                  padding: const EdgeInsets.only(bottom: AppSpacing.xs),
                  child: Text(
                    'Please select at least 2 products',
                    style: TextStyle(color: AppColors.error, fontSize: 13),
                  ),
                ),
              if (_existingProducts.isEmpty)
                Padding(
                  padding: const EdgeInsets.all(AppSpacing.md),
                  child: Text(l10n.translate('no_products_found'),
                      style: textTheme.bodyMedium?.copyWith(color: AppColors.textMuted)),
                )
              else
                Container(
                  decoration: BoxDecoration(
                    color: Colors.grey.shade100,
                    borderRadius: BorderRadius.circular(AppShapes.radiusMd),
                  ),
                  padding: const EdgeInsets.all(AppSpacing.sm),
                  child: SizedBox(
                    height: 300,
                    child: ListView.separated(
                      itemCount: _existingProducts.length,
                      separatorBuilder: (_, __) => const SizedBox(height: AppSpacing.xs),
                      itemBuilder: (ctx, index) => _productCard(_existingProducts[index]),
                    ),
                  ),
                ),
              if (_fromExisting && _selectedProductIds.length >= 2 && _maxPossibleStock != _UNLIMITED_STOCK) ...[
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.orange.shade50,
                    borderRadius: BorderRadius.circular(AppShapes.radiusSm),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '📦 You can create up to $_maxPossibleStock packages because:',
                        style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13, color: Colors.orange.shade800),
                      ),
                      ..._limitingProducts.map((lp) => Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text('• $lp', style: TextStyle(fontSize: 13, color: Colors.orange.shade700)),
                      )),
                    ],
                  ),
                ),
              ] else if (_fromExisting && _selectedProductIds.length >= 2) ...[
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.green.shade50,
                    borderRadius: BorderRadius.circular(AppShapes.radiusSm),
                  ),
                  child: Text(
                    '📦 Unlimited packages possible.',
                    style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13, color: Colors.green.shade800),
                  ),
                ),
              ],
              const SizedBox(height: 12),
            ] else ...[
              _sectionHeader(l10n.translate('products_section')),
              const SizedBox(height: AppSpacing.sm),
              if (_inlineProducts.length < 2)
                Padding(
                  padding: const EdgeInsets.only(bottom: AppSpacing.xs),
                  child: Text(
                    'Please add at least 2 products',
                    style: TextStyle(color: AppColors.error, fontSize: 13),
                  ),
                ),
              ...List.generate(_inlineProducts.length, (i) => _inlineProductCard(i, l10n)),
              Center(
                child: TextButton.icon(
                  onPressed: _addInlineProduct,
                  icon: const Icon(Icons.add_circle_outline, color: AppColors.primary, size: 20),
                  label: Text(l10n.translate('add_another_product'),
                      style: textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600, color: AppColors.primary)),
                ),
              ),
              const SizedBox(height: 12),
            ],

            // Category
            _flatCard(children: [
              _sectionHeader(l10n.translate('category_label')),
              const SizedBox(height: AppSpacing.sm),
              _dropdown<int>(
                value: (_selectedMainCategoryId != null &&
                        _mainCategories.any((c) => c['id'] == _selectedMainCategoryId))
                    ? _selectedMainCategoryId
                    : null,
                hint: l10n.translate('select_main_category'),
                items: _mainCategories
                    .map<DropdownMenuItem<int>>(
                        (c) => DropdownMenuItem<int>(value: c['id'] as int, child: Text(c['name'])))
                    .toList(),
                onChanged: (v) {
                  setState(() {
                    _selectedMainCategoryId = v;
                    _selectedSubCategoryId = null;
                    _subCategories = [];
                  });
                  if (v != null) _loadSubCategories(v);
                },
              ),
              if (_subCategories.isNotEmpty) ...[
                const SizedBox(height: AppSpacing.sm),
                _dropdown<int>(
                  value: (_selectedSubCategoryId != null &&
                          _subCategories.any((c) => c['id'] == _selectedSubCategoryId))
                      ? _selectedSubCategoryId
                      : null,
                  hint: l10n.translate('none_use_main_only'),
                  items: [
                    DropdownMenuItem<int>(value: null, child: Text(l10n.translate('none'))),
                    ..._subCategories.map<DropdownMenuItem<int>>(
                        (c) => DropdownMenuItem<int>(value: c['id'] as int, child: Text(c['name']))),
                  ],
                  onChanged: (v) => setState(() => _selectedSubCategoryId = v),
                ),
              ],
            ]),
            const SizedBox(height: 12),

            // Package fields
            _flatCard(children: [
              _textField(controller: _nameCtrl, label: l10n.translate('package_name_label'), hint: l10n.translate('package_name_hint')),
              const SizedBox(height: AppSpacing.md),
              _textField(controller: _descCtrl, label: 'Package Description', hint: 'Describe your package, key features, etc.', maxLines: 2),
              const SizedBox(height: AppSpacing.md),
              _textField(
                controller: _priceCtrl,
                label: l10n.translate('package_price_label'),
                hint: '0.00',
                keyboardType: TextInputType.numberWithOptions(decimal: true),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) return 'Price is required';
                  final price = double.tryParse(value.trim());
                  if (price == null || price <= 0) return 'Enter a valid price';
                  return null;
                },
              ),
              const SizedBox(height: AppSpacing.md),
              _textField(
                controller: _stockCtrl,
                label: 'Stock (max ${_maxPossibleStock == _UNLIMITED_STOCK ? 'unlimited' : _maxPossibleStock} packages possible)',
                hint: '0',
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                validator: (value) {
                  if (value == null || value.trim().isEmpty) return 'Stock is required';
                  final stock = int.tryParse(value.trim());
                  if (stock == null || stock < 0) return 'Enter a valid stock';
                  final max = _maxPossibleStock;
                  if (max != _UNLIMITED_STOCK && stock > max) return 'Maximum $max packages possible';
                  return null;
                },
                onChanged: (val) {
                  final max = _maxPossibleStock;
                  if (max != _UNLIMITED_STOCK) {
                    final entered = int.tryParse(val) ?? 0;
                    if (entered > max) {
                      _stockCtrl.text = max.toString();
                      _stockCtrl.selection = TextSelection.fromPosition(TextPosition(offset: _stockCtrl.text.length));
                      _showSnack('Maximum $max packages possible', AppColors.info);
                    }
                  }
                },
              ),
            ]),
            const SizedBox(height: 12),

            // Discount
            _flatCard(children: [
              _sectionHeader(l10n.translate('discount_label')),
              const SizedBox(height: AppSpacing.sm),
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Expanded(
                    flex: 2,
                    child: _dropdown<String>(
                      value: _discountType,
                      hint: l10n.translate('discount_type_label'),
                      items: [
                        DropdownMenuItem(value: 'percentage', child: Text(l10n.translate('percentage_label'))),
                        DropdownMenuItem(value: 'fixed', child: Text(l10n.translate('fixed_amount_label'))),
                      ],
                      onChanged: (v) => setState(() => _discountType = v!),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    flex: 1,
                    child: TextFormField(
                      controller: _discountValueCtrl,
                      keyboardType: TextInputType.numberWithOptions(decimal: true),
                      inputFormatters: [
                        PositiveDecimalInputFormatter(
                          maxValue: _discountType == 'percentage' ? 100 : null,
                        ),
                      ],
                      style: Theme.of(context).textTheme.bodyLarge?.copyWith(color: AppColors.textPrimary),
                      decoration: InputDecoration(
                        hintText: '0',
                        hintStyle: Theme.of(context).textTheme.bodyMedium?.copyWith(color: AppColors.textMuted),
                        filled: true,
                        fillColor: AppColors.hoverState,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(AppShapes.radiusSm),
                          borderSide: const BorderSide(color: AppColors.borderLight),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(AppShapes.radiusSm),
                          borderSide: const BorderSide(color: AppColors.borderLight),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(AppShapes.radiusSm),
                          borderSide: const BorderSide(color: AppColors.primary, width: 2),
                        ),
                      ),
                      validator: (value) {
                        if (value == null || value.trim().isEmpty) return null;
                        final v = double.tryParse(value.trim());
                        if (v == null || v <= 0) return 'Must be positive';
                        if (_discountType == 'percentage' && v > 100) return 'Max 100%';
                        return null;
                      },
                    ),
                  ),
                ],
              ),
            ]),
            const SizedBox(height: 12),

            // Delivery Subsidy
            _flatCard(children: [
              _sectionHeader(l10n.translate('delivery_subsidy_label')),
              const SizedBox(height: AppSpacing.xs),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Text(l10n.translate('pay_delivery_label'),
                        style: textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
                  ),
                  Transform.scale(
                    scale: 0.8,
                    child: Switch(
                      value: _sellerPaysDelivery,
                      onChanged: (v) => setState(() => _sellerPaysDelivery = v),
                      activeColor: AppColors.primary,
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                  ),
                ],
              ),
              if (_sellerPaysDelivery) ...[
                const SizedBox(height: AppSpacing.sm),
                _dropdown<String>(
                  value: _deliverySubsidyType,
                  hint: l10n.translate('subsidy_type_label'),
                  items: [
                    DropdownMenuItem(value: 'full', child: Text(l10n.translate('full_delivery_label'))),
                    DropdownMenuItem(value: 'percent', child: Text(l10n.translate('percentage_delivery_label'))),
                  ],
                  onChanged: (v) => setState(() => _deliverySubsidyType = v!),
                ),
                if (_deliverySubsidyType == 'percent') ...[
                  const SizedBox(height: AppSpacing.sm),
                  _textField(
                    controller: _deliverySubsidyValueCtrl,
                    label: l10n.translate('percentage_input_label'),
                    hint: 'e.g., 50',
                    keyboardType: TextInputType.number,
                    inputFormatters: [
                      PositiveDecimalInputFormatter(maxValue: 100),
                    ],
                    validator: (value) {
                      if (value == null || value.trim().isEmpty) return 'Required';
                      final v = double.tryParse(value.trim());
                      if (v == null || v <= 0 || v > 100) return 'Enter 1-100';
                      return null;
                    },
                  ),
                ],
              ],
            ]),
            const SizedBox(height: 12),

            // Status
            _flatCard(children: [
              _sectionHeader(l10n.translate('status_label')),
              const SizedBox(height: AppSpacing.sm),
              Row(children: [
                _statusPill('active', l10n.translate('active')),
                const SizedBox(width: AppSpacing.xs),
                _statusPill('draft', l10n.translate('draft')),
                const SizedBox(width: AppSpacing.xs),
                _statusPill('archived', l10n.translate('archived')),
              ]),
            ]),
            const SizedBox(height: 12),

            // Package Media Section
            _flatCard(children: [
              _sectionHeader('Package Media (optional)'),
              const SizedBox(height: 4),
              Text(
                'Add images and a video to showcase your package.',
                style: textTheme.bodySmall?.copyWith(color: AppColors.textMuted),
              ),
              const SizedBox(height: AppSpacing.sm),

              Text('Images (up to 3)', style: textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
              const SizedBox(height: AppSpacing.xs),
              if (_existingImageUrls.isNotEmpty) ...[
                SizedBox(
                  height: 80,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: _existingImageUrls.length,
                    separatorBuilder: (_, __) => const SizedBox(width: AppSpacing.xs),
                    itemBuilder: (ctx, i) => ClipRRect(
                      borderRadius: BorderRadius.circular(AppShapes.radiusSm),
                      child: Stack(
                        children: [
                          Image.network(resolveUrl(_existingImageUrls[i]),
                              width: 80, height: 80, fit: BoxFit.cover,
                              errorBuilder: (_, __, ___) =>
                                  const Icon(Icons.broken_image, size: 30)),
                          Positioned(
                            top: 2, right: 2,
                            child: GestureDetector(
                              onTap: () {
                                setState(() {
                                  _existingImageUrls.removeAt(i);
                                  if (_existingImageIds.length > i) _existingImageIds.removeAt(i);
                                });
                              },
                              child: Container(
                                padding: const EdgeInsets.all(3),
                                decoration: const BoxDecoration(
                                  color: AppColors.textSecondary,
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(Icons.close, size: 12, color: Colors.white),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: AppSpacing.sm),
              ],
              if (_newPkgImages.isNotEmpty)
                SizedBox(
                  height: 80,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: _newPkgImages.length + 1,
                    separatorBuilder: (_, __) => const SizedBox(width: AppSpacing.xs),
                    itemBuilder: (ctx, i) {
                      if (i == _newPkgImages.length) return _addImageButton(l10n);
                      return Stack(
                        children: [
                          ClipRRect(
                              borderRadius: BorderRadius.circular(AppShapes.radiusSm),
                              child: _buildImageWidget(_newPkgImages[i], width: 80, height: 80)),
                          Positioned(
                            top: 2, right: 2,
                            child: GestureDetector(
                              onTap: () => _removeNewImage(i),
                              child: Container(
                                padding: const EdgeInsets.all(3),
                                decoration: const BoxDecoration(
                                  color: AppColors.textSecondary,
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(Icons.close, size: 12, color: Colors.white),
                              ),
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                )
              else if (_existingImageUrls.isEmpty)
                _addImageButton(l10n)
              else
                _addImageButton(l10n),

              const SizedBox(height: AppSpacing.sm),

              Text('Video (up to 1)', style: textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
              const SizedBox(height: AppSpacing.xs),
              if (_existingVideoUrls.isNotEmpty) ...[
                SizedBox(
                  height: 80,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: _existingVideoUrls.length,
                    separatorBuilder: (_, __) => const SizedBox(width: AppSpacing.xs),
                    itemBuilder: (ctx, i) => Container(
                      width: 80,
                      height: 80,
                      decoration: BoxDecoration(
                        color: Colors.black,
                        borderRadius: BorderRadius.circular(AppShapes.radiusMd),
                      ),
                      child: Stack(
                        children: [
                          Center(child: Icon(Icons.videocam, color: Colors.white, size: 28)),
                          Positioned(
                            top: 2, right: 2,
                            child: GestureDetector(
                              onTap: () {
                                setState(() {
                                  _existingVideoUrls.removeAt(i);
                                  if (_existingVideoIds.length > i) _existingVideoIds.removeAt(i);
                                });
                              },
                              child: Container(
                                padding: const EdgeInsets.all(3),
                                decoration: const BoxDecoration(
                                  color: AppColors.textSecondary,
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(Icons.close, size: 12, color: Colors.white),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: AppSpacing.sm),
              ],
              if (_newPkgVideos.isNotEmpty) ...[
                SizedBox(
                  height: 80,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: _newPkgVideos.length,
                    separatorBuilder: (_, __) => const SizedBox(width: AppSpacing.xs),
                    itemBuilder: (ctx, i) => Stack(
                      children: [
                        Container(
                          width: 80,
                          height: 80,
                          decoration: BoxDecoration(
                            color: Colors.black,
                            borderRadius: BorderRadius.circular(AppShapes.radiusMd),
                          ),
                          child: Center(
                            child: Icon(Icons.videocam, color: Colors.white, size: 28),
                          ),
                        ),
                        Positioned(
                          top: 2, right: 2,
                          child: GestureDetector(
                            onTap: () => _removeNewVideo(i),
                            child: Container(
                              padding: const EdgeInsets.all(3),
                              decoration: const BoxDecoration(
                                color: AppColors.textSecondary,
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(Icons.close, size: 12, color: Colors.white),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: AppSpacing.sm),
              ],
              _addVideoButton(l10n),
            ]),
            const SizedBox(height: 12),

            // Enhanced Summary
            _flatCard(children: [
              Text(l10n.translate('package_summary_label'), style: textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
              const SizedBox(height: AppSpacing.md),
              ..._buildProductSummaryList(),
              const SizedBox(height: AppSpacing.sm),
              _summaryRow('Total Products', _totalProducts.toString()),
              const SizedBox(height: AppSpacing.xs),
              _summaryRow('Total Product Value', 'ETB ${formatCurrency(_totalProductPrice)}'),
              if (_discountValueCtrl.text.isNotEmpty) ...[
                const SizedBox(height: AppSpacing.xs),
                _summaryRow(l10n.translate('you_save_summary'), 'ETB ${_discountValueCtrl.text}'),
              ],
              if (_stockCtrl.text.isNotEmpty) ...[
                const SizedBox(height: AppSpacing.xs),
                _summaryRow(l10n.translate('stock_label'), _stockCtrl.text),
              ],
            ]),
            const SizedBox(height: 24),

            // Submit
            Center(
              child: SizedBox(
                width: 200,
                height: 48,
                child: ElevatedButton(
                  onPressed: (_isSubmitting || !_canSubmit) ? null : _submit,
                  style: AppComponentStyles.primaryButton.copyWith(
                    shape: WidgetStatePropertyAll(
                      RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppShapes.radiusSm)),
                    ),
                  ),
                  child: _isSubmitting
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : Text(isEditing ? l10n.translate('edit_package_title') : l10n.translate('create_package_title')),
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
          ],
        ),
      ),
    );
  }

  List<Widget> _buildProductSummaryList() {
    if (_fromExisting) {
      return _selectedProductIds.map((pid) {
        final product = _existingProducts.firstWhere(
          (p) => p['id'] == pid,
          orElse: () => {'title': 'Unknown', 'price': 0.0},
        );
        final title = product['title'] ?? 'Unknown';
        final price = parsePrice(product['price']);
        return Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  title,
                  style: Theme.of(context).textTheme.bodyMedium,
                  softWrap: true,
                  overflow: TextOverflow.visible,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                'ETB ${formatCurrency(price)}',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
              ),
            ],
          ),
        );
      }).toList();
    } else {
      return _inlineProducts.map((p) {
        final name = p.titleCtrl.text.trim().isEmpty ? 'New Product' : p.titleCtrl.text.trim();
        final price = double.tryParse(p.priceCtrl.text) ?? 0.0;
        return Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  name,
                  style: Theme.of(context).textTheme.bodyMedium,
                  softWrap: true,
                  overflow: TextOverflow.visible,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                'ETB ${formatCurrency(price)}',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
              ),
            ],
          ),
        );
      }).toList();
    }
  }

  Widget _sectionHeader(String text) => Text(
        text,
        style: Theme.of(context).textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimary,
            ),
      );

  Widget _flatCard({required List<Widget> children}) => Container(
        padding: const EdgeInsets.all(AppSpacing.md),
        decoration: BoxDecoration(
          color: AppColors.cardBackground,
          borderRadius: BorderRadius.circular(AppShapes.radiusMd),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: children),
      );

  Widget _modeTab(String text, bool active, VoidCallback onTap) => GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
          decoration: BoxDecoration(
            color: active ? AppColors.primary : Colors.transparent,
            borderRadius: BorderRadius.circular(AppShapes.radiusSm),
          ),
          child: Center(
            child: Text(text,
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 15,
                  color: active ? AppColors.white : AppColors.textSecondary,
                )),
          ),
        ),
      );

  Widget _productCard(Map<String, dynamic> p) {
    final isSelected = _selectedProductIds.contains(p['id']);
    final hasVariants = hasSelectableVariants(p);
    final variantAttrs = _selectedProductVariants[p['id']];
    final isOrderable = p['orderable'] != false;
    final stockDisplay = computeStockDisplay(p, variantAttrs);

    return GestureDetector(
      onTap: isOrderable
          ? () {
              if (isSelected) {
                setState(() {
                  _selectedProductIds.remove(p['id']);
                  _selectedProductVariants.remove(p['id']);
                  _onProductSelectionChanged();
                });
              } else if (hasVariants) {
                _openVariantSelection(p);
              } else {
                setState(() {
                  _selectedProductIds.add(p['id']);
                  _onProductSelectionChanged();
                });
              }
            }
          : null,
      child: Opacity(
        opacity: isOrderable ? 1.0 : 0.5,
        child: Container(
          margin: const EdgeInsets.only(bottom: AppSpacing.xs),
          padding: const EdgeInsets.all(AppSpacing.sm),
          decoration: BoxDecoration(
            color: AppColors.cardBackground,
            borderRadius: BorderRadius.circular(AppShapes.radiusSm),
            border: Border.all(
              color: isSelected ? AppColors.primary : AppColors.borderLight,
              width: isSelected ? 2 : 1,
            ),
          ),
          child: Stack(
            children: [
              Row(children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(AppShapes.radiusSm),
                  child: Image.network(resolveUrl(p['image_url']),
                      width: 48, height: 48, fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => Container(
                          width: 48,
                          height: 48,
                          decoration: BoxDecoration(
                              color: AppColors.hoverState,
                              borderRadius: BorderRadius.circular(AppShapes.radiusSm)),
                          child: const Icon(Icons.image, color: AppColors.textMuted, size: 20))),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(p['title'],
                          style: const TextStyle(
                              fontWeight: FontWeight.w600,
                              color: AppColors.textPrimary,
                              fontSize: 15)),
                      const SizedBox(height: 2),
                      Text('ETB ${p['price']}',
                          style: const TextStyle(
                              fontWeight: FontWeight.w500,
                              color: AppColors.textSecondary,
                              fontSize: 14)),
                      const SizedBox(height: 1),
                      Text('Stock: $stockDisplay',
                          style: const TextStyle(fontSize: 13, color: AppColors.textMuted)),
                      if (hasVariants)
                        variantAttrs != null
                            ? Text(
                                variantAttrs.entries.map((e) => '${e.key}: ${e.value}').join(', '),
                                style: const TextStyle(fontSize: 12, color: Colors.purple),
                              )
                            : const Text(
                                'Choose variant',
                                style: TextStyle(fontSize: 12, color: Colors.blue, fontStyle: FontStyle.italic),
                              ),
                    ],
                  ),
                ),
                Container(
                  width: 24,
                  height: 24,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: isSelected ? AppColors.primary : Colors.transparent,
                    border: Border.all(
                        color: isSelected ? AppColors.primary : AppColors.borderLight, width: 2),
                  ),
                  child: isSelected ? const Icon(Icons.check, size: 16, color: Colors.white) : null,
                ),
              ]),
              if (!isOrderable)
                Positioned.fill(
                  child: Container(
                    color: Colors.white60,
                    child: Center(
                      child: Text(
                        p['unavailable_reason'] ?? 'Unavailable',
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: Colors.red,
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _inlineProductCard(int index, AppLocalizations l10n) {
    final p = _inlineProducts[index];
    return Container(
      margin: const EdgeInsets.only(bottom: AppSpacing.sm),
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.cardBackground,
        borderRadius: BorderRadius.circular(AppShapes.radiusMd),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Expanded(
                child: Text(l10n.translate('product_label').replaceAll('{index}', (index + 1).toString()),
                    style: Theme.of(context)
                        .textTheme
                        .bodyLarge
                        ?.copyWith(fontWeight: FontWeight.w600))),
            if (_inlineProducts.length > 2)
              IconButton(
                  icon: const Icon(Icons.remove_circle_outline, color: AppColors.error, size: 20),
                  onPressed: () => _removeInlineProduct(index)),
          ]),
          const SizedBox(height: AppSpacing.sm),
          _textField(controller: p.titleCtrl, label: l10n.translate('title_label'), hint: l10n.translate('title_hint'), validator: (v) => v == null || v.trim().isEmpty ? 'Required' : null),
          const SizedBox(height: AppSpacing.sm),
          _textField(controller: p.descCtrl, label: l10n.translate('description_label'), hint: 'Optional', maxLines: 2),
          const SizedBox(height: AppSpacing.sm),
          _textField(controller: p.priceCtrl, label: l10n.translate('price_label'), hint: '0.00', keyboardType: TextInputType.numberWithOptions(decimal: true), validator: (v) => v == null || v.trim().isEmpty ? 'Required' : null),
          const SizedBox(height: AppSpacing.sm),
          _textField(controller: p.stockCtrl, label: l10n.translate('stock_label'), hint: '0', keyboardType: TextInputType.number, inputFormatters: [FilteringTextInputFormatter.digitsOnly]),
          const SizedBox(height: AppSpacing.sm),
          // ★ Weight & Dimensions (required for delivery)
          Text('Weight & Dimensions (required)', style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
          const SizedBox(height: 4),
          Row(children: [
            Expanded(child: _textField(controller: p.weightCtrl, label: 'Weight (kg)', hint: '0.0', keyboardType: TextInputType.numberWithOptions(decimal: true), validator: (v) => v == null || v.trim().isEmpty || double.tryParse(v.trim()) == null || double.tryParse(v.trim())! <= 0 ? 'Required' : null)),
            const SizedBox(width: 8),
            Expanded(child: _textField(controller: p.lengthCtrl, label: 'Length (cm)', hint: '0.0', keyboardType: TextInputType.numberWithOptions(decimal: true), validator: (v) => v == null || v.trim().isEmpty || double.tryParse(v.trim()) == null || double.tryParse(v.trim())! <= 0 ? 'Required' : null)),
          ]),
          const SizedBox(height: 4),
          Row(children: [
            Expanded(child: _textField(controller: p.widthCtrl, label: 'Width (cm)', hint: '0.0', keyboardType: TextInputType.numberWithOptions(decimal: true), validator: (v) => v == null || v.trim().isEmpty || double.tryParse(v.trim()) == null || double.tryParse(v.trim())! <= 0 ? 'Required' : null)),
            const SizedBox(width: 8),
            Expanded(child: _textField(controller: p.heightCtrl, label: 'Height (cm)', hint: '0.0', keyboardType: TextInputType.numberWithOptions(decimal: true), validator: (v) => v == null || v.trim().isEmpty || double.tryParse(v.trim()) == null || double.tryParse(v.trim())! <= 0 ? 'Required' : null)),
          ]),
          const SizedBox(height: AppSpacing.sm),
          Text('Product Images (up to 4)', style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
          const SizedBox(height: 4),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              ...p.images.asMap().entries.map((entry) {
                return Stack(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(AppShapes.radiusSm),
                      child: _buildImageWidget(entry.value, width: 48, height: 48),
                    ),
                    Positioned(
                      top: 0,
                      right: 0,
                      child: GestureDetector(
                        onTap: () => _removeProductImage(index, entry.key),
                        child: Container(
                          padding: const EdgeInsets.all(2),
                          decoration: const BoxDecoration(
                            color: Colors.red,
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(Icons.close, size: 12, color: Colors.white),
                        ),
                      ),
                    ),
                  ],
                );
              }),
              if (p.images.length < 4)
                GestureDetector(
                  onTap: () => _pickImagesForProduct(index),
                  child: Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: AppColors.hoverState,
                      borderRadius: BorderRadius.circular(AppShapes.radiusSm),
                      border: Border.all(color: AppColors.borderLight),
                    ),
                    child: const Icon(Icons.add_a_photo, size: 20, color: AppColors.textMuted),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _statusPill(String value, String label) {
    final active = _status == value;
    return GestureDetector(
      onTap: () => setState(() => _status = value),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        decoration: BoxDecoration(
          color: active ? AppColors.primary : AppColors.hoverState,
          borderRadius: BorderRadius.circular(AppShapes.radiusSm),
        ),
        child: Text(label,
            style: TextStyle(
              fontWeight: FontWeight.w600,
              fontSize: 14,
              color: active ? AppColors.white : AppColors.textSecondary,
            )),
      ),
    );
  }

  Widget _textField({
    required TextEditingController controller,
    required String label,
    String? hint,
    int maxLines = 1,
    TextInputType? keyboardType,
    List<TextInputFormatter>? inputFormatters,
    FormFieldValidator<String>? validator,
    ValueChanged<String>? onChanged,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (label.isNotEmpty) ...[
          Text(label,
              style: Theme.of(context)
                  .textTheme
                  .bodyMedium
                  ?.copyWith(fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
          const SizedBox(height: AppSpacing.xs),
        ],
        TextFormField(
          controller: controller,
          maxLines: maxLines,
          keyboardType: keyboardType,
          inputFormatters: inputFormatters,
          onChanged: onChanged,
          validator: validator,
          decoration: InputDecoration(
            hintText: hint,
            hintStyle:
                Theme.of(context).textTheme.bodyMedium?.copyWith(color: AppColors.textMuted),
            filled: true,
            fillColor: AppColors.hoverState,
            contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
            border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(AppShapes.radiusSm),
                borderSide: const BorderSide(color: AppColors.borderLight)),
            enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(AppShapes.radiusSm),
                borderSide: const BorderSide(color: AppColors.borderLight)),
            focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(AppShapes.radiusSm),
                borderSide: const BorderSide(color: AppColors.primary, width: 2)),
          ),
          style: Theme.of(context).textTheme.bodyLarge?.copyWith(color: AppColors.textPrimary),
        ),
      ],
    );
  }

  Widget _dropdown<T>({
    required T? value,
    required String? hint,
    required List<DropdownMenuItem<T>> items,
    required ValueChanged<T?> onChanged,
  }) {
    return Container(
      height: 48,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: AppColors.hoverState,
        borderRadius: BorderRadius.circular(AppShapes.radiusSm),
        border: Border.all(color: AppColors.borderLight),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<T>(
          value: value,
          hint: hint != null
              ? Text(hint,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: AppColors.textMuted))
              : null,
          items: items,
          onChanged: onChanged,
          isExpanded: true,
          icon: const Icon(Icons.expand_more_rounded, color: AppColors.textMuted, size: 20),
          style: Theme.of(context).textTheme.bodyLarge?.copyWith(color: AppColors.textPrimary),
          dropdownColor: AppColors.cardBackground,
          borderRadius: BorderRadius.circular(AppShapes.radiusSm),
        ),
      ),
    );
  }

  Widget _summaryRow(String title, String value) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(title, style: Theme.of(context).textTheme.bodyMedium),
        Text(value,
            style: Theme.of(context)
                .textTheme
                .bodyLarge
                ?.copyWith(fontWeight: FontWeight.w600)),
      ],
    );
  }

  Widget _buildImageWidget(XFile file, {double width = 80, double height = 80}) {
    if (kIsWeb) {
      return Image.network(file.path, width: width, height: height, fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => const Icon(Icons.broken_image, size: 30));
    }
    return Image.file(File(file.path), width: width, height: height, fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => const Icon(Icons.broken_image, size: 30));
  }

  Widget _addImageButton(AppLocalizations l10n) => GestureDetector(
        onTap: _pickPackageImages,
        child: Container(
          width: 80,
          height: 80,
          decoration: BoxDecoration(
            color: AppColors.hoverState,
            borderRadius: BorderRadius.circular(AppShapes.radiusSm),
            border: Border.all(color: AppColors.borderLight),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.add_a_photo_outlined, size: 24, color: AppColors.textMuted),
              const SizedBox(height: 2),
              Text(l10n.translate('add_image_btn'),
                  style: Theme.of(context)
                      .textTheme
                      .bodySmall
                      ?.copyWith(fontSize: 12, color: AppColors.textMuted)),
            ],
          ),
        ),
      );

  Widget _addVideoButton(AppLocalizations l10n) => GestureDetector(
        onTap: _pickPackageVideo,
        child: Container(
          width: 80,
          height: 80,
          decoration: BoxDecoration(
            color: AppColors.hoverState,
            borderRadius: BorderRadius.circular(AppShapes.radiusMd),
            border: Border.all(color: AppColors.borderLight),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.videocam, size: 24, color: AppColors.textMuted),
              const SizedBox(height: 2),
              Text(l10n.translate('add_video_btn'),
                  style: Theme.of(context)
                      .textTheme
                      .bodySmall
                      ?.copyWith(fontSize: 12, color: AppColors.textMuted)),
            ],
          ),
        ),
      );
}

class _InlineProduct {
  final TextEditingController titleCtrl = TextEditingController();
  final TextEditingController descCtrl = TextEditingController();
  final TextEditingController priceCtrl = TextEditingController();
  final TextEditingController stockCtrl = TextEditingController();
  final TextEditingController weightCtrl = TextEditingController();
  final TextEditingController lengthCtrl = TextEditingController();
  final TextEditingController widthCtrl = TextEditingController();
  final TextEditingController heightCtrl = TextEditingController();
  List<XFile> images = [];
}

extension FirstWhereOrNull<T> on Iterable<T> {
  T? firstWhereOrNull(bool Function(T) test) {
    for (final element in this) {
      if (test(element)) return element;
    }
    return null;
  }
}
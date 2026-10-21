// lib/screens/add_product_screen.dart (hardened – bulk stock hidden when variants exist)
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:dio/dio.dart';
import '../api/client.dart';
import '../models/product.dart';
import '../theme/app_theme.dart';
import '../l10n/app_localizations.dart';

class AddProductScreen extends StatefulWidget {
  final Product? product;
  const AddProductScreen({Key? key, this.product}) : super(key: key);
  @override
  State<AddProductScreen> createState() => _AddProductScreenState();
}

class _AddProductScreenState extends State<AddProductScreen> {
  final _formKey = GlobalKey<FormState>();
  final ImagePicker _picker = ImagePicker();

  final _titleCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  final _priceCtrl = TextEditingController();
  final _stockCtrl = TextEditingController();

  bool _sellerPaysDelivery = false;
  String _deliverySubsidyType = 'full';
  final _deliverySubsidyValueCtrl = TextEditingController();

  String _discountType = 'percent';
  final _discountValueCtrl = TextEditingController();

  // Live discount preview
  String? get _discountPreview {
    final val = double.tryParse(_discountValueCtrl.text.trim());
    if (val == null || val <= 0) return null;
    if (_discountType == 'percent' && val > 100) return null;
    return _discountType == 'percent'
        ? '$val% off'
        : 'ETB $val off';
  }

  List<Map<String, dynamic>> _mainCategories = [];
  List<Map<String, dynamic>> _subCategories = [];
  int? _mainCategoryId;
  int? _subCategoryId;
  bool _loadingCategories = true;
  bool _categoriesError = false;

  // Image state
  static const int _maxImages = 6;
  List<XFile> _newImages = [];
  List<String> _existingImageUrls = [];
  List<String> _existingImageBlobIds = []; // string IDs for API

  // Video state
  List<String> _existingVideoUrls = [];
  List<String> _existingVideoBlobIds = []; // string IDs for API
  XFile? _newVideo;

  List<AttributeDefinition> _allAttrs = [];
  List<AttributeDefinition> _requiredAttrs = [];
  List<AttributeDefinition> _optionalAttrs = [];
  List<String> _addedOptionalNames = [];
  Map<String, String> _attrValues = {};

  List<AttributeDefinition> _variantAttrs = [];
  List<Variety> _varieties = [];
  Map<String, List<String>> _customSuggestions = {};

  bool _isSubmitting = false;
  bool _prefilled = false;
  bool _loadingEditData = false;
  bool _attributesError = false;

  // Bulk fields
  bool _bulkEnabled = false;
  final _minBulkQtyCtrl = TextEditingController();
  final _maxQtyPerDayCtrl = TextEditingController();

  // Dimensions
  final _weightCtrl = TextEditingController();
  final _lengthCtrl = TextEditingController();
  final _widthCtrl = TextEditingController();
  final _heightCtrl = TextEditingController();

  final Map<String, TextEditingController> _attrControllers = {};
  final Map<String, TextEditingController> _variantControllers = {};

  TextEditingController _getAttrController(String name) {
    if (!_attrControllers.containsKey(name)) {
      _attrControllers[name] = TextEditingController(text: _attrValues[name] ?? '');
    }
    return _attrControllers[name]!;
  }

  TextEditingController _getVariantController(int idx, String field) {
    final key = '${idx}_$field';
    if (!_variantControllers.containsKey(key)) {
      final v = _varieties[idx];
      final text = field == 'price' ? v.price : (field == 'stock' ? v.stock : '');
      _variantControllers[key] = TextEditingController(text: text);
    }
    return _variantControllers[key]!;
  }

  void _syncAttrController(String name) {
    if (_attrControllers.containsKey(name)) {
      _attrControllers[name]!.text = _attrValues[name] ?? '';
    }
  }

  void _syncVariantController(int idx, String field) {
    final key = '${idx}_$field';
    if (_variantControllers.containsKey(key)) {
      final v = _varieties[idx];
      _variantControllers[key]!.text = field == 'price' ? v.price : (field == 'stock' ? v.stock : '');
    }
  }

  @override
  void initState() {
    super.initState();
    _loadCategories();
    if (widget.product != null) {
      _prefillProduct(widget.product!);
      if (widget.product!.id != null) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            setState(() => _loadingEditData = true);
            _fetchProductDetails(widget.product!.id);
          }
        });
      }
    }
  }

  void _prefillProduct(Product p) {
    _titleCtrl.text = p.title ?? '';
    _descCtrl.text = p.description ?? '';
    _priceCtrl.text = p.price?.toString() ?? '';
    _stockCtrl.text = p.stock?.toString() ?? '';
    if (p.attributes != null && p.attributes.isNotEmpty) {
      _attrValues = Map<String, String>.from(p.attributes);
    }
    _sellerPaysDelivery = p.sellerPaysShipping ?? false;
    // Map 'fixed' to 'full' (we only support full and percent)
    _deliverySubsidyType = (p.shippingSubsidyType == 'percent') ? 'percent' : 'full';
    _deliverySubsidyValueCtrl.text = p.shippingSubsidyValue?.toString() ?? '';

    _discountType = p.discountType ?? 'percent';
    _discountValueCtrl.text = p.discountValue?.toString() ?? '';

    _existingVideoUrls = List<String>.from(p.videoUrls ?? []);
    _existingVideoBlobIds = []; // will be populated by _fetchProductDetails

    _bulkEnabled = p.bulkEnabled ?? false;
    _minBulkQtyCtrl.text = p.minimumBulkQuantity?.toString() ?? '';
    _maxQtyPerDayCtrl.text = p.maxQuantityPerDay?.toString() ?? '';

    _weightCtrl.text = p.weightKg?.toString() ?? '';
    _lengthCtrl.text = p.lengthCm?.toString() ?? '';
    _widthCtrl.text = p.widthCm?.toString() ?? '';
    _heightCtrl.text = p.heightCm?.toString() ?? '';

    if (p.categoryId != null) {
      _mainCategoryId = p.categoryId;
      _subCategoryId = null;
    }

    _prefilled = true;
  }

  Future<void> _fetchProductDetails(int productId) async {
    final l10n = AppLocalizations.of(context);
    try {
      final res = await ApiClient.instance.get('/products/$productId');
      final product = res.data;

      if (product['category'] != null) {
        final cat = product['category'];
        final parentId = cat['parent_id'];
        final catId = cat['id'];
        if (mounted) {
          setState(() {
            if (parentId != null) {
              _mainCategoryId = parentId;
              _subCategoryId = catId;
            } else {
              _mainCategoryId = catId;
              _subCategoryId = null;
            }
          });
        }
        if (_mainCategoryId != null) await _loadSubCategories(_mainCategoryId!);
      }

      if (product['product_attributes'] != null && mounted) {
        final attrs = Map<String, String>.from(product['product_attributes']);
        setState(() {
          _attrValues = attrs;
          _addedOptionalNames = _optionalAttrs
              .where((a) => _attrValues.containsKey(a.name))
              .map((a) => a.name)
              .toList();
        });
      }

      if (product['stock'] != null && mounted)
        _stockCtrl.text = product['stock'].toString();

      if (product['image_urls'] != null && mounted) {
        setState(() {
          _existingImageUrls = List<String>.from(product['image_urls']);
          _existingImageBlobIds =
              (product['image_ids'] as List?)?.map((e) => e.toString()).toList() ?? [];
        });
      }

      if (product['video_urls'] != null && mounted) {
        setState(() {
          _existingVideoUrls = List<String>.from(product['video_urls']);
          _existingVideoBlobIds =
              (product['video_ids'] as List?)?.map((e) => e.toString()).toList() ?? [];
        });
      }

      if (product['variants'] is List && (product['variants'] as List).isNotEmpty && mounted) {
        final variantsData = product['variants'] as List;
        final List<Variety> parsedVarieties = [];
        for (final v in variantsData) {
          final attrsMap = v['attributes'] as Map<String, dynamic>? ?? {};
          final List<SelectedAttr> selected = [];
          attrsMap.forEach((attrName, value) {
            final def = _variantAttrs.firstWhereOrNull((a) => a.name == attrName);
            if (def != null)
              selected.add(SelectedAttr(attrId: def.id, value: value.toString()));
          });
          final unlimited = v['unlimited_stock'] == true;
          parsedVarieties.add(Variety(
            selectedAttrs: selected,
            price: v['price']?.toString() ?? '',
            stock: unlimited ? '' : (v['stock']?.toString() ?? ''),
            unlimitedStock: unlimited,
            image: null,
          ));
        }
        if (parsedVarieties.isNotEmpty)
          setState(() => _varieties = parsedVarieties);
      }
    } catch (_) {
      if (mounted)
        _showSnack(l10n.translate('could_not_load_details'), AppColors.textMuted);
    } finally {
      if (mounted) setState(() => _loadingEditData = false);
    }
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _descCtrl.dispose();
    _priceCtrl.dispose();
    _stockCtrl.dispose();
    _deliverySubsidyValueCtrl.dispose();
    _discountValueCtrl.dispose();
    _minBulkQtyCtrl.dispose();
    _maxQtyPerDayCtrl.dispose();
    _weightCtrl.dispose();
    _lengthCtrl.dispose();
    _widthCtrl.dispose();
    _heightCtrl.dispose();
    for (final c in _attrControllers.values) {
      c.dispose();
    }
    for (final c in _variantControllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  // ── Category & Attribute loading ───────────
  Future<void> _loadCategories() async {
    setState(() {
      _loadingCategories = true;
      _categoriesError = false;
    });
    try {
      final response = await ApiClient.instance.get('/categories');
      final List raw =
          response.data is List ? response.data : (response.data['data'] ?? []);
      final List<Map<String, dynamic>> all = raw
          .map((c) => {
                'id': c['id'],
                'name': c['name'],
                'parent_id': c['parent_id'],
              })
          .toList();
      final mains = all.where((c) => c['parent_id'] == null).toList();
      if (mounted)
        setState(() {
          _mainCategories = mains;
          _loadingCategories = false;
        });
    } catch (e) {
      if (mounted)
        setState(() {
          _loadingCategories = false;
          _categoriesError = true;
        });
    }
  }

  Future<void> _loadSubCategories(int mainId) async {
    try {
      final response = await ApiClient.instance.get('/categories');
      final List raw =
          response.data is List ? response.data : (response.data['data'] ?? []);
      final List<Map<String, dynamic>> all = raw
          .map((c) => {
                'id': c['id'],
                'name': c['name'],
                'parent_id': c['parent_id'],
              })
          .toList();
      final subs = all.where((c) => c['parent_id'] == mainId).toList();
      if (mounted)
        setState(() {
          _subCategories = subs;
          if (!_prefilled) _subCategoryId = null;
        });
    } catch (_) {
      if (mounted)
        _showSnack(
            AppLocalizations.of(context).translate('failed_load_subcategories'),
            AppColors.error);
    }
    _loadAttributes(mainId);
  }

  Future<void> _loadAttributes(int categoryId) async {
    setState(() {
      _attributesError = false;
    });
    try {
      final response = await ApiClient.instance
          .get('/filters', queryParameters: {'category': categoryId});
      final data = response.data;
      final List<dynamic> attrsRaw = data['attributes'] ?? [];
      final all = attrsRaw.map((a) => AttributeDefinition.fromJson(a)).toList();
      final base = all.where((a) => !a.isVariant).toList();
      final required =
          base.where((a) => a.isRequired || a.name == 'condition').toList();
      final optional =
          base.where((a) => !a.isRequired && a.name != 'condition').toList();
      final variant = all.where((a) => a.isVariant).toList();
      if (mounted)
        setState(() {
          _allAttrs = all;
          _requiredAttrs = required;
          _optionalAttrs = optional;
          if (!_prefilled) _addedOptionalNames = [];
          _variantAttrs = variant;
          if (!_prefilled && _varieties.isEmpty) {
            final defaultAttrs = _variantAttrs.take(3).toList();
            _varieties = [
              Variety(
                selectedAttrs: defaultAttrs
                    .map((a) => SelectedAttr(attrId: a.id, value: ''))
                    .toList(),
                price: '',
                stock: '',
                unlimitedStock: false,
                image: null,
              )
            ];
          }
          _customSuggestions = {};
        });
    } catch (_) {
      if (mounted)
        setState(() {
          _attributesError = true;
        });
    }
  }

  // ── Image / Video picking ───────────
  Future<void> _pickImages() async {
    final l10n = AppLocalizations.of(context);
    final currentTotal = _newImages.length + _existingImageUrls.length;
    if (currentTotal >= _maxImages) {
      _showSnack(l10n.translate('max_images_reached'), AppColors.error);
      return;
    }
    final remainingSlots = _maxImages - currentTotal;

    try {
      final List<XFile>? files =
          await _picker.pickMultiImage(imageQuality: 85, maxWidth: 1200);
      if (files != null && files.isNotEmpty) {
        final selected = files.take(remainingSlots).toList();
        final valid = <XFile>[];
        for (final file in selected) {
          final size = await file.length();
          if (size > 5 * 1024 * 1024) {
            _showSnack(l10n.translate('image_too_large'), AppColors.error);
          } else {
            valid.add(file);
          }
        }
        if (valid.isNotEmpty && mounted) {
          setState(() => _newImages.addAll(valid));
        }
        return;
      }
    } catch (_) {}

    // Fallback single picker with loop
    while (_newImages.length + _existingImageUrls.length < _maxImages) {
      final XFile? file =
          await _picker.pickImage(source: ImageSource.gallery, imageQuality: 85, maxWidth: 1200);
      if (file == null) break;
      final size = await file.length();
      if (size > 5 * 1024 * 1024) {
        _showSnack(l10n.translate('image_too_large'), AppColors.error);
        continue;
      }
      setState(() => _newImages.add(file));
      if (!mounted) break;
      final again = await showDialog<bool>(
        context: context,
        builder: (_) => AlertDialog(
          title: Text(l10n.translate('add_another_image')),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: Text(l10n.translate('done'))),
            TextButton(
                onPressed: () => Navigator.pop(context, true),
                child: Text(l10n.translate('add_more'))),
          ],
        ),
      );
      if (again != true) break;
    }
  }

  void _removeNewImage(int index) => setState(() => _newImages.removeAt(index));

  void _removeExistingImage(int index) {
    setState(() {
      _existingImageUrls.removeAt(index);
      if (index < _existingImageBlobIds.length) {
        _existingImageBlobIds.removeAt(index);
      }
    });
  }

  Future<void> _pickVideo() async {
    final l10n = AppLocalizations.of(context);
    if (_newVideo != null || _existingVideoUrls.isNotEmpty || _existingVideoBlobIds.isNotEmpty) {
      _showSnack(l10n.translate('only_one_video_allowed'), AppColors.error);
      return;
    }
    final XFile? file = await _picker.pickVideo(source: ImageSource.gallery);
    if (file != null) {
      final size = await file.length();
      if (size > 50 * 1024 * 1024) {
        _showSnack(l10n.translate('video_too_large'), AppColors.error);
        return;
      }
      setState(() => _newVideo = file);
    }
  }

  void _removeVideo() => setState(() => _newVideo = null);

  void _removeExistingVideo(int index) {
    setState(() {
      _existingVideoUrls.removeAt(index);
      if (index < _existingVideoBlobIds.length) {
        _existingVideoBlobIds.removeAt(index);
      }
    });
  }

  // ── Optional attributes ───────────
  void _addOptionalAttr(String name) {
    if (!_addedOptionalNames.contains(name))
      setState(() => _addedOptionalNames.add(name));
  }

  void _removeOptionalAttr(String name) {
    setState(() {
      _addedOptionalNames.remove(name);
      _attrValues.remove(name);
    });
  }

  // ── Variant management ───────────
  void _addVariety() {
    final defaultAttrs = _variantAttrs.take(3).toList();
    setState(() => _varieties.add(Variety(
          selectedAttrs:
              defaultAttrs.map((a) => SelectedAttr(attrId: a.id, value: '')).toList(),
          price: '',
          stock: '',
          unlimitedStock: false,
          image: null,
        )));
  }

  void _removeVariety(int index) {
    if (index != 0) setState(() => _varieties.removeAt(index));
  }

  void _addSpecificAttribute(int varietyIdx, int attrId) {
    setState(() {
      _varieties[varietyIdx].selectedAttrs.add(SelectedAttr(attrId: attrId, value: ''));
    });
  }

  void _removeAttributeFromVariety(int varietyIdx, int attrId) {
    setState(() =>
        _varieties[varietyIdx].selectedAttrs.removeWhere((s) => s.attrId == attrId));
  }

  void _updateAttrValue(int varietyIdx, int attrId, String value) {
    setState(() {
      final idx =
          _varieties[varietyIdx].selectedAttrs.indexWhere((s) => s.attrId == attrId);
      if (idx != -1) _varieties[varietyIdx].selectedAttrs[idx].value = value;
    });
  }

  void _addCustomSuggestion(String attrName, String value) {
    if (value.trim().isEmpty) return;
    setState(() {
      _customSuggestions.putIfAbsent(attrName, () => []);
      if (!_customSuggestions[attrName]!.contains(value.trim()))
        _customSuggestions[attrName]!.add(value.trim());
    });
  }

  void _updateVarietyField(int varietyIdx, String field, String value) {
    setState(() {
      if (field == 'price')
        _varieties[varietyIdx].price = value;
      else if (field == 'stock')
        _varieties[varietyIdx].stock = value;
      else if (field == 'unlimited')
        _varieties[varietyIdx].unlimitedStock = value == 'true';
    });
    _syncVariantController(varietyIdx, field);
  }

  List<String> _getSuggestions(AttributeDefinition attr) =>
      [...{...attr.values, ...(_customSuggestions[attr.name] ?? [])}];

  // ── Bulk validation helpers ───────────
  bool get _isValidMinBulkQty {
    if (!_bulkEnabled) return true;
    final val = int.tryParse(_minBulkQtyCtrl.text.trim());
    return val != null && val > 0;
  }

  bool get _isValidMaxQtyPerDay {
    if (!_bulkEnabled) return true;
    final val = _maxQtyPerDayCtrl.text.trim();
    if (val.isEmpty) return true;
    final intVal = int.tryParse(val);
    return intVal != null && intVal > 0;
  }

  // ── Discount / Shipping validation ───────────
  bool get _isValidDiscount {
    final val = double.tryParse(_discountValueCtrl.text.trim());
    if (val == null) return _discountValueCtrl.text.trim().isEmpty;
    if (val <= 0) return false;
    if (_discountType == 'percent' && val > 100) return false;
    return true;
  }

  bool get _isValidShippingValue {
    if (!_sellerPaysDelivery || _deliverySubsidyType == 'full') return true;
    final val = double.tryParse(_deliverySubsidyValueCtrl.text.trim());
    if (val == null) return false;
    return val > 0 && val <= 100;
  }

  // ── Submit ───────────────────────────
  Future<void> _submitProduct() async {
    final l10n = AppLocalizations.of(context);
    if (!_formKey.currentState!.validate()) return;

    // Additional manual validations for fields not covered by TextFormField validators
    if (!_isValidDiscount) {
      _showSnack(l10n.translate('invalid_discount_value'), AppColors.error);
      return;
    }

    if (!_isValidShippingValue) {
      _showSnack(l10n.translate('invalid_shipping_subsidy'), AppColors.error);
      return;
    }

    if (_bulkEnabled) {
      if (!_isValidMinBulkQty) {
        _showSnack(
            '${l10n.translate('minimum_order_quantity_label')} must be a positive number',
            AppColors.error);
        return;
      }
      if (!_isValidMaxQtyPerDay) {
        _showSnack(
            '${l10n.translate('max_quantity_per_day_label')} must be a positive number',
            AppColors.error);
        return;
      }
    }

    final categoryId = _subCategoryId ?? _mainCategoryId;
    if (categoryId == null) {
      _showSnack(l10n.translate('select_category_error'), AppColors.error);
      return;
    }
    if (_newImages.isEmpty && _existingImageUrls.isEmpty && widget.product == null) {
      _showSnack(l10n.translate('image_required_error'), AppColors.error);
      return;
    }

    setState(() => _isSubmitting = true);
    try {
      final formFields = <String, String>{
        'product[title]': _titleCtrl.text.trim(),
        'product[description]': _descCtrl.text.trim(),
        'product[category_id]': categoryId.toString(),
        'product[product_attributes]': jsonEncode(_attrValues),
      };

      // Price and stock only for non-variant products
      if (_variantAttrs.isEmpty) {
        if (!_bulkEnabled) {
          formFields['product[price]'] = _priceCtrl.text.trim();
          formFields['product[stock]'] = _stockCtrl.text.trim();
        } else {
          // bulk, no variants: price sent, stock optional (unlimited if empty)
          formFields['product[price]'] = _priceCtrl.text.trim();
          formFields['product[stock]'] =
              _stockCtrl.text.trim().isEmpty ? '' : _stockCtrl.text.trim();
        }
      }

      // Discount
      if (_discountValueCtrl.text.trim().isNotEmpty && _isValidDiscount) {
        formFields['product[discount_type]'] = _discountType;
        formFields['product[discount_value]'] = _discountValueCtrl.text.trim();
      }

      // Shipping
      if (_sellerPaysDelivery) {
        if (_deliverySubsidyType == 'percent' &&
            _deliverySubsidyValueCtrl.text.trim() == '100') {
          formFields['product[seller_pays_shipping]'] = 'true';
          formFields['product[shipping_subsidy_type]'] = 'full';
          formFields['product[shipping_subsidy_value]'] = '';
        } else if (_deliverySubsidyType == 'percent') {
          formFields['product[seller_pays_shipping]'] = 'true';
          formFields['product[shipping_subsidy_type]'] = 'percent';
          formFields['product[shipping_subsidy_value]'] =
              _deliverySubsidyValueCtrl.text.trim();
        } else {
          formFields['product[seller_pays_shipping]'] = 'true';
          formFields['product[shipping_subsidy_type]'] = 'full';
          formFields['product[shipping_subsidy_value]'] = '';
        }
      } else {
        formFields['product[seller_pays_shipping]'] = 'false';
      }

      // Bulk
      formFields['product[bulk_enabled]'] = _bulkEnabled ? 'true' : 'false';
      if (_bulkEnabled) {
        formFields['product[minimum_bulk_quantity]'] =
            _minBulkQtyCtrl.text.trim().isEmpty ? '1' : _minBulkQtyCtrl.text.trim();
        formFields['product[max_quantity_per_day]'] =
            _maxQtyPerDayCtrl.text.trim().isEmpty
                ? ''
                : _maxQtyPerDayCtrl.text.trim();
      } else {
        formFields['product[minimum_bulk_quantity]'] = '1';
        formFields['product[max_quantity_per_day]'] = '';
      }

      // Dimensions (required for delivery)
      formFields['product[weight_kg]'] = _weightCtrl.text.trim();
      formFields['product[length_cm]'] = _lengthCtrl.text.trim();
      formFields['product[width_cm]'] = _widthCtrl.text.trim();
      formFields['product[height_cm]'] = _heightCtrl.text.trim();

      // Keep image IDs
      if (_existingImageBlobIds.isNotEmpty) {
        formFields['product[keep_image_ids]'] = _existingImageBlobIds.join(',');
      }

      // Keep video IDs
      if (_existingVideoBlobIds.isNotEmpty) {
        formFields['product[keep_video_ids]'] = _existingVideoBlobIds.join(',');
      }

      // Variants
      if (_variantAttrs.isNotEmpty && _varieties.isNotEmpty) {
        final variantsPayload = _varieties.map((v) {
          final attrs = <String, String>{};
          for (final sel in v.selectedAttrs) {
            final attr = _variantAttrs.firstWhere((a) => a.id == sel.attrId);
            attrs[attr.name] = sel.value;
          }
          final map = <String, dynamic>{
            'attributes': attrs,
            'price': v.price,
            'unlimited_stock': v.unlimitedStock,
            'stock': v.unlimitedStock ? '' : v.stock,
          };
          return map;
        }).toList();
        formFields['product[variants]'] = jsonEncode(variantsPayload);
      }

      final formData = FormData();
      formFields.forEach((key, value) {
        formData.fields.add(MapEntry(key, value));
      });

      for (final file in _newImages) {
        final MultipartFile multipartFile = kIsWeb
            ? MultipartFile.fromBytes(await file.readAsBytes(), filename: file.name)
            : await MultipartFile.fromFile(file.path, filename: file.name);
        formData.files.add(MapEntry('product[images][]', multipartFile));
      }

      if (_newVideo != null) {
        final videoFile = _newVideo!;
        final MultipartFile multipartVideo = kIsWeb
            ? MultipartFile.fromBytes(await videoFile.readAsBytes(),
                filename: videoFile.name)
            : await MultipartFile.fromFile(videoFile.path, filename: videoFile.name);
        formData.files.add(MapEntry('product[videos][]', multipartVideo));
      }

      final url =
          widget.product != null ? '/products/${widget.product!.id}' : '/products';
      if (widget.product != null) {
        await ApiClient.instance.put(url, data: formData);
      } else {
        await ApiClient.instance.post(url, data: formData);
      }

      _showSnack(
          widget.product != null
              ? l10n.translate('product_updated')
              : l10n.translate('product_added'),
          AppColors.textPrimary);
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      _showSnack(l10n.translate('submit_failed_generic'), AppColors.error);
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  void _showSnack(String msg, Color color) =>
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(msg),
          backgroundColor: color,
          elevation: 0,
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppShapes.radiusSm)),
          margin: const EdgeInsets.all(AppSpacing.lg),
          padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.lg, vertical: AppSpacing.md),
          duration: const Duration(seconds: 2),
        ),
      );

  PreferredSizeWidget _buildAppBar(String title, String subtitle) {
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
    final isEditing = widget.product != null;
    final textTheme = Theme.of(context).textTheme;

    if (isEditing && _loadingEditData) {
      return Scaffold(
        backgroundColor: AppColors.pageBackground,
        appBar: _buildAppBar(
          isEditing
              ? l10n.translate('edit_product_title')
              : l10n.translate('add_product_title'),
          '',
        ),
        body: const Center(
            child: CircularProgressIndicator(color: AppColors.primary)),
      );
    }

    return Scaffold(
      backgroundColor: AppColors.pageBackground,
      appBar: _buildAppBar(
        isEditing
            ? l10n.translate('edit_product_title')
            : l10n.translate('add_product_title'),
        isEditing
            ? l10n.translate('update_product_title')
            : l10n.translate('list_product_title'),
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 30),
          children: [
            // 1. Title
            _buildCard(children: [
              _sectionHeader(l10n.translate('title_label')),
              const SizedBox(height: AppSpacing.sm),
              _textField(
                  controller: _titleCtrl,
                  label: l10n.translate('product_name_label'),
                  hint: l10n.translate('title_hint'),
                  validator: (v) => (v == null || v.trim().isEmpty)
                      ? l10n.translate('title_required')
                      : null),
            ]),
            const SizedBox(height: 12),

            // 2. Bulk / Wholesale
            _buildCard(children: [
              Row(children: [
                _sectionHeader(l10n.translate('bulk_wholesale_label')),
                const SizedBox(width: 8),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.purple.shade50,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(l10n.translate('optional_badge'),
                      style: TextStyle(
                          fontSize: 11, color: Colors.purple.shade700)),
                ),
              ]),
              const SizedBox(height: 6),
              Text(
                l10n.translate('bulk_wholesale_desc') +
                    (_variantAttrs.isNotEmpty
                        ? ' Stock per variant is set below.'
                        : ' Set stock here (leave blank for unlimited).'),
                style: textTheme.bodySmall
                    ?.copyWith(color: Colors.purple.shade700),
              ),
              const SizedBox(height: 12),
              Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                        child: Text(l10n.translate('enable_bulk_label'),
                            style: textTheme.bodyMedium
                                ?.copyWith(fontWeight: FontWeight.w600))),
                    Transform.scale(
                      scale: 0.8,
                      child: Switch(
                        value: _bulkEnabled,
                        onChanged: (v) => setState(() {
                          _bulkEnabled = v;
                          if (!v) {
                            _minBulkQtyCtrl.clear();
                            _maxQtyPerDayCtrl.clear();
                            _stockCtrl.clear();
                          }
                        }),
                        activeColor: Colors.purple,
                        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                    ),
                  ]),
              if (_bulkEnabled) ...[
                const SizedBox(height: AppSpacing.sm),
                _textField(
                  controller: _minBulkQtyCtrl,
                  label: l10n.translate('minimum_order_quantity_label'),
                  hint: 'e.g. 24',
                  keyboardType: TextInputType.number,
                ),
                // Show stock field ONLY if no variants – hidden when variants exist
                if (_variantAttrs.isEmpty) ...[
                  const SizedBox(height: AppSpacing.sm),
                  _textField(
                    controller: _stockCtrl,
                    label: l10n.translate('available_stock_label'),
                    hint: 'Leave blank for unlimited',
                    keyboardType: TextInputType.number,
                  ),
                ],
                const SizedBox(height: AppSpacing.sm),
                _textField(
                  controller: _maxQtyPerDayCtrl,
                  label: l10n.translate('max_quantity_per_day_label'),
                  hint: 'Leave blank for unlimited',
                  keyboardType: TextInputType.number,
                ),
              ],
            ]),
            const SizedBox(height: 12),

            // 3. Dimensions & Weight (Required for delivery)
            _buildCard(children: [
              _sectionHeader(l10n.translate('dimensions_label') + ' *'),
              const SizedBox(height: 4),
              Text(
                l10n.translate('dimensions_required_desc'),
                style: textTheme.bodySmall?.copyWith(color: AppColors.textMuted),
              ),
              const SizedBox(height: AppSpacing.sm),
              Row(children: [
                Expanded(
                    child: _textField(
                        controller: _weightCtrl,
                        label: l10n.translate('weight_kg_label'),
                        hint: 'kg',
                        keyboardType: TextInputType.number,
                        validator: _dimensionValidator)),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                    child: _textField(
                        controller: _lengthCtrl,
                        label: l10n.translate('length_cm_label'),
                        hint: 'cm',
                        keyboardType: TextInputType.number,
                        validator: _dimensionValidator)),
              ]),
              const SizedBox(height: AppSpacing.sm),
              Row(children: [
                Expanded(
                    child: _textField(
                        controller: _widthCtrl,
                        label: l10n.translate('width_cm_label'),
                        hint: 'cm',
                        keyboardType: TextInputType.number,
                        validator: _dimensionValidator)),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                    child: _textField(
                        controller: _heightCtrl,
                        label: l10n.translate('height_cm_label'),
                        hint: 'cm',
                        keyboardType: TextInputType.number,
                        validator: _dimensionValidator)),
              ]),
            ]),
            const SizedBox(height: 12),

            // 4. Category
            _buildCard(children: [
              _sectionHeader(l10n.translate('main_category_label')),
              const SizedBox(height: AppSpacing.sm),
              if (_categoriesError)
                Column(children: [
                  Text(l10n.translate('category_load_error'),
                      style:
                          textTheme.bodyMedium?.copyWith(color: AppColors.error)),
                  TextButton(
                      onPressed: _loadCategories,
                      child: Text(l10n.translate('retry')))
                ])
              else if (_loadingCategories)
                const Center(
                    child:
                        CircularProgressIndicator(color: AppColors.primary))
              else if (_mainCategories.isEmpty)
                Text(l10n.translate('no_categories_available'),
                    style: textTheme.bodyMedium
                        ?.copyWith(color: AppColors.textMuted))
              else ...[
                _dropdown<int>(
                  value: (_mainCategoryId != null &&
                          _mainCategories.any((c) => c['id'] == _mainCategoryId))
                      ? _mainCategoryId
                      : null,
                  hint: l10n.translate('select_main_category'),
                  items: _mainCategories
                      .map<DropdownMenuItem<int>>((c) => DropdownMenuItem<int>(
                          value: c['id'] as int, child: Text(c['name'])))
                      .toList(),
                  onChanged: (v) {
                    if (widget.product != null && v == _mainCategoryId) return;
                    setState(() {
                      _mainCategoryId = v;
                      _subCategoryId = null;
                      _subCategories = [];
                      _requiredAttrs = [];
                      _optionalAttrs = [];
                      _addedOptionalNames = [];
                      _attrValues = {};
                      _variantAttrs = [];
                      if (widget.product == null) _varieties = [];
                    });
                    if (v != null) _loadSubCategories(v);
                  },
                ),
                if (_subCategories.isNotEmpty) ...[
                  const SizedBox(height: AppSpacing.sm),
                  Text(l10n.translate('subcategory_label'),
                      style: textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                          color: AppColors.textPrimary)),
                  const SizedBox(height: AppSpacing.xs),
                  _dropdown<int>(
                    value: (_subCategoryId != null &&
                            _subCategories.any((c) => c['id'] == _subCategoryId))
                        ? _subCategoryId
                        : null,
                    hint: l10n.translate('select_subcategory_optional'),
                    items: [
                      DropdownMenuItem<int>(
                          value: null,
                          child: Text(l10n.translate('none_use_main_only'))),
                      ..._subCategories.map<DropdownMenuItem<int>>((c) =>
                          DropdownMenuItem<int>(
                              value: c['id'] as int, child: Text(c['name'])))
                    ],
                    onChanged: (v) {
                      setState(() {
                        _subCategoryId = v;
                        if (v != null) _loadAttributes(v);
                      });
                    },
                  ),
                ],
              ],
            ]),
            const SizedBox(height: 12),

            // 5. Description
            _buildCard(children: [
              _sectionHeader(l10n.translate('description_label')),
              const SizedBox(height: AppSpacing.sm),
              _textField(
                  controller: _descCtrl,
                  label: '',
                  hint: l10n.translate('description_hint'),
                  maxLines: 4,
                  validator: (v) => (v == null || v.trim().isEmpty)
                      ? l10n.translate('description_required')
                      : null),
            ]),
            const SizedBox(height: 12),

            // 6. Attributes
            if (_attributesError)
              _buildCard(children: [
                Text(l10n.translate('attributes_load_error'),
                    style:
                        textTheme.bodyMedium?.copyWith(color: AppColors.error)),
                TextButton(
                  onPressed: () =>
                      _loadAttributes(_subCategoryId ?? _mainCategoryId ?? 0),
                  child: Text(l10n.translate('retry')),
                ),
              ])
            else if (_requiredAttrs.isNotEmpty || _optionalAttrs.isNotEmpty) ...[
              _buildCard(children: [
                _sectionHeader(l10n.translate('product_attributes_label')),
                const SizedBox(height: AppSpacing.sm),
                ..._requiredAttrs
                    .map((attr) => _buildAttrRow(attr, required: true)),
                ..._addedOptionalNames.map((name) => _buildAttrRow(
                    _optionalAttrs.firstWhere((a) => a.name == name),
                    required: false,
                    removable: true)),
                if (_optionalAttrs
                    .any((a) => !_addedOptionalNames.contains(a.name)))
                  TextButton.icon(
                    onPressed: () => showDialog(
                        context: context,
                        builder: (_) => SimpleDialog(
                            title: Text(l10n.translate('add_attribute_title')),
                            children: _optionalAttrs
                                .where((a) =>
                                    !_addedOptionalNames.contains(a.name))
                                .map<Widget>((a) => SimpleDialogOption(
                                    onPressed: () {
                                      _addOptionalAttr(a.name);
                                      Navigator.pop(context);
                                    },
                                    child: Text(a.displayName,
                                        style: const TextStyle(fontSize: 15))))
                                .toList())),
                    icon: const Icon(Icons.add_circle_outline,
                        color: AppColors.primary, size: 18),
                    label: Text(l10n.translate('add_attribute'),
                        style: textTheme.bodyMedium
                            ?.copyWith(color: AppColors.primary)),
                  ),
              ]),
              const SizedBox(height: 12),
            ],

            // 7. Variants
            if (_variantAttrs.isNotEmpty) ...[
              ...List.generate(_varieties.length, (idx) {
                final v = _varieties[idx];
                final isDefault = idx == 0;
                final usedIds = v.selectedAttrs.map((s) => s.attrId).toSet();
                final remainingAttrs = _variantAttrs
                    .where((a) => !usedIds.contains(a.id))
                    .toList();
                return Container(
                  margin: const EdgeInsets.only(bottom: AppSpacing.md),
                  padding: const EdgeInsets.all(AppSpacing.md),
                  decoration: BoxDecoration(
                      color: AppColors.cardBackground,
                      borderRadius:
                          BorderRadius.circular(AppShapes.radiusMd),
                      boxShadow: [
                        BoxShadow(
                            color: Colors.black.withOpacity(0.04),
                            blurRadius: 8,
                            offset: const Offset(0, 2))
                      ]),
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                            mainAxisAlignment:
                                MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                  isDefault
                                      ? l10n.translate('default_variant')
                                      : l10n
                                          .translate('variety_label')
                                          .replaceAll(
                                              '{index}', (idx + 1).toString()),
                                  style: textTheme.bodyLarge?.copyWith(
                                      fontWeight: FontWeight.w600,
                                      color: AppColors.textPrimary)),
                              if (!isDefault)
                                IconButton(
                                    icon: const Icon(Icons.delete_outline,
                                        size: 20, color: AppColors.error),
                                    onPressed: () => _removeVariety(idx)),
                            ]),
                        const SizedBox(height: AppSpacing.sm),
                        ...v.selectedAttrs.map((sel) {
                          final attrDef = _variantAttrs
                              .firstWhere((a) => a.id == sel.attrId);
                          final suggestions = _getSuggestions(attrDef);
                          return Padding(
                            padding:
                                const EdgeInsets.only(bottom: AppSpacing.xs),
                            child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  SizedBox(
                                      width: 90,
                                      child: Padding(
                                          padding:
                                              const EdgeInsets.only(top: 12),
                                          child: Text(attrDef.displayName,
                                              style: textTheme.bodyMedium
                                                  ?.copyWith(
                                                      color: AppColors
                                                          .textPrimary)))),
                                  const SizedBox(width: AppSpacing.xs),
                                  Expanded(
                                    child: Autocomplete<String>(
                                      optionsBuilder: (tv) => suggestions
                                          .where((s) => s
                                              .toLowerCase()
                                              .contains(tv.text.toLowerCase())),
                                      onSelected: (s) =>
                                          _updateAttrValue(
                                              idx, sel.attrId, s),
                                      initialValue:
                                          TextEditingValue(text: sel.value),
                                      fieldViewBuilder: (context, ctrl,
                                              focusNode, onSubmitted) =>
                                          TextFormField(
                                        controller: ctrl,
                                        focusNode: focusNode,
                                        onChanged: (val) => _updateAttrValue(
                                            idx, sel.attrId, val),
                                        decoration: InputDecoration(
                                          hintText: l10n
                                              .translate('enter_value')
                                              .replaceAll('{displayName}',
                                                  attrDef.displayName),
                                          filled: true,
                                          fillColor: AppColors.hoverState,
                                          contentPadding:
                                              const EdgeInsets.symmetric(
                                                  horizontal: 12,
                                                  vertical: 12),
                                          border: OutlineInputBorder(
                                              borderRadius:
                                                  BorderRadius.circular(
                                                      AppShapes.radiusSm),
                                              borderSide: const BorderSide(
                                                  color:
                                                      AppColors.borderLight)),
                                          focusedBorder: OutlineInputBorder(
                                              borderRadius:
                                                  BorderRadius.circular(
                                                      AppShapes.radiusSm),
                                              borderSide: const BorderSide(
                                                  color: AppColors.primary,
                                                  width: 2)),
                                        ),
                                        style: textTheme.bodyLarge?.copyWith(
                                            color: AppColors.textPrimary),
                                      ),
                                    ),
                                  ),
                                  IconButton(
                                      icon: const Icon(Icons.add,
                                          size: 16,
                                          color: AppColors.textMuted),
                                      onPressed: () =>
                                          _addCustomSuggestion(
                                              attrDef.name, sel.value)),
                                  IconButton(
                                      icon: const Icon(Icons.close,
                                          size: 16,
                                          color: AppColors.textMuted),
                                      onPressed: () =>
                                          _removeAttributeFromVariety(
                                              idx, sel.attrId)),
                                ]),
                          );
                        }),
                        if (remainingAttrs.isNotEmpty)
                          Padding(
                              padding: const EdgeInsets.only(
                                  bottom: AppSpacing.sm),
                              child: DropdownButtonFormField<int>(
                                value: null,
                                decoration: InputDecoration(
                                    hintText: '+ Add attribute',
                                    contentPadding:
                                        const EdgeInsets.symmetric(
                                            horizontal: 12, vertical: 8),
                                    border: OutlineInputBorder(
                                        borderRadius:
                                            BorderRadius.circular(
                                                AppShapes.radiusSm)),
                                    enabledBorder: OutlineInputBorder(
                                        borderRadius:
                                            BorderRadius.circular(
                                                AppShapes.radiusSm),
                                        borderSide: const BorderSide(
                                            color:
                                                AppColors.borderLight)),
                                    focusedBorder: OutlineInputBorder(
                                        borderRadius:
                                            BorderRadius.circular(
                                                AppShapes.radiusSm),
                                        borderSide: const BorderSide(
                                            color: AppColors.primary,
                                            width: 2))),
                                items: remainingAttrs
                                    .map((attr) => DropdownMenuItem<int>(
                                        value: attr.id,
                                        child: Text(attr.displayName,
                                            style: const TextStyle(
                                                fontSize: 13))))
                                    .toList(),
                                onChanged: (val) {
                                  if (val != null)
                                    _addSpecificAttribute(idx, val);
                                },
                              )),
                        const SizedBox(height: AppSpacing.sm),
                        _textField(
                            controller:
                                _getVariantController(idx, 'price'),
                            label: l10n.translate('price_label'),
                            hint: '0',
                            keyboardType: TextInputType.number,
                            onChanged: (val) =>
                                _updateVarietyField(idx, 'price', val)),
                        // Unlimited stock toggle + stock field
                        SwitchListTile(
                          title: Text(l10n.translate('unlimited_stock')),
                          value: v.unlimitedStock,
                          onChanged: (val) {
                            _updateVarietyField(idx, 'unlimited', val ? 'true' : 'false');
                          },
                          activeColor: AppColors.primary,
                          contentPadding: EdgeInsets.zero,
                          dense: true,
                        ),
                        if (!v.unlimitedStock) ...[
                          const SizedBox(height: AppSpacing.sm),
                          _textField(
                              controller:
                                  _getVariantController(idx, 'stock'),
                              label: l10n.translate('stock_label'),
                              hint: '0',
                              keyboardType: TextInputType.number,
                              onChanged: (val) =>
                                  _updateVarietyField(idx, 'stock', val)),
                        ],
                      ]),
                );
              }),
              Align(
                  alignment: Alignment.centerRight,
                  child: TextButton.icon(
                      onPressed: _addVariety,
                      icon: const Icon(Icons.add_circle_outline,
                          color: AppColors.primary, size: 18),
                      label: Text(l10n.translate('add_variety'),
                          style: textTheme.bodyMedium
                              ?.copyWith(color: AppColors.primary)))),
              const SizedBox(height: 12),
            ],

            // 8. Price (non-variant)
            if (_variantAttrs.isEmpty)
              _buildCard(children: [
                _sectionHeader(l10n.translate('price_label') + ' *'),
                const SizedBox(height: AppSpacing.sm),
                _textField(
                    controller: _priceCtrl,
                    label: '',
                    hint: 'e.g. 12,000',
                    keyboardType: TextInputType.number,
                    validator: (v) => (v == null || v.trim().isEmpty)
                        ? l10n.translate('price_required')
                        : null)
              ]),
            if (_variantAttrs.isEmpty) const SizedBox(height: 12),

            // 9. Stock (non-variant, non‑bulk)
            if (_variantAttrs.isEmpty && !_bulkEnabled) ...[
              _buildCard(children: [
                _sectionHeader(l10n.translate('stock_label') + ' *'),
                const SizedBox(height: AppSpacing.sm),
                _textField(
                    controller: _stockCtrl,
                    label: '',
                    hint: 'e.g. 50',
                    keyboardType: TextInputType.number,
                    validator: (v) => (v == null || v.trim().isEmpty)
                        ? l10n.translate('stock_required')
                        : null)
              ]),
              const SizedBox(height: 12),
            ],

            // 10. Discount – with live preview & validation
            _buildCard(children: [
              _sectionHeader(l10n.translate('offer_discount_label')),
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
                            DropdownMenuItem(
                                value: 'percent',
                                child: Text(
                                    l10n.translate('percentage_label'))),
                            DropdownMenuItem(
                                value: 'flat',
                                child: Text(
                                    l10n.translate('flat_amount_label')))
                          ],
                          onChanged: (v) =>
                              setState(() => _discountType = v!))),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                      flex: 1,
                      child: _textField(
                          controller: _discountValueCtrl,
                          label: '',
                          hint: '0',
                          keyboardType: TextInputType.number)),
                ],
              ),
              if (_discountPreview != null)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    _discountPreview!,
                    style: TextStyle(color: AppColors.primary, fontSize: 13),
                  ),
                ),
              if (_discountValueCtrl.text.trim().isNotEmpty &&
                  !_isValidDiscount)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    l10n.translate('invalid_discount_value'),
                    style: TextStyle(color: AppColors.error, fontSize: 12),
                  ),
                ),
            ]),
            const SizedBox(height: 12),

            // 11. Delivery Subsidy – only full / percent, 100% → free, negative blocked
            _buildCard(children: [
              _sectionHeader(l10n.translate('delivery_subsidy_label')),
              const SizedBox(height: AppSpacing.xs),
              Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                        child: Text(l10n.translate('pay_delivery_label'),
                            style: textTheme.bodyMedium?.copyWith(
                                fontWeight: FontWeight.w600,
                                color: AppColors.textPrimary))),
                    Transform.scale(
                      scale: 0.8,
                      child: Switch(
                          value: _sellerPaysDelivery,
                          onChanged: (v) =>
                              setState(() => _sellerPaysDelivery = v),
                          activeColor: AppColors.primary,
                          materialTapTargetSize:
                              MaterialTapTargetSize.shrinkWrap),
                    ),
                  ]),
              if (_sellerPaysDelivery) ...[
                const SizedBox(height: AppSpacing.sm),
                _dropdown<String>(
                    value: _deliverySubsidyType,
                    hint: l10n.translate('subsidy_type_label'),
                    items: [
                      DropdownMenuItem(
                          value: 'full',
                          child: Text(
                              l10n.translate('full_delivery_label'))),
                      DropdownMenuItem(
                          value: 'percent',
                          child: Text(l10n
                              .translate('percentage_delivery_label')))
                    ],
                    onChanged: (v) =>
                        setState(() => _deliverySubsidyType = v!)),
                if (_deliverySubsidyType == 'percent') ...[
                  const SizedBox(height: AppSpacing.sm),
                  _textField(
                      controller: _deliverySubsidyValueCtrl,
                      label: l10n.translate('percentage_input_label'),
                      hint: 'e.g., 50',
                      keyboardType: TextInputType.number),
                  if (_deliverySubsidyValueCtrl.text.trim().isNotEmpty &&
                      !_isValidShippingValue)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(
                        l10n.translate('invalid_shipping_subsidy'),
                        style: TextStyle(color: AppColors.error, fontSize: 12),
                      ),
                    ),
                ],
              ],
            ]),
            const SizedBox(height: 12),

            // 12. Images
            _buildCard(children: [
              _sectionHeader(l10n.translate('product_images_label')),
              const SizedBox(height: 2),
              Text(
                '${l10n.translate('at_least')} 1, ${l10n.translate('up_to')} 6 ${l10n.translate('images')}',
                style:
                    textTheme.bodySmall?.copyWith(color: AppColors.textMuted),
              ),
              const SizedBox(height: AppSpacing.sm),
              // Existing images with remove button
              if (_existingImageUrls.isNotEmpty)
                SizedBox(
                    height: 90,
                    child: ListView.separated(
                        scrollDirection: Axis.horizontal,
                        itemCount: _existingImageUrls.length,
                        separatorBuilder: (_, __) =>
                            const SizedBox(width: AppSpacing.sm),
                        itemBuilder: (ctx, i) {
                          return Stack(children: [
                            ClipRRect(
                                borderRadius: BorderRadius.circular(
                                    AppShapes.radiusMd),
                                child: Image.network(_existingImageUrls[i],
                                    width: 90,
                                    height: 90,
                                    fit: BoxFit.cover,
                                    errorBuilder: (_, __, ___) => const Icon(
                                        Icons.broken_image,
                                        size: 36,
                                        color: AppColors.textMuted))),
                            Positioned(
                                top: 4,
                                right: 4,
                                child: GestureDetector(
                                    onTap: () => _removeExistingImage(i),
                                    child: Container(
                                        padding: const EdgeInsets.all(4),
                                        decoration: const BoxDecoration(
                                            color: Colors.black54,
                                            shape: BoxShape.circle),
                                        child: const Icon(Icons.close,
                                            size: 14, color: Colors.white)))),
                          ]);
                        })),
              if (_existingImageUrls.isNotEmpty)
                const SizedBox(height: AppSpacing.sm),
              // New images
              if (_newImages.isNotEmpty)
                SizedBox(
                    height: 90,
                    child: ListView.separated(
                        scrollDirection: Axis.horizontal,
                        itemCount: _newImages.length + 1,
                        separatorBuilder: (_, __) =>
                            const SizedBox(width: AppSpacing.sm),
                        itemBuilder: (ctx, i) {
                          if (i == _newImages.length) return _addImageButton();
                          return Stack(children: [
                            ClipRRect(
                                borderRadius: BorderRadius.circular(
                                    AppShapes.radiusMd),
                                child: _buildImageWidget(_newImages[i])),
                            Positioned(
                                top: 4,
                                right: 4,
                                child: GestureDetector(
                                    onTap: () => _removeNewImage(i),
                                    child: Container(
                                        padding: const EdgeInsets.all(4),
                                        decoration: const BoxDecoration(
                                            color: Colors.black54,
                                            shape: BoxShape.circle),
                                        child: const Icon(Icons.close,
                                            size: 14, color: Colors.white)))),
                          ]);
                        }))
              else if (_existingImageUrls.isEmpty)
                _dashedUploadArea()
              else
                _addImageButton(),
            ]),

            // 13. Video
            _buildCard(children: [
              _sectionHeader(l10n.translate('product_video_label')),
              const SizedBox(height: 2),
              Text(
                '${l10n.translate('max')} 1 ${l10n.translate('video')}, ${l10n.translate('up_to')} 50 MB',
                style:
                    textTheme.bodySmall?.copyWith(color: AppColors.textMuted),
              ),
              const SizedBox(height: AppSpacing.sm),
              // Existing video with remove
              if (_existingVideoUrls.isNotEmpty)
                Row(children: [
                  Container(
                      width: 80,
                      height: 80,
                      decoration: BoxDecoration(
                          color: Colors.black,
                          borderRadius:
                              BorderRadius.circular(AppShapes.radiusMd)),
                      child: Center(
                          child: Icon(Icons.videocam,
                              color: Colors.white, size: 28))),
                  const SizedBox(width: 8),
                  TextButton.icon(
                      onPressed: () => _removeExistingVideo(0),
                      icon: const Icon(Icons.delete,
                          size: 16, color: AppColors.error),
                      label: Text(l10n.translate('remove_video'),
                          style: TextStyle(color: AppColors.error))),
                ]),
              if (_newVideo != null)
                Row(children: [
                  Container(
                      width: 80,
                      height: 80,
                      decoration: BoxDecoration(
                          color: Colors.black,
                          borderRadius:
                              BorderRadius.circular(AppShapes.radiusMd)),
                      child: Center(
                          child: Icon(Icons.videocam,
                              color: Colors.white, size: 28))),
                  const SizedBox(width: 8),
                  TextButton.icon(
                      onPressed: _removeVideo,
                      icon: const Icon(Icons.delete,
                          size: 16, color: AppColors.error),
                      label: Text(l10n.translate('remove_video'),
                          style: TextStyle(color: AppColors.error))),
                ]),
              if (_existingVideoUrls.isEmpty && _newVideo == null)
                _addVideoButton(),
            ]),
            const SizedBox(height: 24),

            SizedBox(
                height: 48,
                child: ElevatedButton(
                  onPressed: _isSubmitting ? null : _submitProduct,
                  style: AppComponentStyles.primaryButton.copyWith(
                      shape: WidgetStatePropertyAll(RoundedRectangleBorder(
                          borderRadius:
                              BorderRadius.circular(AppShapes.radiusSm)))),
                  child: _isSubmitting
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white))
                      : Text(
                          isEditing
                              ? l10n.translate('update_product_title')
                              : l10n.translate('add_product_title'),
                          style: const TextStyle(
                              fontSize: 15, fontWeight: FontWeight.w700)),
                )),
          ],
        ),
      ),
    );
  }

  String? _dimensionValidator(String? value) {
    if (value == null || value.trim().isEmpty) {
      return AppLocalizations.of(context).translate('required_field');
    }
    final val = double.tryParse(value);
    if (val == null || val <= 0) {
      return AppLocalizations.of(context).translate('must_be_positive');
    }
    return null;
  }

  Widget _sectionHeader(String text) => Text(text,
      style: Theme.of(context)
          .textTheme
          .titleMedium
          ?.copyWith(fontWeight: FontWeight.w700, color: AppColors.textPrimary));

  Widget _buildCard({required List<Widget> children}) => Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
          color: AppColors.cardBackground,
          borderRadius: BorderRadius.circular(AppShapes.radiusMd)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: children));

  Widget _textField(
      {required TextEditingController controller,
      required String label,
      String? hint,
      int maxLines = 1,
      TextInputType? keyboardType,
      ValueChanged<String>? onChanged,
      FormFieldValidator<String>? validator}) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      if (label.isNotEmpty) ...[
        Text(label,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
        const SizedBox(height: AppSpacing.xs)
      ],
      TextFormField(
        controller: controller,
        maxLines: maxLines,
        keyboardType: keyboardType,
        onChanged: onChanged,
        validator: validator,
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: Theme.of(context)
              .textTheme
              .bodyMedium
              ?.copyWith(color: AppColors.textMuted),
          filled: true,
          fillColor: AppColors.hoverState,
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(AppShapes.radiusSm),
              borderSide: const BorderSide(color: AppColors.borderLight)),
          enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(AppShapes.radiusSm),
              borderSide: const BorderSide(color: AppColors.borderLight)),
          focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(AppShapes.radiusSm),
              borderSide:
                  const BorderSide(color: AppColors.primary, width: 2)),
        ),
        style: Theme.of(context)
            .textTheme
            .bodyLarge
            ?.copyWith(color: AppColors.textPrimary),
      ),
    ]);
  }

  Widget _dropdown<T>(
      {required T? value,
      String? hint,
      required List<DropdownMenuItem<T>> items,
      required ValueChanged<T?> onChanged}) {
    return Container(
        height: 48,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        decoration: BoxDecoration(
            color: AppColors.hoverState,
            borderRadius: BorderRadius.circular(AppShapes.radiusSm),
            border: Border.all(color: AppColors.borderLight)),
        child: DropdownButtonHideUnderline(
          child: DropdownButton<T>(
              value: value,
              hint: hint != null
                  ? Text(hint,
                      style: Theme.of(context)
                          .textTheme
                          .bodyMedium
                          ?.copyWith(color: AppColors.textMuted))
                  : null,
              items: items,
              onChanged: onChanged,
              isExpanded: true,
              icon: const Icon(Icons.expand_more_rounded,
                  color: AppColors.textMuted, size: 20),
              style: Theme.of(context)
                  .textTheme
                  .bodyLarge
                  ?.copyWith(color: AppColors.textPrimary),
              dropdownColor: AppColors.cardBackground,
              borderRadius: BorderRadius.circular(AppShapes.radiusSm)),
        ));
  }

  Widget _dashedUploadArea() {
    final l10n = AppLocalizations.of(context);
    return GestureDetector(
      onTap: _pickImages,
      child: Container(
          width: double.infinity,
          height: 120,
          decoration: BoxDecoration(
              border: Border.all(color: AppColors.borderLight, width: 1),
              borderRadius: BorderRadius.circular(AppShapes.radiusMd),
              color: AppColors.hoverState),
          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            Container(
                padding: const EdgeInsets.all(10),
                decoration: const BoxDecoration(
                    shape: BoxShape.circle, color: AppColors.cardBackground),
                child: const Icon(Icons.add_a_photo_outlined,
                    size: 24, color: AppColors.textMuted)),
            const SizedBox(height: 10),
            Text(l10n.translate('add_product_images_hint'),
                style: Theme.of(context)
                    .textTheme
                    .bodyMedium
                    ?.copyWith(fontWeight: FontWeight.w500)),
            const SizedBox(height: 4),
            Text(l10n.translate('image_format_hint'),
                style: Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.copyWith(fontSize: 12, color: AppColors.textMuted)),
          ])),
    );
  }

  Widget _addImageButton() {
    final l10n = AppLocalizations.of(context);
    return GestureDetector(
      onTap: _pickImages,
      child: Container(
          width: 90,
          height: 90,
          decoration: BoxDecoration(
              color: AppColors.hoverState,
              borderRadius: BorderRadius.circular(AppShapes.radiusMd),
              border: Border.all(color: AppColors.borderLight)),
          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            const Icon(Icons.add_a_photo_outlined,
                size: 24, color: AppColors.textMuted),
            const SizedBox(height: 4),
            Text(l10n.translate('add_image_btn'),
                style: Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.copyWith(fontSize: 12, color: AppColors.textMuted)),
          ])),
    );
  }

  Widget _addVideoButton() {
    final l10n = AppLocalizations.of(context);
    return GestureDetector(
      onTap: _pickVideo,
      child: Container(
          width: 90,
          height: 90,
          decoration: BoxDecoration(
              color: AppColors.hoverState,
              borderRadius: BorderRadius.circular(AppShapes.radiusMd),
              border: Border.all(color: AppColors.borderLight)),
          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            const Icon(Icons.videocam, size: 24, color: AppColors.textMuted),
            const SizedBox(height: 4),
            Text(l10n.translate('add_video_btn'),
                style: Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.copyWith(fontSize: 12, color: AppColors.textMuted)),
          ])),
    );
  }

  Widget _buildAttrRow(AttributeDefinition attr,
      {required bool required, bool removable = false}) {
    final l10n = AppLocalizations.of(context);
    final controller = _getAttrController(attr.name);
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Row(children: [
        SizedBox(
            width: 100,
            child: Text(attr.displayName + (required ? ' *' : ''),
                style: TextStyle(
                    fontSize: 14,
                    color: required ? AppColors.error : AppColors.textPrimary))),
        const SizedBox(width: AppSpacing.xs),
        Expanded(
          child: attr.isSelect
              ? _dropdown<String>(
                  value: controller.text.isEmpty ? null : controller.text,
                  hint: l10n.translate('select'),
                  items: [
                    DropdownMenuItem<String>(
                        value: null, child: Text(l10n.translate('select'))),
                    ...attr.values.map((v) => DropdownMenuItem<String>(
                        value: v, child: Text(v)))
                  ],
                  onChanged: (v) {
                    setState(() {
                      _attrValues[attr.name] = v ?? '';
                      _syncAttrController(attr.name);
                    });
                  })
              : _textField(
                  controller: controller,
                  label: '',
                  hint: l10n
                      .translate('enter_value')
                      .replaceAll('{displayName}', attr.displayName),
                  onChanged: (v) {
                    _attrValues[attr.name] = v;
                  }),
        ),
        if (removable)
          IconButton(
              icon: const Icon(Icons.close, size: 18, color: AppColors.error),
              onPressed: () => _removeOptionalAttr(attr.name)),
      ]),
    );
  }

  Widget _buildImageWidget(XFile file) {
    if (kIsWeb)
      return Image.network(file.path,
          width: 90,
          height: 90,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => const Icon(Icons.broken_image,
              size: 36, color: AppColors.textMuted));
    return Image.file(File(file.path),
        width: 90,
        height: 90,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) =>
            const Icon(Icons.broken_image, size: 36, color: AppColors.textMuted));
  }
}

// ─── Models (bottom of file) ─────────────────
class AttributeDefinition {
  final int id;
  final String name;
  final String displayName;
  final String attrType;
  final bool isFilterable;
  final bool isVariant;
  final bool isRequired;
  final List<String> values;

  AttributeDefinition(
      {required this.id,
      required this.name,
      required this.displayName,
      required this.attrType,
      required this.isFilterable,
      required this.isVariant,
      required this.isRequired,
      required this.values});

  bool get isSelect => attrType == 'dropdown' && values.isNotEmpty;

  factory AttributeDefinition.fromJson(Map<String, dynamic> json) =>
      AttributeDefinition(
        id: json['id'],
        name: json['name'],
        displayName: json['display_name'] ?? json['name'],
        attrType: json['attr_type'] ?? 'text',
        isFilterable: json['is_filterable'] ?? false,
        isVariant: json['is_variant'] ?? false,
        isRequired: json['is_required'] ?? false,
        values: (json['values'] as List?)
                ?.map((e) => e.toString())
                .toList() ??
            [],
      );
}

class SelectedAttr {
  final int attrId;
  String value;
  SelectedAttr({required this.attrId, this.value = ''});
}

class Variety {
  List<SelectedAttr> selectedAttrs;
  String price;
  String stock;
  bool unlimitedStock;
  XFile? image;

  Variety(
      {required this.selectedAttrs,
      this.price = '',
      this.stock = '',
      this.unlimitedStock = false,
      this.image});
}

extension FirstWhereOrNull<T> on Iterable<T> {
  T? firstWhereOrNull(bool Function(T) test) {
    for (final element in this) {
      if (test(element)) return element;
    }
    return null;
  }
}
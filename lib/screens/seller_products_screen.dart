// 📁 lib/screens/seller_products_screen.dart
import 'package:flutter/material.dart';
import 'package:dio/dio.dart';
import '../api/client.dart';
import '../models/product.dart';
import '../utils/url_utils.dart';
import '../theme/app_theme.dart';
import '../l10n/app_localizations.dart';
import 'add_product_screen.dart';

class SellerProductsScreen extends StatefulWidget {
  const SellerProductsScreen({Key? key}) : super(key: key);
  @override
  State<SellerProductsScreen> createState() => _SellerProductsScreenState();
}

class _SellerProductsScreenState extends State<SellerProductsScreen> {
  List<Map<String, dynamic>> _allProducts = [];
  bool _isLoading = true;
  String? _error;
  String _query = '';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (ApiClient.hasToken) {
        _fetchProducts();
      } else {
        if (mounted) setState(() => _isLoading = false);
      }
    });
  }

  String _formatPrice(double value) {
    final parts = value.toStringAsFixed(2).split('.');
    final integerPart = parts[0].replaceAllMapped(
      RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'),
      (Match m) => '${m[1]},',
    );
    return '$integerPart.${parts[1]}';
  }

  Future<void> _fetchProducts() async {
    final l10n = AppLocalizations.of(context);
    if (!ApiClient.hasToken) {
      setState(() => _isLoading = false);
      return;
    }
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final res = await ApiClient.instance.get('/products', queryParameters: {'vendor': 'me'});
      final List data = res.data is List ? res.data : (res.data['data'] ?? []);
      final products = data.map((p) => Map<String, dynamic>.from(p)).toList();

      if (mounted) {
        setState(() {
          _allProducts = products;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _error = l10n.translate('failed_load_products');
        });
      }
    }
  }

  List<Map<String, dynamic>> get _filteredProducts {
    if (_query.isEmpty) return _allProducts;
    final lower = _query.toLowerCase();
    return _allProducts.where((p) =>
      (p['title'] ?? '').toString().toLowerCase().contains(lower)
    ).toList();
  }

  String _extractErrorMessage(Object e) {
    try {
      if (e is DioException && e.response?.data != null) {
        final data = e.response!.data;
        if (data is Map) {
          if (data['errors'] is List && (data['errors'] as List).isNotEmpty) {
            return (data['errors'] as List).join(', ');
          }
          if (data['error'] != null) return data['error'].toString();
        }
      }
    } catch (_) {}
    return e.toString();
  }

  Future<void> _deleteProduct(dynamic id) async {
    final l10n = AppLocalizations.of(context);
    try {
      await ApiClient.instance.delete('/products/$id');
      _fetchProducts();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(l10n.translate('product_deleted')),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppShapes.radiusSm)),
            backgroundColor: AppColors.textPrimary,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(_extractErrorMessage(e)),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppShapes.radiusSm)),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  }

  Future<void> _quickUpdateStock(int productId, int? newStock) async {
    final l10n = AppLocalizations.of(context);
    try {
      final body = newStock == null
          ? {'product': {'stock': null}}
          : {'product': {'stock': newStock}};
      await ApiClient.instance.put('/products/$productId', data: body);
      _fetchProducts();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(l10n.translate('stock_updated')),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppShapes.radiusSm)),
            backgroundColor: AppColors.textPrimary,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(_extractErrorMessage(e)),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppShapes.radiusSm)),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  }

  void _showStockDialog(Map<String, dynamic> product) {
    final l10n = AppLocalizations.of(context);

    // If product has variants, stock is managed per variant.
    if (product['has_variants'] == true) {
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(l10n.translate('stock_management')),
          content: Text(l10n.translate('variant_stock_message')),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text(l10n.translate('ok')),
            ),
          ],
        ),
      );
      return;
    }

    final stock = product['stock'];
    final isUnlimited = product['bulk_enabled'] == true && stock == null;
    final controller = TextEditingController(
      text: isUnlimited ? '' : (stock?.toString() ?? ''),
    );

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.translate('update_stock_title').replaceAll('{title}', product['title'] ?? '')),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: controller,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                labelText: l10n.translate('available_stock'),
                hintText: isUnlimited ? 'Leave empty for unlimited' : null,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(AppShapes.radiusSm)),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              isUnlimited ? 'Current: Unlimited' : 'Current: $stock',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text(l10n.translate('cancel'))),
          ElevatedButton(
            onPressed: () {
              final input = controller.text.trim();
              final newStock = input.isEmpty ? null : int.tryParse(input);
              Navigator.pop(ctx);
              _quickUpdateStock(product['id'], newStock);
            },
            style: AppComponentStyles.primaryButton,
            child: Text(l10n.translate('update')),
          ),
        ],
      ),
    );
  }

  void _editProduct(dynamic id) async {
    try {
      final res = await ApiClient.instance.get('/products/$id');
      final product = Product.fromJson(res.data);
      if (mounted) {
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => AddProductScreen(product: product)),
        ).then((_) => _fetchProducts());
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to load product: ${_extractErrorMessage(e)}')),
        );
      }
    }
  }

  String _getStockDisplay(Map<String, dynamic> p) {
    if (p['stock_display'] != null) return p['stock_display'].toString();
    if (p['bulk_enabled'] == true) {
      if (p['stock'] == null) return AppLocalizations.of(context).translate('unlimited_stock');
      return p['stock'].toString();
    }
    if (p['has_variants'] == true) {
      final available = p['available_stock'];
      if (available != null) return available.toString();
    }
    if (p['stock'] != null) return p['stock'].toString();
    return '0';
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final products = _filteredProducts;
    final textTheme = Theme.of(context).textTheme;

    return Column(
      children: [
        Container(
          color: AppColors.cardBackground,
          padding: const EdgeInsets.fromLTRB(AppSpacing.md, AppSpacing.sm, AppSpacing.md, AppSpacing.xs),
          child: Row(children: [
            Expanded(
              child: TextField(
                onChanged: (value) => setState(() => _query = value),
                style: textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w500, color: AppColors.textPrimary),
                decoration: InputDecoration(
                  hintText: l10n.translate('search_products_hint'),
                  hintStyle: textTheme.bodySmall?.copyWith(color: AppColors.textMuted),
                  prefixIcon: const Icon(Icons.search, size: 20, color: AppColors.textMuted),
                  filled: true,
                  fillColor: AppColors.hoverState,
                  contentPadding: const EdgeInsets.symmetric(vertical: 10),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(AppShapes.radiusSm), borderSide: BorderSide.none),
                  enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(AppShapes.radiusSm), borderSide: BorderSide.none),
                  focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(AppShapes.radiusSm), borderSide: const BorderSide(color: AppColors.primary, width: 1.5)),
                ),
              ),
            ),
            const SizedBox(width: AppSpacing.xs),
            Material(
              color: AppColors.primary,
              borderRadius: BorderRadius.circular(AppShapes.radiusSm),
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const AddProductScreen()),
                  ).then((_) => _fetchProducts());
                },
                splashColor: Colors.white24,
                highlightColor: Colors.white10,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.add, size: 16, color: Colors.white),
                      const SizedBox(width: 6),
                      Text(l10n.translate('add'), style: textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w700, color: Colors.white)),
                    ],
                  ),
                ),
              ),
            ),
          ]),
        ),

        Expanded(
          child: Container(
            color: AppColors.productListBackground,
            child: _isLoading
                ? const Center(child: CircularProgressIndicator(color: AppColors.primary, strokeWidth: 2))
                : _error != null
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(32),
                          child: Text(_error!, style: textTheme.bodyLarge?.copyWith(color: AppColors.error)),
                        ),
                      )
                    : products.isEmpty
                        ? Center(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Container(
                                  width: 72,
                                  height: 72,
                                  decoration: const BoxDecoration(
                                    color: AppColors.primary,
                                    shape: BoxShape.circle,
                                  ),
                                  child: const Icon(Icons.inventory_2_outlined, color: Colors.white, size: 36),
                                ),
                                const SizedBox(height: 20),
                                Text(l10n.translate('no_products_found'), style: textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
                                const SizedBox(height: 8),
                                Text(l10n.translate('no_products_message'), style: textTheme.bodySmall?.copyWith(color: AppColors.textMuted)),
                              ],
                            ),
                          )
                        : ListView.builder(
                            padding: const EdgeInsets.fromLTRB(AppSpacing.md, AppSpacing.xs, AppSpacing.md, 24),
                            itemCount: products.length,
                            itemBuilder: (context, index) {
                              final p = products[index];
                              final stockText = _getStockDisplay(p);
                              final bool isUnlimited = p['bulk_enabled'] == true && p['stock'] == null;
                              final outOfStock = p['out_of_stock'] == true;
                              final hasVariants = p['has_variants'] == true;
                              final rawPrice = p['effective_price'] ?? p['price'];
                              final priceNum = rawPrice != null
                                  ? (double.tryParse(rawPrice.toString()) ?? 0.0)
                                  : 0.0;
                              final imageUrls = p['image_urls'];
                              final firstImage = (imageUrls is List && imageUrls.isNotEmpty)
                                  ? resolveUrl(imageUrls.first.toString())
                                  : 'https://placehold.co/600x400?text=No+Image';
                              final freeDelivery = p['free_delivery'] == true;
                              final int variantCount = p['variants_count'] ?? 0;

                              return Padding(
                                padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                                child: Material(
                                  color: AppColors.cardBackground,
                                  borderRadius: BorderRadius.circular(AppShapes.radiusMd),
                                  child: InkWell(
                                    onTap: () => _editProduct(p['id']),
                                    borderRadius: BorderRadius.circular(AppShapes.radiusMd),
                                    splashColor: AppColors.primary.withOpacity(0.05),
                                    highlightColor: AppColors.primary.withOpacity(0.02),
                                    child: Container(
                                      padding: const EdgeInsets.all(AppSpacing.md),
                                      decoration: BoxDecoration(
                                        color: AppColors.cardBackground,
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
                                          Row(
                                            crossAxisAlignment: CrossAxisAlignment.center,
                                            children: [
                                              ClipRRect(
                                                borderRadius: BorderRadius.circular(AppShapes.radiusSm),
                                                child: Image.network(
                                                  firstImage,
                                                  width: 72,
                                                  height: 72,
                                                  fit: BoxFit.cover,
                                                  errorBuilder: (_, __, ___) => Container(
                                                    width: 72,
                                                    height: 72,
                                                    decoration: BoxDecoration(
                                                      color: AppColors.hoverState,
                                                      borderRadius: BorderRadius.circular(AppShapes.radiusSm),
                                                    ),
                                                    child: const Icon(Icons.image_outlined, size: 28, color: AppColors.textMuted),
                                                  ),
                                                ),
                                              ),
                                              const SizedBox(width: AppSpacing.sm),
                                              Expanded(
                                                child: Column(
                                                  crossAxisAlignment: CrossAxisAlignment.start,
                                                  children: [
                                                    Text(
                                                      p['title'] ?? '',
                                                      style: textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w700, color: AppColors.textPrimary),
                                                      maxLines: 2,
                                                      overflow: TextOverflow.ellipsis,
                                                    ),
                                                    const SizedBox(height: 4),
                                                    Wrap(
                                                      spacing: 6,
                                                      runSpacing: 2,
                                                      crossAxisAlignment: WrapCrossAlignment.center,
                                                      children: [
                                                        Text(
                                                          'ETB ${_formatPrice(priceNum)}',
                                                          style: textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w700, color: AppColors.primary),
                                                        ),
                                                        if (!hasVariants)
                                                          GestureDetector(
                                                            onTap: () => _showStockDialog(p),
                                                            child: Row(
                                                              mainAxisSize: MainAxisSize.min,
                                                              children: [
                                                                Container(
                                                                  width: 6,
                                                                  height: 6,
                                                                  decoration: BoxDecoration(
                                                                    shape: BoxShape.circle,
                                                                    color: isUnlimited
                                                                        ? AppColors.textMuted
                                                                        : (outOfStock ? AppColors.error : AppColors.success),
                                                                  ),
                                                                ),
                                                                const SizedBox(width: 4),
                                                                Text(
                                                                  '${l10n.translate('stock_label')}: $stockText',
                                                                  style: textTheme.bodySmall?.copyWith(
                                                                    fontWeight: FontWeight.w700,
                                                                    color: isUnlimited ? AppColors.textMuted : AppColors.textPrimary,
                                                                  ),
                                                                ),
                                                              ],
                                                            ),
                                                          ),
                                                        if (variantCount > 0)
                                                          Text(
                                                            ' ($variantCount variant${variantCount > 1 ? 's' : ''})',
                                                            style: textTheme.bodySmall?.copyWith(
                                                              color: AppColors.textMuted,
                                                              fontSize: 11,
                                                            ),
                                                          ),
                                                        if (freeDelivery)
                                                          Text(
                                                            l10n.translate('free_delivery'),
                                                            style: textTheme.bodySmall?.copyWith(
                                                              fontWeight: FontWeight.w600,
                                                              color: Colors.black,
                                                            ),
                                                          ),
                                                      ],
                                                    ),
                                                    if (outOfStock) ...[
                                                      const SizedBox(height: 4),
                                                      Container(
                                                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                                        decoration: BoxDecoration(
                                                          color: Colors.grey.shade200,
                                                          borderRadius: BorderRadius.circular(4),
                                                          border: Border.all(color: Colors.grey.shade400, width: 0.5),
                                                        ),
                                                        child: const Row(
                                                          mainAxisSize: MainAxisSize.min,
                                                          children: [
                                                            Icon(Icons.error_outline, size: 12, color: Colors.grey),
                                                            SizedBox(width: 4),
                                                            Text('Out of stock', style: TextStyle(fontSize: 11, color: Colors.grey, fontWeight: FontWeight.w600)),
                                                          ],
                                                        ),
                                                      ),
                                                    ],
                                                  ],
                                                ),
                                              ),
                                              PopupMenuButton<String>(
                                                onSelected: (value) {
                                                  if (value == 'edit') {
                                                    _editProduct(p['id']);
                                                  } else if (value == 'delete') {
                                                    _deleteProduct(p['id']);
                                                  }
                                                },
                                                icon: const Icon(Icons.more_vert, size: 20, color: AppColors.textPrimary),
                                                itemBuilder: (_) => [
                                                  PopupMenuItem(value: 'edit', child: Text(l10n.translate('edit'))),
                                                  PopupMenuItem(value: 'delete', child: Text(l10n.translate('delete'))),
                                                ],
                                                padding: EdgeInsets.zero,
                                                constraints: const BoxConstraints(),
                                              ),
                                            ],
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                              );
                            },
                          ),
          ),
        ),
      ],
    );
  }
}
// lib/screens/compare_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../api/client.dart';
import '../models/product.dart';
import '../providers/compare_provider.dart';
import '../providers/cart_provider.dart';
import '../theme/app_theme.dart';
import '../utils/url_utils.dart';
import '../l10n/app_localizations.dart';
import '../widgets/bottom_nav_bar.dart';
import '../providers/tab_provider.dart';

class CompareScreen extends ConsumerStatefulWidget {
  const CompareScreen({Key? key}) : super(key: key);
  @override
  ConsumerState<CompareScreen> createState() => _CompareScreenState();
}

class _CompareScreenState extends ConsumerState<CompareScreen> {
  List<Product> _products = [];
  Map<int, Map<String, String>> _variantAttrs = {};
  bool _isLoading = true;
  final Set<int> _addingToCart = {};

  @override
  void initState() {
    super.initState();
    _fetchComparedProducts();
  }

  Future<void> _fetchComparedProducts() async {
    setState(() => _isLoading = true);
    try {
      final res = await ApiClient.instance.get('/comparisons');
      final List data = res.data is List ? res.data : (res.data['data'] ?? []);
      final List<Product> products = [];
      final Map<int, Map<String, String>> variantMap = {};

      for (final item in data) {
        final product = Product.fromJson(item);
        products.add(product);

        if (item['variant_attributes'] is Map) {
          variantMap[product.id] = Map<String, String>.from(
            (item['variant_attributes'] as Map).map((k, v) => MapEntry(k.toString(), v.toString()))
          );
        } else {
          variantMap[product.id] = {};
        }
      }

      setState(() {
        _products = products;
        _variantAttrs = variantMap;
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _removeProduct(int productId) async {
    final l10n = AppLocalizations.of(context);
    try {
      await ApiClient.instance.delete('/comparisons/$productId');
      setState(() {
        _products.removeWhere((p) => p.id == productId);
        _variantAttrs.remove(productId);
      });
      if (mounted) _showSnack(l10n.translate('compare_removed'));
    } catch (e) {
      if (mounted) _showSnack(l10n.translate('compare_failed_remove'), isError: true);
    }
  }

  Future<void> _clearAll() async {
    final l10n = AppLocalizations.of(context);
    try {
      await Future.wait(_products.map((p) => ApiClient.instance.delete('/comparisons/${p.id}')));
      setState(() { _products.clear(); _variantAttrs.clear(); });
    } catch (e) {
      if (mounted) _showSnack(l10n.translate('compare_failed_clear'), isError: true);
    }
  }

  void _showSnack(String msg, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: isError ? AppColors.error : AppColors.primary),
    );
  }

  Future<void> _addToCart(Product product, Map<String, String> variant) async {
    final l10n = AppLocalizations.of(context);
    if (_addingToCart.contains(product.id)) return;
    setState(() => _addingToCart.add(product.id));
    try {
      await ref.read(cartProvider.notifier).addItem(
        product,
        quantity: 1,
        variant: variant.isNotEmpty ? variant : null,
      );
      if (mounted) _showSnack(l10n.translate('compare_added_to_cart'));
    } catch (e) {
      if (mounted) _showSnack('Failed to add to cart', isError: true);
    } finally {
      setState(() => _addingToCart.remove(product.id));
    }
  }

  // ── Build the attribute table rows for a single product ──
  List<Widget> _buildAttributeRows(Product product, AppLocalizations l10n) {
    final attributes = <String, String>{};

    // Price
    attributes[l10n.translate('compare_price')] = 'ETB ${(product.effectivePrice).toStringAsFixed(2)}';
    // Brand
    final brand = product.attributes['brand'] ?? product.productAttributes['brand'] ?? '—';
    attributes[l10n.translate('compare_brand')] = brand;
    // Category
    final cat = product.categoryId?.toString() ?? '—';
    attributes[l10n.translate('compare_category')] = cat;
    // Other non‑brand attributes
    for (final key in product.attributes.keys.where((k) => k != 'brand')) {
      attributes[key] = product.attributes[key] ?? '—';
    }
    // Description (trimmed)
    final desc = product.description ?? '';
    attributes[l10n.translate('compare_description')] =
        desc.length > 80 ? '${desc.substring(0, 80)}…' : (desc.isEmpty ? '—' : desc);

    final rows = <Widget>[];
    for (int i = 0; i < attributes.length; i++) {
      final entry = attributes.entries.elementAt(i);
      final isEven = i.isEven;
      rows.add(
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: isEven ? AppColors.cardBackground : AppColors.hoverState,
            border: Border(
              top: BorderSide(color: AppColors.borderLight.withOpacity(0.4)),
            ),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 90,
                child: Text(
                  entry.key,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        fontWeight: FontWeight.w600,
                        fontSize: 12,
                        color: AppColors.textSecondary,
                      ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  entry.value,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        fontWeight: FontWeight.w500,
                        fontSize: 12,
                        color: AppColors.textPrimary,
                      ),
                ),
              ),
            ],
          ),
        ),
      );
    }
    return rows;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final textTheme = Theme.of(context).textTheme;

    if (_isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator(color: AppColors.primary)));
    }

    if (_products.isEmpty) {
      return _buildEmptyState(l10n, textTheme);
    }

    return Scaffold(
      backgroundColor: AppColors.productListBackground, // grey background
      appBar: AppBar(
        backgroundColor: AppColors.cardBackground,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, color: AppColors.textPrimary),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          l10n.translate('compare_title'),
          style: textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700, color: AppColors.textPrimary),
        ),
        actions: [
          TextButton.icon(
            onPressed: _clearAll,
            icon: const Icon(Icons.delete_sweep_outlined, size: 18, color: AppColors.error),
            label: Text(
              l10n.translate('compare_clear'),
              style: const TextStyle(color: AppColors.error, fontWeight: FontWeight.w600, fontSize: 13),
            ),
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: ListView.builder(
        padding: const EdgeInsets.fromLTRB(AppSpacing.md, AppSpacing.sm, AppSpacing.md, AppSpacing.lg),
        itemCount: _products.length,
        itemBuilder: (context, index) {
          final product = _products[index];
          final variantAttrs = _variantAttrs[product.id] ?? {};
          return _buildProductSection(product, variantAttrs, l10n, textTheme);
        },
      ),
      bottomNavigationBar: BottomNavBar(
        selectedIndex: 4,
        onTap: (index) {
          Navigator.of(context).pushNamedAndRemoveUntil('/main', (route) => false);
          ref.read(tabProvider.notifier).state = index;
        },
      ),
    );
  }

  // ── Each product section: compact card + organized table ──
  Widget _buildProductSection(Product product, Map<String, String> variant, AppLocalizations l10n, TextTheme textTheme) {
    final isAdding = _addingToCart.contains(product.id);

    return Container(
      margin: const EdgeInsets.only(bottom: AppSpacing.lg),
      child: Column(
        children: [
          // 1. Product card – with close button at the very top‑left corner of the card
          Stack(
            clipBehavior: Clip.none,
            children: [
              Container(
                padding: const EdgeInsets.all(AppSpacing.sm),
                decoration: BoxDecoration(
                  color: AppColors.cardBackground,
                  borderRadius: BorderRadius.circular(AppShapes.radiusMd),
                  border: Border.all(color: AppColors.borderLight, width: 1),
                  boxShadow: [
                    BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 8, offset: const Offset(0, 2)),
                  ],
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    // Product image (80×80) – clean, no close button inside
                    ClipRRect(
                      borderRadius: BorderRadius.circular(AppShapes.radiusSm),
                      child: Image.network(
                        resolveUrl(product.imageUrl),
                        width: 80,
                        height: 80,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => Container(
                          width: 80,
                          height: 80,
                          color: AppColors.hoverState,
                          child: Icon(Icons.image_not_supported, size: 28, color: AppColors.textMuted),
                        ),
                      ),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    // Product info (title, price, rating)
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            product.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: textTheme.bodyMedium?.copyWith(
                                fontWeight: FontWeight.w600, color: AppColors.textPrimary, fontSize: 13),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'ETB ${(product.effectivePrice).toStringAsFixed(2)}',
                            style: textTheme.titleMedium?.copyWith(
                                fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.textPrimary),
                          ),
                          const SizedBox(height: 2),
                          Row(
                            children: [
                              Icon(Icons.star_rounded, size: 12, color: AppColors.starGold),
                              const SizedBox(width: 2),
                              Text(
                                product.rating.toStringAsFixed(1),
                                style: textTheme.bodySmall?.copyWith(fontSize: 11, color: AppColors.textMuted),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    // Cart button – right side
                    GestureDetector(
                      onTap: isAdding ? null : () => _addToCart(product, variant),
                      child: Container(
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(
                          color: Colors.white,
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.12),
                              blurRadius: 6,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: isAdding
                            ? const Padding(
                                padding: EdgeInsets.all(8.0),
                                child: CircularProgressIndicator(strokeWidth: 2.5, color: AppColors.primary),
                              )
                            : Icon(Icons.shopping_cart_outlined, size: 18, color: AppColors.primary),
                      ),
                    ),
                  ],
                ),
              ),
              // ★ Plain X icon at top‑left corner (no circle)
              Positioned(
                top: 4,
                left: 4,
                child: GestureDetector(
                  onTap: () => _removeProduct(product.id),
                  child: const Icon(
                    Icons.close_rounded,
                    size: 20,
                    color: AppColors.textSecondary,
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(height: AppSpacing.xs),

          // 2. Comparison table – organized, world‑class
          Container(
            decoration: BoxDecoration(
              color: AppColors.cardBackground,
              borderRadius: BorderRadius.circular(AppShapes.radiusMd),
              border: Border.all(color: AppColors.borderLight, width: 1),
              boxShadow: [
                BoxShadow(color: Colors.black.withOpacity(0.02), blurRadius: 4, offset: const Offset(0, 2)),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Table header
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                  decoration: BoxDecoration(
                    color: AppColors.hoverState,
                    borderRadius: const BorderRadius.vertical(top: Radius.circular(AppShapes.radiusMd)),
                  ),
                  child: Row(
                    children: [
                      SizedBox(
                        width: 90,
                        child: Text(
                          l10n.translate('compare_attribute'),
                          style: textTheme.bodySmall?.copyWith(
                              fontWeight: FontWeight.w700, fontSize: 12, color: AppColors.textSecondary),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          l10n.translate('compare_description'),
                          style: textTheme.bodySmall?.copyWith(
                              fontWeight: FontWeight.w700, fontSize: 12, color: AppColors.textSecondary),
                        ),
                      ),
                    ],
                  ),
                ),
                // Table body
                ..._buildAttributeRows(product, l10n),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState(AppLocalizations l10n, TextTheme textTheme) {
    return Scaffold(
      backgroundColor: AppColors.cardBackground,
      appBar: AppBar(
        backgroundColor: AppColors.cardBackground,
        elevation: 0,
        leading: IconButton(
            icon: const Icon(Icons.arrow_back_ios_new_rounded, color: AppColors.textPrimary),
            onPressed: () => Navigator.pop(context)),
        title: Text(l10n.translate('compare_title'),
            style: textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 40),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                  width: 100,
                  height: 100,
                  decoration: BoxDecoration(
                      color: AppColors.primary.withOpacity(0.08),
                      shape: BoxShape.circle,
                      boxShadow: [BoxShadow(color: AppColors.primary.withOpacity(0.15), blurRadius: 24, offset: const Offset(0, 8))]),
                  child: const Icon(Icons.compare_arrows_rounded, size: 44, color: AppColors.primary)),
              const SizedBox(height: 24),
              Text(l10n.translate('compare_empty_title'),
                  textAlign: TextAlign.center,
                  style: textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
              const SizedBox(height: 8),
              Text(l10n.translate('compare_empty_subtitle'),
                  textAlign: TextAlign.center,
                  style: textTheme.bodyMedium?.copyWith(color: AppColors.textMuted, height: 1.4)),
              const SizedBox(height: 24),
              ElevatedButton(
                  onPressed: () => Navigator.of(context).pushNamedAndRemoveUntil('/main', (route) => false),
                  style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppShapes.radiusSm)),
                      elevation: 2,
                      shadowColor: AppColors.primary.withOpacity(0.3)),
                  child: Text(l10n.translate('compare_browse_products'),
                      style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600))),
            ],
          ),
        ),
      ),
      bottomNavigationBar: BottomNavBar(
        selectedIndex: 4,
        onTap: (index) {
          Navigator.of(context).pushNamedAndRemoveUntil('/main', (route) => false);
          ref.read(tabProvider.notifier).state = index;
        },
      ),
    );
  }
}
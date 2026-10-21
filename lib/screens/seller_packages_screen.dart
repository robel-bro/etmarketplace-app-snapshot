// 📁 lib/screens/seller_packages_screen.dart
import 'package:flutter/material.dart';
import 'package:dio/dio.dart';
import '../api/client.dart';
import '../utils/url_utils.dart';
import '../theme/app_theme.dart';
import '../l10n/app_localizations.dart';
import 'create_package_screen.dart';

class SellerPackagesScreen extends StatefulWidget {
  const SellerPackagesScreen({Key? key}) : super(key: key);
  @override
  State<SellerPackagesScreen> createState() => _SellerPackagesScreenState();
}

class _SellerPackagesScreenState extends State<SellerPackagesScreen> {
  List<Map<String, dynamic>> _allPackages = [];
  bool _isLoading = true;
  String? _error;
  String _query = '';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (ApiClient.hasToken) {
        _fetchPackages();
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

  Future<void> _fetchPackages() async {
    final l10n = AppLocalizations.of(context);
    if (!ApiClient.hasToken) {
      setState(() => _isLoading = false);
      return;
    }
    setState(() { _isLoading = true; _error = null; });
    try {
      final res = await ApiClient.instance.get('/packages', queryParameters: {'vendor': 'me'});
      final List data = res.data is List ? res.data : (res.data['data'] ?? []);
      final packages = data.map((p) => Map<String, dynamic>.from(p)).toList();
      if (mounted) {
        setState(() {
          _allPackages = packages;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _error = l10n.translate('failed_load_package').replaceAll('{error}', _extractErrorMessage(e));
        });
      }
    }
  }

  List<Map<String, dynamic>> get _filteredPackages {
    if (_query.isEmpty) return _allPackages;
    final lower = _query.toLowerCase();
    return _allPackages.where((p) =>
      (p['name'] ?? '').toString().toLowerCase().contains(lower)
    ).toList();
  }

  Future<void> _quickUpdateStock(int packageId, int? newStock) async {
    final l10n = AppLocalizations.of(context);
    try {
      await ApiClient.instance.put(
        '/packages/$packageId',
        data: { 'package': { 'stock': newStock } },
      );
      _fetchPackages();
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
            content: Text(l10n.translate('failed_update_stock').replaceAll('{error}', _extractErrorMessage(e))),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppShapes.radiusSm)),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  }

  void _showStockDialog(Map<String, dynamic> package) {
    final l10n = AppLocalizations.of(context);
    final currentStock = package['stock'];
    final isUnlimited = currentStock == null;
    final controller = TextEditingController(
      text: isUnlimited ? '' : currentStock.toString(),
    );
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.translate('update_stock_title').replaceAll('{name}', package['name'] ?? '')),
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
              isUnlimited ? 'Current: Unlimited' : 'Current: $currentStock',
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
              _quickUpdateStock(package['id'], newStock);
            },
            style: AppComponentStyles.primaryButton,
            child: Text(l10n.translate('update')),
          ),
        ],
      ),
    );
  }

  Future<void> _deletePackage(dynamic id) async {
    final l10n = AppLocalizations.of(context);
    try {
      await ApiClient.instance.delete('/packages/$id');
      _fetchPackages();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(l10n.translate('package_deleted')),
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
            content: Text(l10n.translate('failed_delete_package').replaceAll('{error}', _extractErrorMessage(e))),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppShapes.radiusSm)),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  }

  void _editPackage(dynamic id) async {
    try {
      final res = await ApiClient.instance.get('/packages/$id');
      final package = res.data;
      if (mounted) {
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => CreatePackageScreen(packageData: package)),
        ).then((_) => _fetchPackages());
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to load package: ${_extractErrorMessage(e)}')),
        );
      }
    }
  }

  // ── Correct stock display (uses stock_display or available_stock) ──
  String _getStockDisplay(Map<String, dynamic> pkg) {
    if (pkg['stock_display'] != null) return pkg['stock_display'].toString();
    final available = pkg['available_stock'];
    if (available != null) return available.toString();
    if (pkg['stock'] != null) return pkg['stock'].toString();
    return '0';
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final packages = _filteredPackages;
    final textTheme = Theme.of(context).textTheme;

    return Column(children: [
      // Search bar + Add button
      Container(
        color: AppColors.cardBackground,
        padding: const EdgeInsets.fromLTRB(AppSpacing.md, AppSpacing.sm, AppSpacing.md, AppSpacing.xs),
        child: Row(children: [
          Expanded(
            child: TextField(
              onChanged: (value) => setState(() => _query = value),
              style: textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w500, color: AppColors.textPrimary),
              decoration: InputDecoration(
                hintText: l10n.translate('search_packages_hint'),
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
                  MaterialPageRoute(builder: (_) => const CreatePackageScreen()),
                ).then((_) => _fetchPackages());
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
                    Text(l10n.translate('add_package'),
                        style: textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w700, color: Colors.white)),
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
                  : packages.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Container(
                                width: 72, height: 72,
                                decoration: const BoxDecoration(
                                  color: AppColors.primary,
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(Icons.card_giftcard, color: Colors.white, size: 36),
                              ),
                              const SizedBox(height: 20),
                              Text(l10n.translate('no_packages_found'),
                                  style: textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
                              const SizedBox(height: 8),
                              Text(l10n.translate('no_packages_message'),
                                  style: textTheme.bodySmall?.copyWith(color: AppColors.textMuted)),
                            ],
                          ),
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.fromLTRB(AppSpacing.md, AppSpacing.xs, AppSpacing.md, 24),
                          itemCount: packages.length,
                          itemBuilder: (context, index) {
                            final pkg = packages[index];
                            final imageUrls = pkg['image_urls'];
                            final firstImage = (imageUrls is List && imageUrls.isNotEmpty)
                                ? resolveUrl(imageUrls.first.toString())
                                : '';
                            final name = pkg['name'] ?? '';
                            final productCount = pkg['items_count'] ?? (pkg['products'] as List?)?.length ?? 0;
                            double priceNum = 0.0;
                            final rawPrice = pkg['price'];
                            if (rawPrice != null) {
                              priceNum = double.tryParse(rawPrice.toString()) ?? 0.0;
                            }
                            final discountPercent = pkg['discount_percentage'] ?? pkg['discount_value'];
                            final hasDiscount = discountPercent != null && discountPercent.toString() != '0' && discountPercent.toString() != '0.0';
                            final stockText = _getStockDisplay(pkg);
                            final bool isUnlimited = stockText == 'Unlimited';
                            final outOfStock = pkg['out_of_stock'] == true;
                            final freeDelivery = pkg['free_delivery'] == true;
                            final deliveryLabel = pkg['delivery_label']?.toString();

                            return Padding(
                              padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                              child: Material(
                                color: AppColors.cardBackground,
                                borderRadius: BorderRadius.circular(AppShapes.radiusMd),
                                clipBehavior: Clip.antiAlias,
                                child: InkWell(
                                  onTap: () => _editPackage(pkg['id']),
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
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            ClipRRect(
                                              borderRadius: BorderRadius.circular(AppShapes.radiusSm),
                                              child: firstImage.isNotEmpty
                                                  ? Image.network(
                                                      firstImage,
                                                      width: 80,
                                                      height: 80,
                                                      fit: BoxFit.cover,
                                                      errorBuilder: (_, __, ___) => _placeholderImage(),
                                                    )
                                                  : _placeholderImage(),
                                            ),
                                            const SizedBox(width: AppSpacing.sm),
                                            Expanded(
                                              child: Column(
                                                crossAxisAlignment: CrossAxisAlignment.start,
                                                children: [
                                                  Text(
                                                    name,
                                                    style: textTheme.bodyMedium?.copyWith(
                                                      fontWeight: FontWeight.w700,
                                                      color: AppColors.textPrimary,
                                                    ),
                                                    maxLines: 2,
                                                    overflow: TextOverflow.ellipsis,
                                                  ),
                                                  const SizedBox(height: 4),
                                                  Text(
                                                    l10n.translate('products_count').replaceAll('{count}', productCount.toString()),
                                                    style: textTheme.bodySmall?.copyWith(color: AppColors.textMuted),
                                                  ),
                                                  const SizedBox(height: 6),
                                                  Text(
                                                    'ETB ${_formatPrice(priceNum)}',
                                                    style: textTheme.titleSmall?.copyWith(
                                                      fontWeight: FontWeight.w700,
                                                      color: AppColors.textPrimary,
                                                    ),
                                                  ),
                                                  const SizedBox(height: 4),
                                                  Wrap(
                                                    spacing: 8,
                                                    runSpacing: 2,
                                                    crossAxisAlignment: WrapCrossAlignment.center,
                                                    children: [
                                                      _StockBadge(
                                                        stockText: stockText,
                                                        isUnlimited: isUnlimited,
                                                        outOfStock: outOfStock,
                                                        onTap: () => _showStockDialog(pkg),
                                                        l10n: l10n,
                                                      ),
                                                      if (hasDiscount)
                                                        Container(
                                                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                                          decoration: BoxDecoration(
                                                            color: AppColors.error.withOpacity(0.1),
                                                            borderRadius: BorderRadius.circular(AppShapes.radiusSm),
                                                          ),
                                                          child: Text(
                                                            'Discounted -$discountPercent%',
                                                            style: textTheme.bodySmall?.copyWith(
                                                              color: AppColors.error,
                                                              fontWeight: FontWeight.w700,
                                                              fontSize: 11,
                                                            ),
                                                          ),
                                                        ),
                                                      if (freeDelivery)
                                                        Text(
                                                          l10n.translate('free_delivery'),
                                                          style: textTheme.bodySmall?.copyWith(
                                                            fontWeight: FontWeight.w600,
                                                            color: Colors.black,
                                                          ),
                                                        )
                                                      else if (deliveryLabel != null && deliveryLabel != 'Paid Delivery')
                                                        Text(
                                                          deliveryLabel,
                                                          style: textTheme.bodySmall?.copyWith(
                                                            fontWeight: FontWeight.w600,
                                                            color: Colors.blue.shade700,
                                                          ),
                                                        ),
                                                    ],
                                                  ),
                                                  if (outOfStock) ...[
                                                    const SizedBox(height: 6),
                                                    _OutOfStockBadge(),
                                                  ],
                                                ],
                                              ),
                                            ),
                                            PopupMenuButton<String>(
                                              onSelected: (value) {
                                                if (value == 'edit') {
                                                  _editPackage(pkg['id']);
                                                } else if (value == 'delete') {
                                                  _deletePackage(pkg['id']);
                                                }
                                              },
                                              icon: const Icon(Icons.more_vert, size: 20, color: AppColors.textPrimary),
                                              padding: EdgeInsets.zero,
                                              constraints: const BoxConstraints(),
                                              itemBuilder: (_) => [
                                                PopupMenuItem(value: 'edit', child: Text(l10n.translate('edit'))),
                                                PopupMenuItem(value: 'delete', child: Text(l10n.translate('delete'))),
                                              ],
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
    ]);
  }

  Widget _placeholderImage() {
    return Container(
      width: 80,
      height: 80,
      decoration: BoxDecoration(
        color: AppColors.primary.withOpacity(0.06),
        borderRadius: BorderRadius.circular(AppShapes.radiusSm),
      ),
      child: const Icon(Icons.card_giftcard, color: AppColors.primary, size: 32),
    );
  }
}

// ── Stock badge ──
class _StockBadge extends StatelessWidget {
  final String stockText;
  final bool isUnlimited;
  final bool outOfStock;
  final VoidCallback onTap;
  final AppLocalizations l10n;
  const _StockBadge({
    required this.stockText,
    required this.isUnlimited,
    required this.outOfStock,
    required this.onTap,
    required this.l10n,
  });

  @override
  Widget build(BuildContext context) {
    final Color dotColor = isUnlimited
        ? AppColors.textMuted
        : (outOfStock ? AppColors.error : AppColors.success);
    final String displayText = isUnlimited
        ? l10n.translate('unlimited_stock')
        : '${l10n.translate('stock_label')}: $stockText';

    return GestureDetector(
      onTap: onTap,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(width: 6, height: 6, decoration: BoxDecoration(shape: BoxShape.circle, color: dotColor)),
          const SizedBox(width: 4),
          Flexible(
            child: Text(
              displayText,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                fontWeight: FontWeight.w700,
                color: isUnlimited ? AppColors.textMuted : AppColors.textPrimary,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}

class _OutOfStockBadge extends StatelessWidget {
  const _OutOfStockBadge();

  @override
  Widget build(BuildContext context) {
    return Container(
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
          Text(
            'Out of stock',
            style: TextStyle(fontSize: 11, color: Colors.grey, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}
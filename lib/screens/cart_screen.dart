// lib/screens/cart_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:dio/dio.dart';
import '../api/client.dart';
import '../models/cart.dart';
import '../providers/cart_provider.dart';
import '../providers/wishlist_provider.dart';
import '../providers/auth_provider.dart';
import '../models/product.dart';
import '../utils/format_utils.dart';
import '../theme/app_theme.dart';
import '../l10n/app_localizations.dart';
import '../widgets/notification_bell.dart';
import 'checkout_screen.dart';
import 'login_screen.dart';

class CartScreen extends ConsumerStatefulWidget {
  const CartScreen({Key? key}) : super(key: key);
  @override
  ConsumerState<CartScreen> createState() => _CartScreenState();
}

class _CartScreenState extends ConsumerState<CartScreen> {
  // Track which items are currently being removed
  final Set<int> _removingItems = {};
  String? _noticeMessage;

  Future<void> _handleRemove(int itemId) async {
    if (_removingItems.contains(itemId)) return; // prevent double-tap

    setState(() => _removingItems.add(itemId));

    try {
      final response = await ApiClient.instance.delete('/cart/remove_item/$itemId');
      final data = response.data as Map<String, dynamic>?;

      // Check for cascade notice
      final notice = data?['notice'] as String?;
      if (notice != null && notice.isNotEmpty) {
        setState(() => _noticeMessage = notice);
        Future.delayed(const Duration(seconds: 5), () {
          if (mounted) setState(() => _noticeMessage = null);
        });
      }
      // Refresh the cart provider (it will re-fetch)
      await ref.read(cartProvider.notifier).fetchCart();
    } on DioException catch (e) {
      if (e.response?.statusCode != 404) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(e.response?.data?['error'] ?? 'Failed to remove item'),
            backgroundColor: AppColors.error,
          ),
        );
      } else {
        // Item already gone – just refresh cart silently
        await ref.read(cartProvider.notifier).fetchCart();
      }
    } catch (_) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Something went wrong'),
          backgroundColor: AppColors.error,
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _removingItems.remove(itemId));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final cart = ref.watch(cartProvider);
    final cartNotifier = ref.read(cartProvider.notifier);

    if (cart == null) {
      return const Scaffold(
        backgroundColor: AppColors.pageBackground,
        body: Center(child: CircularProgressIndicator(color: AppColors.primary)),
      );
    }

    final subtotal = cart.totalPrice;
    final minimumBulkProgress = cart.minimumBulkProgress ?? {};

    return Scaffold(
      backgroundColor: AppColors.cardBackground,
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(cart.items.length, l10n),
            if (_noticeMessage != null)
              Container(
                width: double.infinity,
                color: Colors.blue.shade50,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                child: Text(
                  _noticeMessage!,
                  style: TextStyle(color: Colors.blue.shade700, fontSize: 13),
                ),
              ),
            Expanded(
              child: Container(
                color: AppColors.productListBackground,
                child: cart.items.isEmpty
                    ? _buildEmptyState(l10n)
                    : ListView(
                        padding: const EdgeInsets.fromLTRB(
                            AppSpacing.xs, AppSpacing.sm, AppSpacing.xs, AppSpacing.sm),
                        children: cart.items
                            .map((item) => _buildCartItemCard(
                                  item,
                                  cartNotifier,
                                  minimumBulkProgress,
                                  l10n,
                                ))
                            .toList(),
                      ),
              ),
            ),
            if (cart.items.isNotEmpty)
              Container(
                color: AppColors.cardBackground,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _buildPriceSummary(subtotal, l10n),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(
                          AppSpacing.xs, 0, AppSpacing.xs, AppSpacing.sm),
                      child: _buildCheckoutButton(l10n),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(int itemCount, AppLocalizations l10n) {
    final route = ModalRoute.of(context);
    final isTab = route?.settings.name == '/main';
    final canPop = !isTab && Navigator.of(context).canPop();

    return Container(
      height: 56,
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs),
      color: AppColors.cardBackground,
      child: Row(
        children: [
          if (canPop)
            IconButton(
              icon: const Icon(Icons.chevron_left, size: 24, color: AppColors.textPrimary),
              onPressed: () => Navigator.pop(context),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
            ),
          if (canPop) const SizedBox(width: AppSpacing.sm),
          Text(
            l10n.translate('my_cart'),
            style: const TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w600,
              color: AppColors.textPrimary,
            ),
          ),
          if (itemCount > 0) ...[
            const SizedBox(width: 4),
            Text(
              '($itemCount)',
              style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w600,
                color: AppColors.primary,
              ),
            ),
          ],
          const Spacer(),
          const NotificationBell(),
        ],
      ),
    );
  }

  Widget _buildEmptyState(AppLocalizations l10n) {
    return Center(
      child: Container(
        padding: const EdgeInsets.all(32),
        margin: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: AppColors.cardBackground,
          borderRadius: BorderRadius.circular(24),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.06),
              blurRadius: 16,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 100,
              height: 100,
              decoration: BoxDecoration(
                color: AppColors.primary.withOpacity(0.08),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.shopping_bag_outlined, size: 48, color: AppColors.primary),
            ),
            const SizedBox(height: 20),
            Text(l10n.translate('cart_empty'),
                style: const TextStyle(
                    fontSize: 20, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
            const SizedBox(height: 8),
            Text(l10n.translate('cart_empty_subtitle'),
                style: const TextStyle(fontSize: 14, color: AppColors.textMuted)),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: () => Navigator.pushNamed(context, '/all-products'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
                elevation: 2,
              ),
              child: Text(l10n.translate('explore_products'),
                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCartItemCard(
    CartItem item,
    dynamic cartNotifier,
    Map<int, BulkProgress> minimumBulkProgress,
    AppLocalizations l10n,
  ) {
    final textTheme = Theme.of(context).textTheme;
    final lineTotal = item.price * item.quantity;
    final variantAttrs = item.variant;
    final hasVariants = variantAttrs.isNotEmpty;
    final isRemoving = _removingItems.contains(item.id);

    // Bulk MOQ info
    final moqInfo = item.productId != 0 ? minimumBulkProgress[item.productId] : null;
    final isBulkItem = item.bulkEnabled && moqInfo != null;
    final moq = moqInfo?.minimumRequired ?? 0;
    final totalForProduct = moqInfo?.currentQuantity ?? 0;
    final belowMoq = isBulkItem && !moqInfo!.met;

    final minQty = (item.bulkEnabled && item.minimumBulkQuantity != null)
        ? item.minimumBulkQuantity!
        : 1;

    return Container(
      margin: const EdgeInsets.only(bottom: AppSpacing.xs),
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.cardBackground,
        borderRadius: BorderRadius.circular(AppShapes.radiusMd),
        border: Border.all(color: AppColors.borderLight, width: 1),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(AppShapes.radiusSm),
            child: Image.network(
              item.imageUrl,
              width: 80,
              height: 80,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => Container(
                width: 80,
                height: 80,
                color: AppColors.hoverState,
                child: Icon(Icons.image_not_supported, color: AppColors.textMuted, size: 24),
              ),
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(item.title,
                    style: textTheme.headlineMedium?.copyWith(
                        fontSize: 14, fontWeight: FontWeight.w600),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis),
                // Bulk badge
                if (item.bulkEnabled) ...[
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.purple.shade100,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: const Text(
                          'WHOLESALE',
                          style: TextStyle(
                            color: Colors.purple,
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      if (moq > 1)
                        Padding(
                          padding: const EdgeInsets.only(left: 6),
                          child: Text(
                            'Min. $moq pcs (total: $totalForProduct)',
                            style: const TextStyle(fontSize: 11, color: Colors.grey),
                          ),
                        ),
                    ],
                  ),
                ],
                // MOQ warning if not met
                if (belowMoq)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      '⚠️ Add ${moqInfo!.remaining} more to meet minimum order of $moq at checkout.',
                      style: const TextStyle(color: Colors.amber, fontSize: 12),
                    ),
                  ),
                if (hasVariants) ...[
                  const SizedBox(height: 4),
                  Wrap(
                    spacing: 4,
                    runSpacing: 4,
                    children: variantAttrs.entries.map((entry) {
                      return Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.grey.shade100,
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: Colors.grey.shade300),
                        ),
                        child: Text(
                          '${entry.key}: ${entry.value}',
                          style: const TextStyle(
                            fontSize: 11,
                            color: AppColors.textSecondary,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                ],
                const SizedBox(height: 4),
                Text('${FormatUtils.price(item.price)} ${l10n.translate("each")}',
                    style: textTheme.bodySmall?.copyWith(color: AppColors.textMuted)),
                const SizedBox(height: AppSpacing.xs),
                Text(FormatUtils.price(lineTotal),
                    style: textTheme.titleMedium?.copyWith(
                        fontSize: 18, fontWeight: FontWeight.w700)),
                const SizedBox(height: AppSpacing.xs),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    _QuantityStepper(
                      quantity: item.quantity,
                      minQuantity: minQty,
                      maxQuantity: item.stock,
                      onDecrement: () {
                        if (item.quantity > minQty) {
                          cartNotifier.updateQuantity(item.id, item.quantity - 1);
                        }
                      },
                      onIncrement: () {
                        if (item.stock <= 0 || item.quantity < item.stock) {
                          cartNotifier.updateQuantity(item.id, item.quantity + 1);
                        }
                      },
                    ),
                    Row(
                      children: [
                        TextButton.icon(
                          onPressed: isRemoving
                              ? null
                              : () {
                                  final product = Product(
                                    id: item.effectiveId,
                                    title: item.title,
                                    price: item.price,
                                    imageUrl: item.imageUrl,
                                    rating: 0.0,
                                    reviewsCount: 0,
                                    soldCount: 0,
                                    freeShipping: false,
                                    effectivePrice: item.price,
                                  );
                                  ref.read(wishlistProvider.notifier).addItem(product);
                                  _handleRemove(item.id);
                                },
                          icon: Icon(Icons.favorite_border, size: 14, color: isRemoving ? Colors.grey : AppColors.primary),
                          label: Text(l10n.translate('save'),
                              style: TextStyle(fontSize: 12, color: isRemoving ? Colors.grey : AppColors.primary)),
                          style: TextButton.styleFrom(
                              padding: EdgeInsets.zero,
                              minimumSize: Size.zero,
                              tapTargetSize: MaterialTapTargetSize.shrinkWrap),
                        ),
                        const SizedBox(width: 12),
                        TextButton.icon(
                          onPressed: isRemoving ? null : () => _handleRemove(item.id),
                          icon: isRemoving
                              ? SizedBox(
                                  width: 14,
                                  height: 14,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: AppColors.error,
                                  ),
                                )
                              : Icon(Icons.delete_outline, size: 14, color: AppColors.error),
                          label: Text(l10n.translate('remove'),
                              style: TextStyle(fontSize: 12, color: isRemoving ? Colors.grey : AppColors.error)),
                          style: TextButton.styleFrom(
                              padding: EdgeInsets.zero,
                              minimumSize: Size.zero,
                              tapTargetSize: MaterialTapTargetSize.shrinkWrap),
                        ),
                      ],
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPriceSummary(double subtotal, AppLocalizations l10n) {
    final textTheme = Theme.of(context).textTheme;
    return Container(
      padding: const EdgeInsets.fromLTRB(AppSpacing.md, AppSpacing.md, AppSpacing.md, AppSpacing.sm),
      decoration: const BoxDecoration(
        color: AppColors.cardBackground,
        border: Border(
          top: BorderSide(color: AppColors.borderLight, width: 1),
        ),
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(l10n.translate('subtotal'),
                  style: textTheme.bodyMedium?.copyWith(color: AppColors.textMuted)),
              Text(FormatUtils.price(subtotal),
                  style: textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w500)),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(l10n.translate('shipping'),
                  style: textTheme.bodyMedium?.copyWith(color: AppColors.textMuted)),
              Text(l10n.translate('calculated_at_checkout'),
                  style: textTheme.bodySmall?.copyWith(color: AppColors.textMuted)),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          const Divider(color: AppColors.borderLight, thickness: 1, height: 1),
          const SizedBox(height: AppSpacing.sm),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(l10n.translate('estimated_total'),
                  style: textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w600)),
              Text(FormatUtils.price(subtotal),
                  style: textTheme.bodyLarge?.copyWith(
                      fontWeight: FontWeight.w700, color: AppColors.primary)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildCheckoutButton(AppLocalizations l10n) {
    return ElevatedButton(
      onPressed: () {
        final authState = ref.read(authProvider);
        final user = authState.valueOrNull;
        if (user == null) {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const LoginScreen()),
          );
          return;
        }
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const CheckoutScreen()),
        );
      },
      style: ElevatedButton.styleFrom(
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        minimumSize: const Size(double.infinity, 52),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppShapes.radiusSm)),
        elevation: 2,
        shadowColor: AppColors.primary.withOpacity(0.2),
      ),
      child: Text(l10n.translate('proceed_to_checkout'),
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
    );
  }
}

class _QuantityStepper extends StatelessWidget {
  final int quantity;
  final int minQuantity;
  final int maxQuantity;
  final VoidCallback onDecrement;
  final VoidCallback onIncrement;

  const _QuantityStepper({
    required this.quantity,
    required this.minQuantity,
    required this.maxQuantity,
    required this.onDecrement,
    required this.onIncrement,
  });

  @override
  Widget build(BuildContext context) {
    final canDecrement = quantity > minQuantity;
    final canIncrement = maxQuantity <= 0 || quantity < maxQuantity;

    return Container(
      height: 36,
      decoration: BoxDecoration(
        color: AppColors.hoverState,
        borderRadius: BorderRadius.circular(AppShapes.radiusFull),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          GestureDetector(
            onTap: canDecrement ? onDecrement : null,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              child: Icon(Icons.remove,
                  size: 18,
                  color: canDecrement ? AppColors.textPrimary : AppColors.textMuted),
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6),
            child: Text(
              '$quantity',
              style: const TextStyle(
                  fontSize: 15, fontWeight: FontWeight.w500, color: AppColors.textPrimary),
            ),
          ),
          GestureDetector(
            onTap: canIncrement ? onIncrement : null,
            child: Container(
              padding: const EdgeInsets.all(4),
              margin: const EdgeInsets.all(2),
              decoration: BoxDecoration(
                color: canIncrement ? AppColors.textPrimary : AppColors.textMuted,
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.add, size: 16, color: Colors.white),
            ),
          ),
        ],
      ),
    );
  }
}
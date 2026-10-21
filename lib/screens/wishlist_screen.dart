// lib/screens/wishlist_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/wishlist_provider.dart';
import '../providers/auth_provider.dart';
import '../models/wishlist.dart';
import '../utils/format_utils.dart';
import '../theme/app_theme.dart';
import '../l10n/app_localizations.dart';
import 'product_detail_screen.dart';

class WishlistScreen extends ConsumerStatefulWidget {
  const WishlistScreen({Key? key}) : super(key: key);

  @override
  ConsumerState<WishlistScreen> createState() => _WishlistScreenState();
}

class _WishlistScreenState extends ConsumerState<WishlistScreen> {
  @override
  void initState() {
    super.initState();
    Future.microtask(() {
      if (mounted) {
        ref.read(wishlistProvider.notifier).fetchWishlist();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    ref.listen(authProvider, (prev, next) {
      if (prev != next) {
        Future.microtask(() {
          if (mounted) {
            ref.read(wishlistProvider.notifier).fetchWishlist();
          }
        });
      }
    });

    final wishlist = ref.watch(wishlistProvider);

    return Scaffold(
      backgroundColor: AppColors.cardBackground,
      appBar: AppBar(
        title: Text(l10n.translate('wishlist_title'),
            style: const TextStyle(fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
        backgroundColor: AppColors.cardBackground,
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          await ref.read(wishlistProvider.notifier).fetchWishlist();
        },
        child: wishlist.isEmpty
            ? ListView(
                children: [
                  SizedBox(height: MediaQuery.of(context).size.height * 0.3),
                  _buildEmptyState(context, l10n),
                ],
              )
            : ListView.builder(
                padding: const EdgeInsets.all(AppSpacing.xs),
                itemCount: wishlist.length,
                itemBuilder: (ctx, index) =>
                    _buildWishlistItemCard(context, wishlist[index], ref, l10n),
              ),
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context, AppLocalizations l10n) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.favorite_border, size: 64, color: Colors.grey[400]),
          const SizedBox(height: 16),
          Text(l10n.translate('wishlist_empty'),
              style: const TextStyle(fontSize: 18, color: AppColors.textMuted)),
        ],
      ),
    );
  }

  Widget _buildWishlistItemCard(
      BuildContext context, WishlistItem item, WidgetRef ref, AppLocalizations l10n) {
    final textTheme = Theme.of(context).textTheme;
    final imageUrl = item.imageUrl.isNotEmpty
        ? item.imageUrl
        : (item.imageUrls.isNotEmpty ? item.imageUrls.first : '');

    final showBulkBadge = item.bulkEnabled;

    return Container(
      margin: const EdgeInsets.only(bottom: AppSpacing.xs),
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.cardBackground,
        borderRadius: BorderRadius.circular(AppShapes.radiusMd),
        border: Border.all(color: AppColors.borderLight),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withOpacity(0.04),
              blurRadius: 4,
              offset: const Offset(0, 2)),
        ],
      ),
      child: Row(
        children: [
          GestureDetector(
            onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (_) => ProductDetailScreen(productId: item.productId))),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(AppShapes.radiusSm),
              child: Image.network(
                imageUrl,
                width: 80,
                height: 80,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => Container(
                  width: 80,
                  height: 80,
                  color: AppColors.hoverState,
                  child: Icon(Icons.image_not_supported,
                      color: AppColors.textMuted, size: 24),
                ),
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
                const SizedBox(height: 4),
                if (showBulkBadge) ...[
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.purple.shade100,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: const Text(
                          'WHOLESALE',
                          style: TextStyle(
                              color: Colors.purple,
                              fontSize: 10,
                              fontWeight: FontWeight.w700),
                        ),
                      ),
                      if (item.minimumBulkQuantity != null &&
                          item.minimumBulkQuantity! > 1)
                        Padding(
                          padding: const EdgeInsets.only(left: 6),
                          child: Text(
                            'Min. ${item.minimumBulkQuantity} pcs',
                            style: const TextStyle(
                                fontSize: 11, color: Colors.grey),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 4),
                ],
                Text(
                  '${FormatUtils.price(item.effectivePrice ?? item.price)} ${l10n.translate("each")}',
                  style: textTheme.bodySmall?.copyWith(color: AppColors.textMuted),
                ),
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerRight,
                  child: IconButton(
                    icon: const Icon(Icons.delete_outline, color: AppColors.error),
                    onPressed: () => ref
                        .read(wishlistProvider.notifier)
                        .removeItem(item.productId),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
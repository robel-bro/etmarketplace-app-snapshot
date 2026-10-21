// 📁 lib/widgets/super_deal_card.dart
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:intl/intl.dart';
import '../models/product.dart';
import '../theme/app_theme.dart';

final _priceFormatter = NumberFormat('#,##0.00', 'en_US');

class SuperDealCard extends StatelessWidget {
  final Product product;
  const SuperDealCard({Key? key, required this.product}) : super(key: key);

  Widget? _buildDeliveryBadge() {
    if (product.freeShipping ||
        (product.sellerPaysShipping &&
            product.shippingSubsidyType == 'full')) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.local_shipping_outlined, size: 10, color: AppColors.success),
          const SizedBox(width: 2),
          Text(
            'Free',
            style: TextStyle(color: AppColors.success, fontSize: 9, fontWeight: FontWeight.w700),
          ),
        ],
      );
    }

    if (product.sellerPaysShipping &&
        product.shippingSubsidyType == 'percentage' &&
        product.shippingSubsidyValue != null) {
      final discount = product.shippingSubsidyValue!.round();
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.local_shipping_outlined, size: 10, color: AppColors.primary),
          const SizedBox(width: 2),
          Text(
            '$discount% off',
            style: TextStyle(color: AppColors.primary, fontSize: 9, fontWeight: FontWeight.w700),
          ),
        ],
      );
    }

    return null;
  }

  @override
  Widget build(BuildContext context) {
    final deliveryBadge = _buildDeliveryBadge();

    final double originalPrice = product.price;
    double salePrice = product.effectivePrice;
    if (product.flashSalePrice != null && product.flashSalePrice! > 0) {
      salePrice = product.flashSalePrice!;
    }

    final bool hasDiscount = originalPrice > salePrice && originalPrice > 0;
    final int discount = hasDiscount
        ? ((1 - salePrice / originalPrice) * 100).round()
        : product.discountPercentage;

    final String priceText = _priceFormatter.format(salePrice);

    return Container(
      width: 140,
      decoration: BoxDecoration(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(AppShapes.radiusSm),
        border: Border.all(color: Colors.white.withOpacity(0.15), width: 0.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.vertical(
              top: Radius.circular(AppShapes.radiusSm),
            ),
            child: AspectRatio(
              aspectRatio: 0.95,
              child: CachedNetworkImage(
                imageUrl: product.imageUrl,
                fit: BoxFit.cover,
                width: double.infinity,
                height: double.infinity,
              ),
            ),
          ),
          // Tight padding – no overflow
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 2, 4, 2),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  product.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 14,               // ★ increased
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 1),
                Text(
                  'ETB $priceText',
                  style: const TextStyle(
                    fontSize: 16,               // ★ increased
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 1),
                // Rating row with discount badge
                Row(
                  children: [
                    ...List.generate(5, (index) {
                      final starValue = index + 1;
                      final rating = product.rating;
                      IconData icon;
                      if (starValue <= rating.floor()) {
                        icon = Icons.star_rounded;
                      } else if (starValue - 0.5 <= rating) {
                        icon = Icons.star_half_rounded;
                      } else {
                        icon = Icons.star_outline_rounded;
                      }
                      return Icon(icon, size: 10, color: AppColors.starGold);
                    }),
                    const SizedBox(width: 2),
                    Text(
                      '(${product.reviewsCount})',
                      style: const TextStyle(fontSize: 9, color: AppColors.textMuted),
                    ),
                    if (discount > 0) ...[
                      const SizedBox(width: 6),
                      Text(
                        '-$discount% OFF',
                        style: const TextStyle(
                          color: AppColors.error,
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                    if (deliveryBadge != null) ...[
                      const SizedBox(width: 6),
                      deliveryBadge,
                    ],
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
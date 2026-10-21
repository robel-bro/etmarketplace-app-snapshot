// 📁 lib/widgets/flash_deal_card.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:intl/intl.dart';               // ★ for NumberFormat
import '../models/product.dart';
import '../theme/app_theme.dart';

// ─── Local price formatter (comma, dot, no currency symbol) ───
final _priceFormatter = NumberFormat('#,##0.00', 'en_US');

class _PulsingChip extends StatefulWidget {
  final Widget child;
  const _PulsingChip({required this.child});
  @override
  State<_PulsingChip> createState() => _PulsingChipState();
}
class _PulsingChipState extends State<_PulsingChip>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;
  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    )..repeat(reverse: true);
    _animation = Tween<double>(begin: 0.6, end: 1.0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );
  }
  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }
  @override
  Widget build(BuildContext context) =>
      FadeTransition(opacity: _animation, child: widget.child);
}

class _FlashDealCountdown extends StatefulWidget {
  final DateTime endsAt;
  const _FlashDealCountdown({required this.endsAt});
  @override
  State<_FlashDealCountdown> createState() => _FlashDealCountdownState();
}
class _FlashDealCountdownState extends State<_FlashDealCountdown> {
  late Timer _timer;
  Duration _remaining = Duration.zero;
  @override
  void initState() {
    super.initState();
    _updateRemaining();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) => _updateRemaining());
  }
  @override
  void dispose() {
    _timer.cancel();
    super.dispose();
  }
  void _updateRemaining() {
    if (!mounted) return;
    final diff = widget.endsAt.difference(DateTime.now());
    setState(() {
      _remaining = diff.isNegative ? Duration.zero : diff;
    });
  }
  @override
  Widget build(BuildContext context) {
    if (_remaining == Duration.zero) {
      return const Text(
        'Expired',
        style: TextStyle(color: AppColors.error, fontSize: 11, fontWeight: FontWeight.w700),
      );
    }
    final h = _remaining.inHours;
    final m = _remaining.inMinutes.remainder(60);
    final s = _remaining.inSeconds.remainder(60);
    return Text(
      '${h}h ${m}m ${s}s',
      style: const TextStyle(
        color: AppColors.error,
        fontSize: 11,
        fontWeight: FontWeight.w700,
      ),
    );
  }
}

class FlashDealCard extends StatelessWidget {
  final Product product;
  const FlashDealCard({Key? key, required this.product}) : super(key: key);

  Widget? _buildDeliveryRibbon() {
    final bool freeDelivery = product.freeShipping ||
        (product.sellerPaysShipping && product.shippingSubsidyType == 'full');
    final bool percentOff = product.sellerPaysShipping &&
        product.shippingSubsidyType == 'percentage' &&
        product.shippingSubsidyValue != null;
    final bool fixedOff = product.sellerPaysShipping &&
        product.shippingSubsidyType == 'fixed' &&
        product.shippingSubsidyValue != null;

    if (!freeDelivery && !percentOff && !fixedOff) return null;

    String text;
    Color bgColor;
    if (freeDelivery) {
      text = 'Free';
      bgColor = const Color(0xFF42A5F5);
    } else if (percentOff) {
      text = '${product.shippingSubsidyValue!.round()}% off';
      bgColor = const Color(0xFFFF7A00);
    } else {
      text = '-${product.shippingSubsidyValue!.round()}';
      bgColor = const Color(0xFFFF7A00);
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 1),
      color: bgColor,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.local_shipping, size: 10, color: Colors.white),
          const SizedBox(width: 2),
          Text(
            text,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 10,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final deliveryRibbon = _buildDeliveryRibbon();
    // stock is nullable now
    final int? stock = product.stock;
    final int soldCount = product.soldCount;

    final showCountdown = product.isFlashSale &&
        product.flashSaleEndsAt != null &&
        product.flashSaleEndsAt!.isAfter(DateTime.now());

    final double originalPrice = product.price;
    double salePrice = product.effectivePrice;
    if (product.flashSalePrice != null && product.flashSalePrice! > 0) {
      salePrice = product.flashSalePrice!;
    }

    final bool hasDiscount = originalPrice > salePrice && originalPrice > 0;
    final int discount = hasDiscount
        ? ((1 - salePrice / originalPrice) * 100).round()
        : product.discountPercentage;

    // ★ Price formatted with comma + dot, no currency symbol
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
              child: Stack(
                fit: StackFit.expand,
                children: [
                  CachedNetworkImage(
                    imageUrl: product.imageUrl,
                    fit: BoxFit.cover,
                  ),
                  if (deliveryRibbon != null)
                    Positioned(
                      bottom: 0,
                      left: 0,
                      right: 0,
                      child: deliveryRibbon,
                    ),
                ],
              ),
            ),
          ),

          LayoutBuilder(
            builder: (context, constraints) {
              final isWide = constraints.maxWidth >= 150;
              final textContainer = Padding(
                padding: EdgeInsets.fromLTRB(isWide ? 5 : 3, 1, isWide ? 5 : 3, isWide ? 4 : 2),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      product.title,
                      maxLines: isWide ? 2 : 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: isWide ? 14 : 12,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 1),

                    // ★ Price row – only one ETB
                    Row(
                      children: [
                        Text(
                          'ETB $priceText',   // priceText is just the number
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: isWide ? 16 : 14,
                            fontWeight: FontWeight.w700,
                            color: AppColors.textPrimary,
                          ),
                        ),
                      ],
                    ),

                    // ★ Rectangular discount badge
                    if (discount > 0) ...[
                      const SizedBox(height: 2),
                      _PulsingChip(
                        child: Container(
                          padding: EdgeInsets.symmetric(
                            horizontal: isWide ? 5 : 3,
                            vertical: 1,
                          ),
                          decoration: BoxDecoration(
                            color: AppColors.error,
                            borderRadius: BorderRadius.zero,
                          ),
                          child: Text(
                            '-$discount% OFF',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: isWide ? 12 : 10,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                      ),
                    ],

                    const SizedBox(height: 2),

                    if (isWide) ...[
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
                            return Icon(icon, size: 12, color: AppColors.starGold);
                          }),
                          const SizedBox(width: 2),
                          Text(
                            '(${product.reviewsCount})',
                            style: const TextStyle(fontSize: 11, color: AppColors.textMuted),
                          ),
                        ],
                      ),
                      const SizedBox(height: 1),
                      Row(
                        children: [
                          // ★ Handle nullable stock
                          if (stock == null)
                            Text(
                              'Unlimited',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: AppColors.textSecondary,
                              ),
                            )
                          else if (stock > 0)
                            Text(
                              '$stock in stock',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: (stock <= 5) ? AppColors.error : AppColors.textSecondary,
                              ),
                            ),
                          if (stock != null && stock > 0 && soldCount > 0) const SizedBox(width: 6),
                          if (soldCount > 0)
                            Text(
                              '$soldCount sold',
                              style: const TextStyle(fontSize: 11, color: AppColors.textSecondary),
                            ),
                        ],
                      ),
                      if (showCountdown) ...[
                        const SizedBox(height: 2),
                        _FlashDealCountdown(endsAt: product.flashSaleEndsAt!),
                      ],
                    ],
                  ],
                ),
              );

              if (isWide) {
                return Container(
                  color: Colors.white,
                  child: textContainer,
                );
              }
              return textContainer;
            },
          ),
        ],
      ),
    );
  }
}
// lib/widgets/product_card.dart (hardened – unorderable overlay, stock‑aware, delivery badges)
import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:shimmer/shimmer.dart';
import '../models/product.dart';
import '../utils/format_utils.dart';
import '../utils/url_utils.dart';
import '../theme/app_theme.dart';

class ProductCard extends StatelessWidget {
  final Product product;
  final int maxTitleLines;
  final bool showSupplierBadge;
  final bool isDeal;
  final bool showOutOfStock;
  final bool hideCartButton;
  final bool compact;
  final bool hideMembershipBadge;

  const ProductCard({
    Key? key,
    required this.product,
    this.maxTitleLines = 2,
    this.showSupplierBadge = false,
    this.isDeal = false,
    this.showOutOfStock = false,
    this.hideCartButton = false,
    this.compact = false,
    this.hideMembershipBadge = false,
  }) : super(key: key);

  // ─── Membership badge – icon + text using only the tier's original color ─────
  Widget? _buildMembershipBadge({bool compactMode = false}) {
    final badgeText = product.vendor?.badge;
    if (badgeText == null || badgeText.isEmpty) return null;

    final lower = badgeText.toLowerCase();
    String glyph;
    Color color;

    if (lower.contains('platinum')) {
      glyph = '💎';
      color = Colors.blue.shade700;
    } else if (lower.contains('gold')) {
      glyph = '🏆';
      color = const Color(0xFFF59E0B);
    } else if (lower.contains('silver')) {
      glyph = '🥈';
      color = const Color(0xFF9CA3AF);
    } else {
      glyph = '✨';
      color = const Color(0xFF6B7280);
    }

    if (compactMode) {
      return Text(glyph, style: TextStyle(fontSize: 14, color: color));
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(glyph, style: TextStyle(fontSize: 11, color: color)),
        const SizedBox(width: 2),
        Flexible(
          child: Text(
            badgeText,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 11,
              color: color,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ],
    );
  }

  // ★ Delivery ribbon – ONLY for free or subsidised delivery (never Paid Delivery)
  Widget? _buildDeliveryRibbon() {
    // 1. Use the new unified fields when available
    if (product.deliveryLabel != null &&
        product.deliveryLabel!.isNotEmpty &&
        product.deliveryLabel!.toLowerCase() != 'paid delivery' &&
        product.deliveryLabel!.toLowerCase() != 'paid shipping') {
      final isFree = product.freeDelivery ||
          product.deliveryLabel!.toLowerCase().contains('free');
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 2),
        color: isFree ? const Color(0xFF42A5F5) : const Color(0xFFFF7A00),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.local_shipping, size: 13, color: Colors.white),
            const SizedBox(width: 3),
            Flexible(
              child: Text(
                product.deliveryLabel!,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 9,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.2,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      );
    }

    // 2. Fallback to old API fields (remove once backend is fully updated)
    if (product.freeShipping) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 2),
        color: const Color(0xFF42A5F5),
        child: const Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.local_shipping, size: 13, color: Colors.white),
            SizedBox(width: 3),
            Text(
              'Free Delivery',
              style: TextStyle(
                color: Colors.white,
                fontSize: 9,
                fontWeight: FontWeight.w700,
                letterSpacing: -0.2,
              ),
            ),
          ],
        ),
      );
    }

    if (product.sellerPaysShipping &&
        product.shippingSubsidyType != null &&
        product.shippingSubsidyValue != null) {
      final type = product.shippingSubsidyType!.toLowerCase();
      final valueNum =
          double.tryParse(product.shippingSubsidyValue!.toString()) ?? 0;
      String text;

      if (type == 'percent') {
        text = '${valueNum.round()}% off Delivery';
      } else if (type == 'fixed') {
        text = 'ETB ${valueNum.round()} off Delivery';
      } else {
        return null;
      }

      return Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 2),
        color: const Color(0xFFFF7A00),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.local_shipping, size: 13, color: Colors.white),
            SizedBox(width: 3),
            Flexible(
              child: Text(
                text,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 9,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.2,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      );
    }

    // 3. No ribbon for paid delivery
    return null;
  }

  // ─── Non‑compact wholesale info – black/red only ─────
  Widget? _buildWholesaleInfo(TextTheme textTheme) {
    if (!product.bulkEnabled || compact) return null;

    int? displayStock = product.availableStock;
    if (displayStock == null) {
      final hasVariants = product.variants.isNotEmpty;
      final int? baseStock = product.stock;
      final int totalVariantStock = hasVariants
          ? product.variants.fold<int>(
              0, (sum, v) => sum + ((v['stock'] as num?)?.toInt() ?? 0))
          : 0;
      displayStock = hasVariants ? totalVariantStock : (baseStock ?? 0);
    }

    final bool isUnlimited = product.bulkEnabled && product.stock == null;
    final moq = product.minimumBulkQuantity;

    String stockPart;
    if (isUnlimited) {
      stockPart = 'Unlimited stock';
    } else if (displayStock != null) {
      if (displayStock > 0) {
        stockPart =
            displayStock <= 5 ? 'only $displayStock left' : '$displayStock in stock';
      } else {
        stockPart = '';
      }
    } else {
      stockPart = '';
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 4),
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            const Text(
              'WHOLESALE',
              style: TextStyle(
                color: Colors.black,
                fontSize: 9,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.3,
              ),
            ),
            const SizedBox(width: 6),
            if (stockPart.isNotEmpty || (moq != null && moq > 1))
              _WholesaleInfoSwitcher(
                key: ValueKey(product.id),
                stockPart: stockPart,
                displayStock: displayStock ?? 0,
                isUnlimited: isUnlimited,
                moq: moq,
                productId: product.id,
              ),
          ],
        ),
      ),
    );
  }

  // ─── Compact badge (WHOLESALE / only X left) ─────
  Widget? _buildCompactBadge() {
    if (!compact) return null;

    int? available = product.availableStock;
    bool isUnlimited = product.bulkEnabled && product.stock == null;

    int displayStock;
    if (available != null) {
      displayStock = available;
    } else {
      final hasVariants = product.variants.isNotEmpty;
      final int? baseStock = product.stock;
      final int totalVariantStock = hasVariants
          ? product.variants.fold<int>(
              0, (sum, v) => sum + ((v['stock'] as num?)?.toInt() ?? 0))
          : 0;
      displayStock = hasVariants ? totalVariantStock : (baseStock ?? 0);
    }

    final bool isLowStock =
        !isUnlimited && displayStock > 0 && displayStock <= 5;
    final bool isWholesale = product.bulkEnabled;

    if (!isWholesale && !isLowStock) return null;

    return _CompactBadgeSwitcher(
      key: ValueKey(product.id),
      showWholesale: isWholesale,
      showLowStock: isLowStock,
      lowStockCount: displayStock,
      productId: product.id,
    );
  }

  // ─── Overlay when product is not orderable ─────────────────
  Widget? _buildUnorderableOverlay(TextTheme textTheme) {
    // Use the new 'orderable' field from the API
    if (product.orderable == false && product.unavailableReason != null) {
      return Positioned.fill(
        child: Container(
          color: Colors.white70,
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(8.0),
              child: Text(
                product.unavailableReason!,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.red,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
        ),
      );
    }
    // Fallback for older API: if out of stock and showOutOfStock is true,
    // we might still want an overlay? Already handled by stockText.
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    final double effectivePrice =
        double.tryParse(product.effectivePrice.toString()) ?? 0.0;
    final double? originalPrice = product.originalPrice != null
        ? double.tryParse(product.originalPrice.toString())
        : null;
    final double rating =
        double.tryParse(product.rating.toString()) ?? 0.0;
    final int reviewsCount = product.reviewsCount;
    final int soldCount = product.soldCount;

    int? displayStock = product.availableStock;
    final bool isUnlimited = product.bulkEnabled && product.stock == null;

    if (displayStock == null) {
      final hasVariants = product.variants.isNotEmpty;
      final int? baseStock = product.stock;
      final int totalVariantStock = hasVariants
          ? product.variants.fold<int>(
              0, (sum, v) => sum + ((v['stock'] as num?)?.toInt() ?? 0))
          : 0;
      displayStock = hasVariants ? totalVariantStock : (baseStock ?? 0);
    }

    final bool hasDiscount = product.discountPercentage > 0;
    final bool showOriginal =
        hasDiscount && originalPrice != null && originalPrice > effectivePrice;

    String? stockText;
    if (!product.bulkEnabled && !compact) {
      if (displayStock != null && displayStock > 0 && displayStock <= 5) {
        stockText = 'only $displayStock left';
      } else if (displayStock != null &&
          displayStock == 0 &&
          showOutOfStock) {
        stockText = 'Out of stock';
      }
    }

    final cardDecoration = BoxDecoration(
      color: Colors.transparent,
      border: Border.all(color: Colors.transparent, width: 0),
    );

    final imageUrl = resolveUrl(product.imageUrl);

    final membershipBadge = !hideMembershipBadge
        ? _buildMembershipBadge(compactMode: compact)
        : null;

    Widget ratingRow;
    if (rating > 0 || reviewsCount > 0) {
      ratingRow = Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          ...List.generate(5, (index) {
            final starValue = index + 1;
            IconData icon;
            if (starValue <= rating.floor()) {
              icon = Icons.star_rounded;
            } else if (starValue - 0.5 <= rating) {
              icon = Icons.star_half_rounded;
            } else {
              icon = Icons.star_outline_rounded;
            }
            return Icon(
              icon,
              size: 14,
              color: Colors.orange,
            );
          }),
          const SizedBox(width: 2),
          Text(
            '($reviewsCount)',
            style: textTheme.bodySmall,
          ),
          if (membershipBadge != null) ...[
            const SizedBox(width: 6),
            Flexible(child: membershipBadge),
          ],
        ],
      );
    } else {
      ratingRow = Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Text(
            'Not rated yet',
            style: textTheme.bodySmall?.copyWith(
              color: AppColors.textMuted,
              fontStyle: FontStyle.italic,
            ),
          ),
          if (membershipBadge != null) ...[
            const SizedBox(width: 6),
            Flexible(child: membershipBadge),
          ],
        ],
      );
    }

    return Container(
      decoration: cardDecoration,
      child: Stack(
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.vertical(
                  top: Radius.circular(AppShapes.radiusSm),
                ),
                child: AspectRatio(
                  aspectRatio: 1.0,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      CachedNetworkImage(
                        imageUrl: imageUrl,
                        fit: BoxFit.cover,
                        placeholder: (_, __) => Shimmer.fromColors(
                          baseColor: Colors.grey.shade200,
                          highlightColor: Colors.grey.shade100,
                          child: Container(color: Colors.white),
                        ),
                        errorWidget: (_, __, ___) => Container(
                          color: Colors.grey.shade100,
                          child: Icon(Icons.image_not_supported_outlined,
                              color: Colors.grey.shade400, size: 32),
                        ),
                      ),
                      if (hasDiscount)
                        Positioned(
                          top: AppSpacing.xxs,
                          left: AppSpacing.xxs,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 4, vertical: 1),
                            decoration: BoxDecoration(
                              color: AppColors.error,
                              borderRadius:
                                  BorderRadius.circular(AppShapes.radiusSm),
                            ),
                            child: Text(
                              '-${product.discountPercentage}%',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 9,
                                fontWeight: FontWeight.w700,
                                letterSpacing: -0.2,
                              ),
                            ),
                          ),
                        ),
                      if (_buildDeliveryRibbon() != null)
                        Positioned(
                          bottom: 0,
                          left: 0,
                          right: 0,
                          child: _buildDeliveryRibbon()!,
                        ),
                    ],
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(AppSpacing.xs),
                child: LayoutBuilder(
                  builder: (ctx, constraints) {
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          product.title,
                          maxLines: maxTitleLines,
                          overflow: TextOverflow.ellipsis,
                          style: textTheme.headlineMedium,
                        ),
                        const SizedBox(height: 2),
                        _buildWholesaleInfo(textTheme) ?? const SizedBox.shrink(),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.baseline,
                          textBaseline: TextBaseline.alphabetic,
                          children: [
                            Text(
                              FormatUtils.price(effectivePrice),
                              style: textTheme.titleMedium?.copyWith(
                                color: Colors.black,
                                fontSize:
                                    (textTheme.titleMedium?.fontSize ?? 14) + 1,
                              ),
                            ),
                            if (showOriginal) ...[
                              const SizedBox(width: 6),
                              Flexible(
                                child: Text(
                                  FormatUtils.price(originalPrice!),
                                  style: textTheme.bodySmall?.copyWith(
                                    decoration: TextDecoration.lineThrough,
                                    color: AppColors.textMuted,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ],
                        ),
                        if (stockText != null) ...[
                          const SizedBox(height: 2),
                          Text(
                            stockText,
                            style: const TextStyle(
                              color: AppColors.error,
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                        const SizedBox(height: 2),
                        ratingRow,
                        if (compact) ...[
                          const SizedBox(height: 4),
                          _buildCompactBadge() ?? const SizedBox.shrink(),
                        ],
                      ],
                    );
                  },
                ),
              ),
            ],
          ),
          // Unorderable overlay on top of everything
          if (product.orderable == false)
            Positioned.fill(
              child: Container(
                color: Colors.white70,
                child: Center(
                  child: Padding(
                    padding: const EdgeInsets.all(8.0),
                    child: Text(
                      product.unavailableReason ?? 'Currently unavailable',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Colors.red,
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// ─── Non‑compact interchanging widget (unchanged) ─────
class _WholesaleInfoSwitcher extends StatefulWidget {
  final String stockPart;
  final int displayStock;
  final bool isUnlimited;
  final int? moq;
  final int productId;

  const _WholesaleInfoSwitcher({
    Key? key,
    required this.stockPart,
    required this.displayStock,
    required this.isUnlimited,
    this.moq,
    required this.productId,
  }) : super(key: key);

  @override
  State<_WholesaleInfoSwitcher> createState() => _WholesaleInfoSwitcherState();
}

class _WholesaleInfoSwitcherState extends State<_WholesaleInfoSwitcher> {
  late Timer _timer;
  bool _showStock = true;
  late int _intervalSeconds;

  @override
  void initState() {
    super.initState();
    final seededRandom = Random(widget.productId);
    _intervalSeconds = 4 + seededRandom.nextInt(5);
    _showStock = seededRandom.nextBool();
    _timer = Timer.periodic(Duration(seconds: _intervalSeconds), (_) {
      if (mounted) setState(() => _showStock = !_showStock);
    });
  }

  @override
  void dispose() {
    _timer.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bool hasStock = widget.stockPart.isNotEmpty;
    final bool hasMoq = widget.moq != null && widget.moq! > 1;

    if (hasStock && !hasMoq) return _buildStockInfo();
    if (!hasStock && hasMoq) return _buildMoqInfo();
    if (hasStock && hasMoq)
      return _showStock ? _buildStockInfo() : _buildMoqInfo();
    return const SizedBox.shrink();
  }

  Widget _buildStockInfo() {
    final bool isLow = widget.displayStock <= 5 && !widget.isUnlimited;
    final Color color = isLow ? AppColors.error : Colors.black;
    final FontWeight weight = isLow ? FontWeight.w700 : FontWeight.w500;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.inventory_2_outlined, size: 12, color: color),
        const SizedBox(width: 2),
        Flexible(
          child: Text(
            widget.stockPart,
            style: TextStyle(fontSize: 10, color: color, fontWeight: weight),
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }

  Widget _buildMoqInfo() {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.archive_outlined, size: 12, color: Colors.black),
        const SizedBox(width: 2),
        Flexible(
          child: Text(
            'Min ${widget.moq} pcs',
            style: const TextStyle(
              fontSize: 10,
              color: Colors.black,
              fontWeight: FontWeight.w500,
            ),
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}

// ─── Compact badge switcher (unchanged) ─────
class _CompactBadgeSwitcher extends StatefulWidget {
  final bool showWholesale;
  final bool showLowStock;
  final int lowStockCount;
  final int productId;

  const _CompactBadgeSwitcher({
    Key? key,
    required this.showWholesale,
    required this.showLowStock,
    required this.lowStockCount,
    required this.productId,
  }) : super(key: key);

  @override
  State<_CompactBadgeSwitcher> createState() => _CompactBadgeSwitcherState();
}

class _CompactBadgeSwitcherState extends State<_CompactBadgeSwitcher> {
  late Timer _timer;
  bool _showWholesale = true;

  @override
  void initState() {
    super.initState();
    if (widget.showWholesale && widget.showLowStock) {
      final seededRandom = Random(widget.productId);
      final interval = 4 + seededRandom.nextInt(5);
      _showWholesale = seededRandom.nextBool();
      _timer = Timer.periodic(Duration(seconds: interval), (_) {
        if (mounted) setState(() => _showWholesale = !_showWholesale);
      });
    }
  }

  @override
  void dispose() {
    if (widget.showWholesale && widget.showLowStock) _timer.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.showWholesale && widget.showLowStock) {
      return _showWholesale ? _buildWholesaleBadge() : _buildLowStockBadge();
    } else if (widget.showWholesale) {
      return _buildWholesaleBadge();
    } else if (widget.showLowStock) {
      return _buildLowStockBadge();
    }
    return const SizedBox.shrink();
  }

  Widget _buildWholesaleBadge() {
    return const Text(
      'WHOLESALE',
      style: TextStyle(
        color: Colors.black,
        fontSize: 8,
        fontWeight: FontWeight.w700,
      ),
    );
  }

  Widget _buildLowStockBadge() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
      decoration: BoxDecoration(
        color: AppColors.error.withOpacity(0.1),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: AppColors.error, width: 0.5),
      ),
      child: Text(
        'only ${widget.lowStockCount} left',
        style: const TextStyle(
          color: AppColors.error,
          fontSize: 8,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}
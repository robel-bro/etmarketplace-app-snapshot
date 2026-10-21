// 📁 lib/widgets/package_card.dart (hardened – out‑of‑stock overlay, delivery label support)
import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:shimmer/shimmer.dart';
import '../models/product.dart';
import '../utils/format_utils.dart';
import '../theme/app_theme.dart';
import '../l10n/app_localizations.dart';

class PackageCard extends StatefulWidget {
  final Product product;
  final int? itemCount;
  final bool showPackageBadge;

  const PackageCard({
    Key? key,
    required this.product,
    this.itemCount,
    this.showPackageBadge = true,
  }) : super(key: key);

  @override
  State<PackageCard> createState() => _PackageCardState();
}

class _PackageCardState extends State<PackageCard> {
  int _currentImageIndex = 0;
  Timer? _rotationTimer;

  List<String> get _allImages {
    final images = widget.product.images;
    if (images.isNotEmpty) return images;
    if (widget.product.imageUrl.isNotEmpty) return [widget.product.imageUrl];
    return ['https://placehold.co/400x400?text=No+Image'];
  }

  @override
  void initState() {
    super.initState();
    _startAutoRotation();
  }

  void _startAutoRotation() {
    if (_allImages.length <= 1) return;
    _rotationTimer = Timer.periodic(const Duration(seconds: 10), (_) {
      if (!mounted) return;
      setState(() {
        _currentImageIndex = (_currentImageIndex + 1) % _allImages.length;
      });
    });
  }

  @override
  void dispose() {
    _rotationTimer?.cancel();
    super.dispose();
  }

  // ─── Membership badge – shimmer kept, original tier colour, no ellipsis (wraps) ─────
  Widget? _buildMembershipBadge() {
    final badgeText = widget.product.vendor?.badge;
    if (badgeText == null || badgeText.isEmpty) return null;
    final tierLower = badgeText.toLowerCase();

    String glyph;
    Color baseColor;

    if (tierLower.contains('platinum')) {
      glyph = '💎';
      baseColor = Colors.blue.shade700;
    } else if (tierLower.contains('gold')) {
      glyph = '🏆';
      baseColor = const Color(0xFFF59E0B);
    } else if (tierLower.contains('silver')) {
      glyph = '🥈';
      baseColor = const Color(0xFF9CA3AF);
    } else {
      glyph = '✨';
      baseColor = const Color(0xFF6B7280);
    }

    final highlightColor = Color.lerp(baseColor, Colors.white, 0.4)!;

    return Shimmer.fromColors(
      baseColor: baseColor,
      highlightColor: highlightColor,
      period: const Duration(milliseconds: 1500),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 1),
            child: Text(glyph, style: TextStyle(fontSize: 11, color: baseColor)),
          ),
          const SizedBox(width: 2),
          Flexible(
            child: Text(
              badgeText,
              style: TextStyle(
                fontSize: 11,
                color: baseColor,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ─── Delivery badge – now uses delivery_label / free_delivery if available, one line ─────
  Widget? _buildDeliveryBadgeRaw() {
    final product = widget.product;
    String text = '';
    Color textColor = Colors.black;

    // 1. New unified fields from package API
    if (product.deliveryLabel != null &&
        product.deliveryLabel!.isNotEmpty &&
        product.deliveryLabel!.toLowerCase() != 'paid delivery' &&
        product.deliveryLabel!.toLowerCase() != 'paid shipping') {
      text = product.deliveryLabel!;
      textColor = (product.freeDelivery == true) ? Colors.black : AppColors.error;
    }
    // 2. Fallback to old product fields
    else if (product.freeShipping ||
        (product.sellerPaysShipping && product.shippingSubsidyType == 'full')) {
      text = 'Free Delivery';
    } else if (product.sellerPaysShipping &&
        product.shippingSubsidyType == 'percentage' &&
        product.shippingSubsidyValue != null) {
      final discount = product.shippingSubsidyValue!.round();
      text = '$discount% off Delivery';
      textColor = AppColors.error;
    }

    if (text.isEmpty) return null;

    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Icon(Icons.local_shipping, size: 11, color: textColor),
        const SizedBox(width: 2),
        Flexible(
          child: Text(
            text,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            softWrap: false,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: textColor,
            ),
          ),
        ),
      ],
    );
  }

  String? _lowStockWarning() {
    final stock = widget.product.stock;
    if (stock != null && stock > 0 && stock <= 5) {
      return 'only $stock left';
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final textTheme = Theme.of(context).textTheme;
    final discount = widget.product.discountPercentage;
    final imageCount = _allImages.length;
    final displayPrice = FormatUtils.price(widget.product.effectivePrice);
    final itemCount = widget.itemCount;
    final lowStockMsg = _lowStockWarning();
    final bool showBadge = widget.showPackageBadge;

    final membershipBadge = _buildMembershipBadge();
    final deliveryBadge = _buildDeliveryBadgeRaw();

    // ★ Interchanging switcher – exactly like ProductCard’s _WholesaleInfoSwitcher
    Widget? interchangingBadge;
    if (membershipBadge != null && deliveryBadge != null) {
      interchangingBadge = _BadgeDeliverySwitcher(
        key: ValueKey(widget.product.id),
        membershipBadge: membershipBadge,
        deliveryBadge: deliveryBadge,
        productId: widget.product.id,
      );
    } else if (membershipBadge != null) {
      interchangingBadge = membershipBadge;
    } else if (deliveryBadge != null) {
      interchangingBadge = deliveryBadge;
    }

    // Rating section – orange stars, black text
    Widget ratingSection;
    if (widget.product.rating > 0 || widget.product.reviewsCount > 0) {
      ratingSection = Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          ...List.generate(5, (index) {
            final starValue = index + 1;
            final rating = widget.product.rating;
            IconData icon;
            if (starValue <= rating.floor()) {
              icon = Icons.star_rounded;
            } else if (starValue - 0.5 <= rating) {
              icon = Icons.star_half_rounded;
            } else {
              icon = Icons.star_outline_rounded;
            }
            return Icon(icon, size: 14, color: Colors.orange);
          }),
          const SizedBox(width: 2),
          Text('(${widget.product.reviewsCount})',
              style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: Colors.black)),
        ],
      );
    } else {
      ratingSection = const Text('Not rated yet',
          style: TextStyle(
              fontSize: 12,
              fontStyle: FontStyle.italic,
              color: Colors.black));
    }

    return Stack(
      children: [
        Container(
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
                    top: Radius.circular(AppShapes.radiusSm)),
                child: AspectRatio(
                  aspectRatio: 0.9,
                  child: Stack(
                    children: [
                      AnimatedSwitcher(
                        duration: const Duration(milliseconds: 400),
                        switchInCurve: Curves.easeInOut,
                        switchOutCurve: Curves.easeInOut,
                        child: CachedNetworkImage(
                          key: ValueKey('${widget.product.id}_$_currentImageIndex'),
                          imageUrl: _allImages[_currentImageIndex],
                          fit: BoxFit.cover,
                          width: double.infinity,
                          height: double.infinity,
                          placeholder: (_, __) =>
                              Container(color: Colors.grey.shade100),
                          errorWidget: (_, __, ___) => Container(
                            color: Colors.grey.shade100,
                            child: const Icon(Icons.image_not_supported,
                                size: 28, color: Colors.grey),
                          ),
                        ),
                      ),
                      if (discount > 0)
                        Positioned(
                          top: 6,
                          left: 6,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: AppColors.error,
                              borderRadius:
                                  BorderRadius.circular(AppShapes.radiusSm),
                            ),
                            child: Text(
                              l10n.translate('discount_percent_label')
                                  .replaceAll('{discount}', discount.toString()),
                              style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 10,
                                  fontWeight: FontWeight.w700),
                            ),
                          ),
                        ),
                      if (imageCount > 1)
                        Positioned(
                          bottom: 6,
                          left: 0,
                          right: 0,
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: List.generate(imageCount, (index) {
                              return GestureDetector(
                                onTap: () =>
                                    setState(() => _currentImageIndex = index),
                                child: AnimatedContainer(
                                  duration: const Duration(milliseconds: 200),
                                  width: _currentImageIndex == index ? 8 : 6,
                                  height: _currentImageIndex == index ? 8 : 6,
                                  margin:
                                      const EdgeInsets.symmetric(horizontal: 3),
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: _currentImageIndex == index
                                        ? AppColors.primary
                                        : Colors.white.withOpacity(0.7),
                                    border: Border.all(
                                      color: _currentImageIndex == index
                                          ? AppColors.primary
                                          : Colors.white.withOpacity(0.4),
                                      width: 1,
                                    ),
                                  ),
                                ),
                              );
                            }),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              // Text pad
              Padding(
                padding: const EdgeInsets.fromLTRB(5, 1, 5, 2),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Vendor name row (now empty if no vendor name and no badge)
                    if (widget.product.vendorBusinessName != null ||
                        interchangingBadge != null)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 2),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (widget.product.vendorBusinessName != null)
                              Flexible(
                                child: Text(
                                  widget.product.vendorBusinessName!,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w600,
                                      color: Colors.black),
                                ),
                              ),
                            if (widget.product.vendorBusinessName != null &&
                                interchangingBadge != null)
                              const SizedBox(width: 4),
                            if (interchangingBadge != null)
                              Flexible(child: interchangingBadge),
                          ],
                        ),
                      ),
                    // Price
                    Text(
                      displayPrice,
                      style: textTheme.titleMedium?.copyWith(
                        fontSize: (textTheme.titleMedium?.fontSize ?? 14) + 1,
                        fontWeight: FontWeight.w700,
                        color: Colors.black,
                      ),
                    ),
                    // Title + gift badge
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (showBadge)
                          const Padding(
                            padding: EdgeInsets.only(right: 4, top: 2),
                            child: Text('🎁', style: TextStyle(fontSize: 14)),
                          ),
                        Expanded(
                          child: Text(
                            widget.product.title,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: textTheme.headlineMedium?.copyWith(
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                              color: Colors.black,
                            ),
                          ),
                        ),
                      ],
                    ),
                    // Rating + low stock
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        ratingSection,
                        if (lowStockMsg != null) ...[
                          const SizedBox(width: 8),
                          Text(lowStockMsg,
                              style: const TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  color: AppColors.error)),
                        ],
                      ],
                    ),
                    if (itemCount != null && itemCount > 0)
                      Text('$itemCount items included in this package',
                          style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: Colors.black)),
                  ],
                ),
              ),
            ],
          ),
        ),
        // ★ Overlay when package is out of stock
        if (widget.product.outOfStock == true)
          Positioned.fill(
            child: Container(
              color: Colors.white70,
              alignment: Alignment.center,
              child: Padding(
                padding: const EdgeInsets.all(12.0),
                child: Text(
                  'Out of stock',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: AppColors.error,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    backgroundColor: Colors.white,
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

// ─── Switcher widget (exactly like _WholesaleInfoSwitcher from ProductCard) ─────
class _BadgeDeliverySwitcher extends StatefulWidget {
  final Widget membershipBadge;
  final Widget deliveryBadge;
  final int productId;

  const _BadgeDeliverySwitcher({
    Key? key,
    required this.membershipBadge,
    required this.deliveryBadge,
    required this.productId,
  }) : super(key: key);

  @override
  State<_BadgeDeliverySwitcher> createState() => _BadgeDeliverySwitcherState();
}

class _BadgeDeliverySwitcherState extends State<_BadgeDeliverySwitcher> {
  late Timer _timer;
  bool _showMembership = true;
  late int _intervalSeconds;

  @override
  void initState() {
    super.initState();
    final seededRandom = Random(widget.productId);
    _intervalSeconds = 4 + seededRandom.nextInt(5); // 4–8 seconds
    _showMembership = seededRandom.nextBool();       // random initial badge
    _timer = Timer.periodic(Duration(seconds: _intervalSeconds), (_) {
      if (mounted) setState(() => _showMembership = !_showMembership);
    });
  }

  @override
  void dispose() {
    _timer.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return _showMembership ? widget.membershipBadge : widget.deliveryBadge;
  }
}
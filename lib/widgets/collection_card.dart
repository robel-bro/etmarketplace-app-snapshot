import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../theme/app_theme.dart';

// ---------- Data Models ----------
class CategoryItem {
  final String name;
  final String? image;
  final int? count;
  final String path;
  const CategoryItem({required this.name, this.image, this.count, required this.path});
}

class VariantItem {
  final double price;
  final int stock;
  final Map<String, String> attributes;
  const VariantItem({required this.price, required this.stock, required this.attributes});
}

class ProductPreview {
  final int id;
  final String? title;
  final List<String>? imageUrls;
  final String? image;
  final double? price;
  final double? effectivePrice;
  final double? originalPrice;
  final int? discount;
  final double? rating;
  final bool freeShipping;
  final bool isFlashSale;
  final bool isSuperDeal;
  final List<VariantItem>? variants;

  const ProductPreview({
    required this.id,
    this.title,
    this.imageUrls,
    this.image,
    this.price,
    this.effectivePrice,
    this.originalPrice,
    this.discount,
    this.rating,
    this.freeShipping = false,
    this.isFlashSale = false,
    this.isSuperDeal = false,
    this.variants,
  });

  String get displayImage =>
      (imageUrls != null && imageUrls!.isNotEmpty)
          ? imageUrls!.first
          : (image ?? 'https://placehold.co/80x80?text=No+Image');

  String get displayPriceFormatted {
    if (variants != null && variants!.isNotEmpty) {
      final min = variants!.map((v) => v.price).reduce((a, b) => a < b ? a : b);
      return 'From ETB ${_formatPrice(min)}';
    }
    final p = (price ?? effectivePrice) ?? 0;
    return 'ETB ${_formatPrice(p)}';
  }
}

class Collection {
  final int id;
  final String? slug;
  final String name;
  final String? description;
  final String? label;
  final String? coverImageUrl;
  final int productCount;
  final List<CategoryItem> categories;
  final List<ProductPreview> showcaseProducts;
  final List<ProductPreview> products;

  const Collection({
    required this.id,
    this.slug,
    required this.name,
    this.description,
    this.label,
    this.coverImageUrl,
    this.productCount = 0,
    this.categories = const [],
    this.showcaseProducts = const [],
    this.products = const [],
  });
}

// ---------- Number formatting ----------
String _formatPrice(double value) {
  if (value <= 0) return '0';
  final intPart = value.toInt().toString();
  return intPart.replaceAllMapped(
    RegExp(r'\B(?=(\d{3})+(?!\d))'),
    (match) => ',',
  );
}

// ---------- Helper widgets ----------
class _Badge extends StatelessWidget {
  final String text;
  final Color bg;
  final Color fg;
  const _Badge(this.text, this.bg, this.fg);

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(top: 4),
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
      color: bg,
      child: Text(
        text,
        style: TextStyle(fontSize: 9, fontWeight: FontWeight.w700, color: fg),
      ),
    );
  }
}

class _StatItem extends StatelessWidget {
  final Widget icon;
  final String label;
  const _StatItem({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        icon,
        const SizedBox(width: 6),
        Text(
          label,
          style: const TextStyle(fontSize: 12, color: Colors.white),
        ),
      ],
    );
  }
}

// ---------- Product row (tighter vertical padding) ----------
class _ProductRow extends StatelessWidget {
  final ProductPreview product;
  final VoidCallback? onTap;
  const _ProductRow({required this.product, this.onTap});

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final oldPrice = product.originalPrice ?? 0;
    final hasDiscount = oldPrice > 0 && oldPrice > ((product.price ?? product.effectivePrice) ?? 0);
    final discount = product.discount ??
        (hasDiscount ? ((oldPrice - ((product.price ?? product.effectivePrice) ?? 0)) / oldPrice * 100).round() : null);

    return InkWell(
      onTap: onTap,
      child: Container(
        // Reduced vertical padding
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: AppColors.cardBackground,
          border: Border.all(color: Colors.grey.shade300, width: 1),
        ),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.zero,
              child: Image.network(
                product.displayImage,
                width: 64,
                height: 64,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => Container(
                  width: 64,
                  height: 64,
                  color: const Color(0xFFF9FAFB),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    product.title ?? 'Product',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: textTheme.headlineMedium?.copyWith(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    product.displayPriceFormatted,
                    style: textTheme.titleMedium?.copyWith(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  if (hasDiscount) ...[
                    const SizedBox(width: 6),
                    Text(
                      'ETB ${_formatPrice(oldPrice)}',
                      style: textTheme.bodySmall?.copyWith(
                        fontSize: 12,
                        color: AppColors.textMuted,
                        decoration: TextDecoration.lineThrough,
                      ),
                    ),
                  ],
                  if (product.isFlashSale)
                    _Badge('FLASH', const Color(0xFFFEE2E2), const Color(0xFFB91C1C)),
                  if (product.isSuperDeal)
                    _Badge('SUPER DEAL', const Color(0xFFFFEDD5), const Color(0xFFC2410C)),
                  if (discount != null && !product.isFlashSale && !product.isSuperDeal)
                    _Badge('-$discount%', const Color(0xFFDCFCE7), const Color(0xFF15803D)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------- Main Card ----------
class CollectionCard extends StatelessWidget {
  final Collection collection;
  final VoidCallback? onExplore;
  final void Function(ProductPreview product)? onProductTap;
  final void Function(CategoryItem category)? onCategoryTap;

  const CollectionCard({
    Key? key,
    required this.collection,
    this.onExplore,
    this.onProductTap,
    this.onCategoryTap,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final heroImg = collection.coverImageUrl ??
        'https://images.unsplash.com/photo-1556905055-8f358a7a47b2?w=1200&q=80';
    final hasCategories = collection.categories.isNotEmpty;
    final showcase = collection.showcaseProducts.isNotEmpty
        ? collection.showcaseProducts
        : collection.products.take(4).toList();
    final hasShowcase = showcase.isNotEmpty;

    // Stats calculation
    double totalValue = 0;
    double savings = 0;
    bool hasFreeShipping = false;
    String? avgRating;
    if (showcase.isNotEmpty) {
      for (final p in showcase) {
        final price = (p.price ?? p.effectivePrice) ?? 0;
        final old = p.originalPrice ?? 0;
        if (price > 0) totalValue += price;
        if (old > price) savings += (old - price);
        if (p.freeShipping) hasFreeShipping = true;
      }
      final totalRating = showcase
          .map((p) => p.rating ?? 0)
          .fold(0.0, (sum, r) => sum + r);
      avgRating = (totalRating / showcase.length).toStringAsFixed(1);
    }

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: AppColors.cardBackground,
        // ★ Removed black border
        borderRadius: BorderRadius.circular(AppShapes.radiusSm),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Hero section (slightly tighter bottom padding)
          SizedBox(
            height: 200,
            child: Stack(
              fit: StackFit.expand,
              children: [
                CachedNetworkImage(
                  imageUrl: heroImg,
                  fit: BoxFit.cover,
                  placeholder: (_, __) => Container(color: const Color(0xFFE5E7EB)),
                  errorWidget: (_, __, ___) => Container(color: const Color(0xFFE5E7EB)),
                ),
                const DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.bottomCenter,
                      end: Alignment.topCenter,
                      colors: [
                        Color(0x80000000),
                        Color(0x40000000),
                        Colors.transparent,
                      ],
                    ),
                  ),
                ),
                Positioned(
                  bottom: 0,
                  left: 0,
                  right: 0,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),  // reduced bottom
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (collection.label != null)
                          Text(
                            collection.label!.toUpperCase(),
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w800,
                              color: Colors.white,
                              letterSpacing: 1,
                            ),
                          ),
                        const SizedBox(height: 4),
                        Text(
                          collection.name,
                          style: const TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.w800,
                            color: Colors.white,
                            height: 1.2,
                          ),
                        ),
                        if (collection.description != null) ...[
                          const SizedBox(height: 4),
                          Text(
                            collection.description!,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 13,
                              color: Colors.white,
                              height: 1.4,
                            ),
                          ),
                        ],
                        const SizedBox(height: 8),  // reduced
                        Wrap(
                          spacing: 12,
                          runSpacing: 8,
                          children: [
                            if (collection.productCount > 0)
                              _StatItem(
                                icon: const Icon(Icons.inventory_2_outlined, size: 16, color: Colors.white),
                                label: '${collection.productCount}+ Products',
                              ),
                            if (totalValue > 0)
                              _StatItem(
                                icon: const Icon(Icons.local_offer_outlined, size: 16, color: Colors.white),
                                label: 'Total ETB ${_formatPrice(totalValue)}',
                              ),
                            if (savings > 0)
                              _StatItem(
                                icon: const Icon(Icons.local_offer_outlined, size: 16, color: Colors.white),
                                label: 'Save ETB ${_formatPrice(savings)}',
                              ),
                            if (hasFreeShipping)
                              _StatItem(
                                icon: const Icon(Icons.local_shipping_outlined, size: 16, color: Colors.white),
                                label: 'Free Shipping',
                              ),
                            if (avgRating != null)
                              _StatItem(
                                icon: const Icon(Icons.star, size: 16, color: Colors.amber),
                                label: '$avgRating rating',
                              ),
                          ],
                        ),
                        const SizedBox(height: 10),  // reduced
                        SizedBox(
                          height: 32,
                          child: ElevatedButton(
                            onPressed: onExplore ?? () {},
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppColors.primary,
                              foregroundColor: AppColors.white,
                              padding: const EdgeInsets.symmetric(horizontal: 12),
                              textStyle: AppTextStyles.buttonLabel.copyWith(fontSize: 12, fontWeight: FontWeight.w500),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.zero),
                              elevation: 0,
                            ),
                            child: const Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text('Explore Collection'),
                                SizedBox(width: 4),
                                Icon(Icons.arrow_forward, size: 14),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          // ★ “Top Picks” section with gray background and reduced padding
          if (hasShowcase)
            Container(
              color: Colors.grey.shade100,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8), // denser
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        hasCategories ? 'Categories' : '🔥 Top Picks',
                        style: textTheme.displayLarge?.copyWith(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: AppColors.textPrimary,
                        ) ?? const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: AppColors.textPrimary),
                      ),
                      if (!hasCategories)
                        GestureDetector(
                          onTap: onExplore,
                          child: Text(
                            'View All',
                            style: textTheme.bodySmall?.copyWith(
                              color: AppColors.primary,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 4),  // reduced
                  ...showcase.map(
                    (prod) => Padding(
                      padding: const EdgeInsets.only(bottom: 4), // tighter
                      child: _ProductRow(
                        product: prod,
                        onTap: onProductTap != null
                            ? () => onProductTap!(prod)
                            : null,
                      ),
                    ),
                  ),
                  if (!hasCategories && collection.products.length > 4)
                    Align(
                      alignment: Alignment.centerRight,
                      child: GestureDetector(
                        onTap: onExplore,
                        child: Text(
                          'View All',
                          style: textTheme.bodySmall?.copyWith(
                            color: AppColors.primary,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
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
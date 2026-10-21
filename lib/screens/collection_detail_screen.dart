// 📁 lib/screens/collection_detail_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_staggered_grid_view/flutter_staggered_grid_view.dart';
import '../api/client.dart';
import '../models/product.dart';
import '../widgets/product_card.dart';
import '../widgets/bottom_nav_bar.dart';
import '../providers/tab_provider.dart';
import '../theme/app_theme.dart';

class CollectionDetailScreen extends ConsumerStatefulWidget {
  final String slug;
  const CollectionDetailScreen({Key? key, required this.slug}) : super(key: key);
  @override
  ConsumerState<CollectionDetailScreen> createState() => _CollectionDetailScreenState();
}

class _CollectionDetailScreenState extends ConsumerState<CollectionDetailScreen> {
  Map<String, dynamic>? _collection;
  List<Product> _products = [];
  bool _isLoading = true;

  final ScrollController _scrollController = ScrollController();

  double _headerTitleOpacity = 0.0;
  double _itemCountOpacity = 0.0;

  static const double _expandedHeight = 200.0;
  static const double _toolbarHeight = 56.0;

  @override
  void initState() {
    super.initState();
    _fetchCollection();
    _scrollController.addListener(_updateOpacity);
  }

  void _updateOpacity() {
    final offset = _scrollController.offset;
    final maxCollapseOffset = _expandedHeight - _toolbarHeight;

    const startFadeInFraction = 0.7;
    final startFadeInOffset = maxCollapseOffset * startFadeInFraction;
    final fadeInDistance = maxCollapseOffset - startFadeInOffset;

    double newTitleOpacity = 0.0;
    if (offset > startFadeInOffset && fadeInDistance > 0) {
      newTitleOpacity = ((offset - startFadeInOffset) / fadeInDistance).clamp(0.0, 1.0);
    }

    if (mounted && (_headerTitleOpacity - newTitleOpacity).abs() > 0.01) {
      setState(() {
        _headerTitleOpacity = newTitleOpacity;
        _itemCountOpacity = newTitleOpacity;
      });
    }
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _fetchCollection() async {
    try {
      final res = await ApiClient.instance.get('/api/v1/collections/${widget.slug}');
      final data = res.data;
      setState(() {
        _collection = data;
        _products = (data['products'] as List?)?.map((p) => Product.fromJson(p)).toList() ?? [];
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    if (_isLoading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator(color: AppColors.primary)),
      );
    }
    if (_collection == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Collection')),
        body: const Center(
          child: Text('Collection not found', style: TextStyle(color: AppColors.textMuted)),
        ),
        bottomNavigationBar: _bottomNav(),
      );
    }

    final coverUrl = _collection!['cover_image_url'] ?? '';
    final name = _collection!['name'] ?? '';
    final description = _collection!['description'] ?? '';
    final itemCount = _products.length;

    return Scaffold(
      backgroundColor: AppColors.pageBackground,
      body: CustomScrollView(
        controller: _scrollController,
        slivers: [
          SliverAppBar(
            expandedHeight: _expandedHeight,
            pinned: true,
            backgroundColor: AppColors.cardBackground,
            surfaceTintColor: AppColors.cardBackground,
            elevation: 0,
            leading: _AdaptiveBackButton(
              onTap: () => Navigator.pop(context),
              headerTitleOpacity: _headerTitleOpacity,
            ),
            title: Opacity(
              opacity: _headerTitleOpacity,
              child: Text(
                name,
                overflow: TextOverflow.ellipsis,
                style: textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary,
                ),
              ),
            ),
            actions: [
              Opacity(
                opacity: _itemCountOpacity,
                child: Padding(
                  padding: const EdgeInsets.only(right: AppSpacing.md),
                  child: Text(
                    '$itemCount item${itemCount == 1 ? '' : 's'}',
                    style: const TextStyle(
                      color: AppColors.error,
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                    ),
                  ),
                ),
              ),
            ],
            flexibleSpace: FlexibleSpaceBar(
              background: Stack(
                fit: StackFit.expand,
                children: [
                  Image.network(
                    coverUrl,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => Container(color: Colors.grey.shade300),
                  ),
                  Container(color: Colors.black.withOpacity(0.35)),
                  Positioned(
                    bottom: 24,
                    left: AppSpacing.md,
                    right: AppSpacing.md,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          name,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 24,
                            fontWeight: FontWeight.w700,
                            letterSpacing: -0.3,
                          ),
                        ),
                        if (description.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: Text(
                              description,
                              style: TextStyle(
                                color: Colors.white.withOpacity(0.9),
                                fontSize: 14,
                                height: 1.3,
                              ),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          // Product grid – tight masonry, grey background everywhere
          SliverToBoxAdapter(
            child: Container(
              color: AppColors.productListBackground,
              child: _products.isEmpty
                  ? const Padding(
                      padding: EdgeInsets.all(32),
                      child: Center(
                        child: Text(
                          'No products in this collection',
                          style: TextStyle(color: AppColors.textMuted, fontSize: 15),
                        ),
                      ),
                    )
                  : MasonryGridView.count(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      crossAxisCount: 2,
                      mainAxisSpacing: 4,
                      crossAxisSpacing: 4,
                      padding: const EdgeInsets.fromLTRB(
                        AppSpacing.xs,
                        AppSpacing.xs,
                        AppSpacing.xs,
                        0,
                      ),
                      itemCount: _products.length,
                      itemBuilder: (ctx, index) {
                        final product = _products[index];
                        return GestureDetector(
                          onTap: () => Navigator.pushNamed(context, '/product', arguments: product.id),
                          child: ProductCard(product: product, isDeal: false),
                        );
                      },
                    ),
            ),
          ),
          // This sliver fills the remaining space with the grey background, so there's never a white gap.
          SliverFillRemaining(
            hasScrollBody: false,
            child: Container(color: AppColors.productListBackground),
          ),
        ],
      ),
      bottomNavigationBar: _bottomNav(),
    );
  }

  Widget _bottomNav() {
    return BottomNavBar(
      selectedIndex: 0,
      onTap: (index) {
        Navigator.of(context).popUntil(ModalRoute.withName('/main'));
        ref.read(tabProvider.notifier).state = index;
      },
    );
  }
}

/// Adaptive back button – transparent circle on the image, clean dark icon on white.
class _AdaptiveBackButton extends StatelessWidget {
  final VoidCallback onTap;
  final double headerTitleOpacity;
  const _AdaptiveBackButton({
    required this.onTap,
    required this.headerTitleOpacity,
  });

  @override
  Widget build(BuildContext context) {
    final isWhiteBackground = headerTitleOpacity > 0.5;

    return Padding(
      padding: const EdgeInsets.only(left: AppSpacing.xs, top: AppSpacing.xs),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(20),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            width: 36,
            height: 36,
            decoration: isWhiteBackground
                ? const BoxDecoration(
                    color: Colors.transparent,
                    shape: BoxShape.circle,
                  )
                : BoxDecoration(
                    color: Colors.black.withOpacity(0.2),
                    shape: BoxShape.circle,
                  ),
            child: Icon(
              Icons.arrow_back_ios_new_rounded,
              color: isWhiteBackground ? AppColors.textPrimary : Colors.white,
              size: 18,
            ),
          ),
        ),
      ),
    );
  }
}
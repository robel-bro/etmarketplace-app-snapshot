import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../api/client.dart';
import '../widgets/collection_card.dart';
import '../widgets/search_bar.dart';
import '../widgets/notification_bell.dart';
import '../widgets/quick_links_bar.dart';
import '../providers/tab_provider.dart';
import '../widgets/bottom_nav_bar.dart';
import '../theme/app_theme.dart';
import '../l10n/app_localizations.dart';
import 'collection_detail_screen.dart';

class CollectionsScreen extends ConsumerStatefulWidget {
  const CollectionsScreen({Key? key}) : super(key: key);

  @override
  ConsumerState<CollectionsScreen> createState() => _CollectionsScreenState();
}

class _CollectionsScreenState extends ConsumerState<CollectionsScreen> {
  List<Map<String, dynamic>> _collectionsRaw = [];
  bool _isLoading = true;

  late List<Map<String, dynamic>> _quickLinks;
  String _selectedQuickLink = '';

  @override
  void initState() {
    super.initState();
    _fetchCollections();
  }

  Future<void> _fetchCollections() async {
    try {
      final res = await ApiClient.instance.get('/api/v1/collections');
      final data = res.data is List ? res.data : (res.data['data'] ?? []);
      final List<Map<String, dynamic>> rawList = (data as List)
          .whereType<Map<String, dynamic>>()
          .toList();
      setState(() {
        _collectionsRaw = rawList;
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
    }
  }

  void _onQuickLinkTap(Map<String, dynamic> link) {
    final route = link['route'] as String;
    setState(() => _selectedQuickLink = link['name']);
    if (route.isEmpty || route == '/home') {
      Navigator.of(context).pushNamedAndRemoveUntil('/main', (route) => false);
    } else {
      Navigator.pushNamed(context, route);
    }
  }

  double? _parseDouble(dynamic value) {
    if (value == null) return null;
    if (value is double) return value;
    if (value is int) return value.toDouble();
    return double.tryParse(value.toString());
  }

  Collection _mapToCollection(Map<String, dynamic> raw) {
    final showcaseRaw = raw['showcase_products'] as List<dynamic>? ?? [];
    final allProductsRaw = raw['products'] as List<dynamic>? ?? [];
    final productCount = raw['product_count'] ?? allProductsRaw.length;

    List<ProductPreview> parseProductList(List<dynamic> list) =>
        list.map((p) {
          final map = Map<String, dynamic>.from(p);
          return ProductPreview(
            id: map['id'] ?? 0,
            title: map['title'],
            imageUrls: (map['image_urls'] as List<dynamic>?)?.cast<String>(),
            image: map['image'],
            price: _parseDouble(map['price']),
            effectivePrice: _parseDouble(map['effective_price']),
            originalPrice: _parseDouble(map['original_price']),
            discount: map['discount'] is int
                ? map['discount']
                : int.tryParse(map['discount']?.toString() ?? ''),
            rating: _parseDouble(map['rating']),
            freeShipping: map['free_shipping'] == true,
            isFlashSale: map['is_flash_sale'] == true,
            isSuperDeal: map['is_super_deal'] == true,
          );
        }).toList();

    return Collection(
      id: raw['id'] ?? 0,
      slug: raw['slug'],
      name: raw['name'] ?? 'Collection',
      description: raw['description'],
      label: raw['label'],
      coverImageUrl: raw['cover_image_url'],
      productCount: productCount,
      categories: [],
      showcaseProducts: parseProductList(showcaseRaw),
      products: parseProductList(allProductsRaw),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    // ★ Updated quick links – Hot Deals replaces Flash & Super, localized
    _quickLinks = [
      {'name': l10n.translate('explore'),         'route': '/home'},
      {'name': l10n.translate('all_products'),    'route': '/all-products'},
      {'name': l10n.translate('new_arrivals'),    'route': '/new-arrivals'},
      {'name': l10n.translate('best_sellers'),    'route': '/best-sellers'},
      {'name': l10n.translate('trending'),        'route': '/trending'},
      {'name': l10n.translate('hot_deals_title'), 'route': '/hot-deals'},
      {'name': l10n.translate('packages'),        'route': '/packages'},
      {'name': l10n.translate('collections'),     'route': '/collections'},
    ];
    if (_selectedQuickLink.isEmpty ||
        !_quickLinks.any((link) => link['name'] == _selectedQuickLink)) {
      _selectedQuickLink = l10n.translate('collections');
    }

    final bool showEmpty = !_isLoading && _collectionsRaw.isEmpty;

    return Scaffold(
      backgroundColor: AppColors.pageBackground,
      body: SafeArea(
        child: CustomScrollView(
          slivers: [
            // Search + notification bell (reduced padding)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.xs, 2, AppSpacing.xs, 2,
                ),
                child: Row(
                  children: [
                    Expanded(child: RotatingSearchBar()),
                    const SizedBox(width: 4),
                    const NotificationBell(),
                  ],
                ),
              ),
            ),

            // Quick links (pinned)
            SliverPersistentHeader(
              pinned: true,
              delegate: QuickLinksHeaderDelegate(
                links: _quickLinks,
                selected: _selectedQuickLink,
                onTap: _onQuickLinkTap,
              ),
            ),

            // Collection cards area
            if (!showEmpty)
              SliverToBoxAdapter(
                child: Container(
                  color: AppColors.productListBackground,
                  child: _isLoading
                      ? const Padding(
                          padding: EdgeInsets.all(32),
                          child: Center(
                            child: CircularProgressIndicator(color: AppColors.primary),
                          ),
                        )
                      : ListView.builder(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          itemCount: _collectionsRaw.length,
                          itemBuilder: (ctx, index) {
                            final raw = _collectionsRaw[index];
                            final collection = _mapToCollection(raw);
                            return CollectionCard(
                              collection: collection,
                              onExplore: () {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => CollectionDetailScreen(slug: collection.slug ?? ''),
                                  ),
                                );
                              },
                              onProductTap: (product) {
                                Navigator.pushNamed(context, '/product', arguments: product.id);
                              },
                            );
                          },
                        ),
                ),
              ),

            // Empty state
            if (showEmpty)
              SliverFillRemaining(
                hasScrollBody: false,
                child: Container(
                  color: AppColors.productListBackground,
                  child: Center(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 32),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 72,
                            height: 72,
                            decoration: const BoxDecoration(
                              color: AppColors.primary,
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(
                              Icons.auto_awesome_rounded,
                              color: Colors.white,
                              size: 36,
                            ),
                          ),
                          const SizedBox(height: 20),
                          Text(
                            l10n.translate('no_collections_yet'),
                            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.w600,
                                  color: AppColors.textPrimary,
                                ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            l10n.translate('collections_empty_msg'),
                            textAlign: TextAlign.center,
                            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                  color: AppColors.textMuted,
                                ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              )
            else
              SliverFillRemaining(
                hasScrollBody: false,
                child: Container(color: AppColors.productListBackground),
              ),
          ],
        ),
      ),
      bottomNavigationBar: BottomNavBar(
        selectedIndex: 0,
        onTap: (index) {
          Navigator.of(context).pushNamedAndRemoveUntil('/main', (route) => false);
          ref.read(tabProvider.notifier).state = index;
        },
      ),
    );
  }
}
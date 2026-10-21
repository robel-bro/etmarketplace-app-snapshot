// 📁 lib/screens/category_products_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_staggered_grid_view/flutter_staggered_grid_view.dart';
import 'package:url_launcher/url_launcher.dart';
import '../api/client.dart';
import '../models/category.dart';
import '../models/product.dart';
import '../theme/app_theme.dart';
import '../l10n/app_localizations.dart';
import '../widgets/product_card.dart';
import '../widgets/search_bar.dart';
import '../widgets/notification_bell.dart';
import 'product_detail_screen.dart';
import 'product_listing_screen.dart';
import 'search_screen.dart';

class CategoryProductsScreen extends ConsumerStatefulWidget {
  final int? initialCategoryId;
  final String? categoryName;
  const CategoryProductsScreen({
    Key? key,
    this.initialCategoryId,
    this.categoryName,
  }) : super(key: key);

  @override
  ConsumerState<CategoryProductsScreen> createState() =>
      _CategoryProductsScreenState();
}

class _CategoryProductsScreenState
    extends ConsumerState<CategoryProductsScreen> {
  List<Category> _mainCategories = [];
  int? _selectedCategoryId;
  List<Product> _categoryProducts = [];
  bool _isLoadingCategories = true;
  bool _isLoadingProducts = false;

  // Announcement data
  Map<String, dynamic>? _announcement;
  bool _dismissedAnnouncement = false;

  @override
  void initState() {
    super.initState();
    _selectedCategoryId = widget.initialCategoryId;
    _loadCategoriesAndProducts();
    _fetchAnnouncement();
  }

  Future<void> _fetchAnnouncement() async {
    try {
      final res = await ApiClient.instance.get('/api/v1/announcements');
      final list = res.data as List;
      if (list.isNotEmpty && mounted) {
        setState(() => _announcement = Map<String, dynamic>.from(list.first));
      }
    } catch (_) {}
  }

  Future<void> _loadCategoriesAndProducts() async {
    setState(() => _isLoadingCategories = true);
    try {
      final response = await ApiClient.instance.get('/categories');
      final List rawList = response.data as List;
      final flatCategories = rawList.map((c) => Category.fromJson(c)).toList();
      _mainCategories = flatCategories.where((c) => c.parentId == null).map((c) {
        final children = _buildChildren(c.id, flatCategories);
        return Category(
          id: c.id,
          name: c.name,
          image: c.image,
          parentId: c.parentId,
          children: children,
        );
      }).toList();

      if (_selectedCategoryId == null && _mainCategories.isNotEmpty) {
        _selectedCategoryId = _mainCategories.first.id;
      }
      if (_selectedCategoryId != null) {
        await _loadProducts();
      }
    } catch (e) {} finally {
      if (mounted) setState(() => _isLoadingCategories = false);
    }
  }

  List<Category> _buildChildren(int parentId, List<Category> flat) {
    return flat.where((c) => c.parentId == parentId).map((c) {
      return Category(
        id: c.id,
        name: c.name,
        image: c.image,
        parentId: c.parentId,
        children: _buildChildren(c.id, flat),
      );
    }).toList();
  }

  Future<void> _loadProducts() async {
    if (_selectedCategoryId == null) return;
    setState(() => _isLoadingProducts = true);
    try {
      final response = await ApiClient.instance
          .get('/products?category=$_selectedCategoryId');
      final List data = response.data['data'] ?? response.data;
      if (mounted) {
        setState(() {
          _categoryProducts =
              data.map((json) => Product.fromJson(json)).toList();
          _isLoadingProducts = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _categoryProducts = [];
          _isLoadingProducts = false;
        });
      }
    }
  }

  void _onMainCategorySelected(Category cat) {
    if (cat.id == _selectedCategoryId) return;
    setState(() => _selectedCategoryId = cat.id);
    _loadProducts();
  }

  void _navigateToSubcategory(Category sub) {
    Navigator.of(context, rootNavigator: true).push(
      MaterialPageRoute(
        builder: (_) => ProductListingScreen(
          title: sub.name,
          apiEndpoint: '/products?category=${sub.id}',
          showSubcategoryRow: sub.children.isNotEmpty,
          subcategories: sub.children,
          mainCategoryId: sub.id,
          heroImageUrl: sub.image,
        ),
      ),
    );
  }

  void _navigateToSeeAll() {
    final cat = _mainCategories.firstWhere(
      (c) => c.id == _selectedCategoryId,
      orElse: () => _mainCategories.first,
    );
    Navigator.of(context, rootNavigator: true).push(
      MaterialPageRoute(
        builder: (_) => ProductListingScreen(
          title: cat.name,
          apiEndpoint: '/products?category=${cat.id}',
          showSubcategoryRow: false,
          subcategories: const [],
          mainCategoryId: cat.id,
          heroImageUrl: cat.image,
        ),
      ),
    );
  }

  // ★ Rich announcement dialog – same design as the floating icon
  void _showAnnouncementDetails() {
    if (_announcement == null) return;
    final title = _announcement!['title'] ?? '';
    final content = _announcement!['content'] ?? '';
    final link = _announcement!['link'] as String?;

    showDialog(
      context: context,
      builder: (ctx) => Center(
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24.0),
            child: Container(
              width: double.infinity,
              constraints: const BoxConstraints(maxWidth: 400),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(20),
                color: Colors.white,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.15),
                    blurRadius: 20,
                    offset: const Offset(0, 10),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Header with gradient
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 20),
                    decoration: const BoxDecoration(
                      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
                      gradient: LinearGradient(
                        colors: [Color(0xFFFF9800), Color(0xFFFFB74D)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                    ),
                    child: Column(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: Colors.white.withOpacity(0.2),
                          ),
                          child: const Icon(
                            Icons.campaign,
                            size: 32,
                            color: Colors.white,
                          ),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          title,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                            color: Colors.white,
                            letterSpacing: 0.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                  // Body
                  if (content.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
                      child: Text(
                        content,
                        style: const TextStyle(
                          fontSize: 15,
                          height: 1.5,
                          color: Colors.black87,
                        ),
                      ),
                    ),
                  // Actions
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        TextButton(
                          onPressed: () => Navigator.pop(ctx),
                          child: const Text(
                            'DISMISS',
                            style: TextStyle(color: Colors.grey, fontWeight: FontWeight.w600),
                          ),
                        ),
                        if (link != null && link.isNotEmpty) ...[
                          const SizedBox(width: 4),
                          ElevatedButton.icon(
                            onPressed: () async {
                              final uri = Uri.tryParse(link);
                              if (uri != null && await canLaunchUrl(uri)) {
                                await launchUrl(uri, mode: LaunchMode.externalApplication);
                              }
                              Navigator.pop(ctx);
                            },
                            icon: const Icon(Icons.open_in_new, size: 16),
                            label: const Text('OPEN'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.orange,
                              foregroundColor: Colors.white,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8),
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(height: 4),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final screenWidth = MediaQuery.of(context).size.width;
    final textTheme = Theme.of(context).textTheme;

    double sidebarWidth;
    if (screenWidth < 360) {
      sidebarWidth = 75;
    } else if (screenWidth < 400) {
      sidebarWidth = 85;
    } else if (screenWidth < 500) {
      sidebarWidth = 100;
    } else if (screenWidth < 700) {
      sidebarWidth = 120;
    } else {
      sidebarWidth = 140;
    }

    final catFontSize = sidebarWidth >= 120 ? 13.0 : (sidebarWidth >= 100 ? 12.0 : 11.0);
    final rightPanelWidth = screenWidth - sidebarWidth;

    int subCols;
    if (rightPanelWidth < 200) {
      subCols = 2;
    } else if (rightPanelWidth < 350) {
      subCols = 3;
    } else {
      subCols = 4;
    }

    if (_isLoadingCategories) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }
    if (_mainCategories.isEmpty) {
      return Scaffold(
        body: Center(
          child: Text(l10n.translate('no_categories_found'),
              style: const TextStyle(color: AppColors.textMuted)),
        ),
      );
    }

    final selectedCategory = _mainCategories.firstWhere(
      (c) => c.id == _selectedCategoryId,
      orElse: () => _mainCategories.first,
    );
    final subcategories = selectedCategory.children;

    return Scaffold(
      backgroundColor: AppColors.pageBackground,
      body: SafeArea(
        child: Column(
          children: [
            // Header – search bar + notification bell
            Padding(
              padding: const EdgeInsets.fromLTRB(AppSpacing.xs, 2, AppSpacing.xs, 2),
              child: Row(
                children: [
                  const Expanded(
                    child: SizedBox(
                      height: 40,
                      child: RotatingSearchBar(),
                    ),
                  ),
                  const SizedBox(width: 2),
                  const NotificationBell(),
                ],
              ),
            ),

            // ★ Tappable announcement banner – opens rich dialog
            if (_announcement != null && !_dismissedAnnouncement)
              GestureDetector(
                onTap: _showAnnouncementDetails,
                child: Container(
                  width: double.infinity,
                  height: 30,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFFFFF3E0), Color(0xFFFFE0B2)],
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.orange.withOpacity(0.1),
                        blurRadius: 4,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Row(
                    children: [
                      const Icon(Icons.campaign, color: Colors.orange, size: 16),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _announcement!['title'] ?? '',
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: Colors.black87,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const Icon(Icons.chevron_right, size: 18, color: Colors.orange),
                      const SizedBox(width: 8),
                      GestureDetector(
                        onTap: () => setState(() => _dismissedAnnouncement = true),
                        child: const Icon(Icons.close, size: 16, color: Colors.grey),
                      ),
                    ],
                  ),
                ),
              ),

            // Main content (sidebar + products)
            Expanded(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Left Sidebar
                  SizedBox(
                    width: sidebarWidth,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 2),
                      decoration: const BoxDecoration(
                        color: AppColors.productListBackground,
                        border: Border(
                          right: BorderSide(
                            color: AppColors.borderLight,
                            width: 1,
                          ),
                        ),
                      ),
                      child: ScrollConfiguration(
                        behavior: ScrollConfiguration.of(context).copyWith(
                          scrollbars: false,
                        ),
                        child: ListView.builder(
                          itemCount: _mainCategories.length,
                          itemBuilder: (context, index) {
                            final cat = _mainCategories[index];
                            final isSelected = cat.id == _selectedCategoryId;
                            return GestureDetector(
                              onTap: () => _onMainCategorySelected(cat),
                              child: Container(
                                padding: EdgeInsets.symmetric(
                                    vertical: sidebarWidth >= 120 ? 14 : 10,
                                    horizontal: 2),
                                margin: const EdgeInsets.symmetric(
                                    vertical: 2, horizontal: 4),
                                decoration: BoxDecoration(
                                  color: isSelected
                                      ? AppColors.primary.withOpacity(0.08)
                                      : Colors.transparent,
                                  borderRadius: BorderRadius.circular(AppShapes.radiusSm),
                                ),
                                child: Text(
                                  cat.name,
                                  style: TextStyle(
                                    fontSize: catFontSize,
                                    fontWeight: isSelected
                                        ? FontWeight.w600
                                        : FontWeight.w500,
                                    color: isSelected
                                        ? AppColors.primary
                                        : AppColors.textMuted,
                                    height: 1.2,
                                  ),
                                  textAlign: TextAlign.center,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                    ),
                  ),

                  // Right Content
                  Expanded(
                    child: Container(
                      color: AppColors.cardBackground,
                      child: CustomScrollView(
                        slivers: [
                          // Subcategories
                          if (subcategories.isNotEmpty)
                            SliverPadding(
                              padding: const EdgeInsets.fromLTRB(0, AppSpacing.sm, 0, AppSpacing.sm),
                              sliver: SliverGrid(
                                gridDelegate:
                                    SliverGridDelegateWithFixedCrossAxisCount(
                                  crossAxisCount: subCols,
                                  mainAxisSpacing: 4,
                                  crossAxisSpacing: 0,
                                  mainAxisExtent: 90,
                                ),
                                delegate: SliverChildBuilderDelegate(
                                  (context, index) {
                                    final sub = subcategories[index];
                                    return GestureDetector(
                                      onTap: () => _navigateToSubcategory(sub),
                                      child: Column(
                                        children: [
                                          Container(
                                            width: 58,
                                            height: 58,
                                            decoration: BoxDecoration(
                                              shape: BoxShape.circle,
                                              color: AppColors.hoverState,
                                              border: Border.all(
                                                color: AppColors.borderLight,
                                                width: 1,
                                              ),
                                              boxShadow: [
                                                BoxShadow(
                                                  color: Colors.black.withOpacity(0.04),
                                                  blurRadius: 4,
                                                  offset: const Offset(0, 2),
                                                ),
                                              ],
                                            ),
                                            child: sub.image != null && sub.image!.isNotEmpty
                                                ? ClipOval(
                                                    child: Image.network(
                                                      sub.image!,
                                                      fit: BoxFit.cover,
                                                      errorBuilder:
                                                          (_, __, ___) => const Icon(
                                                        Icons.category,
                                                        color: AppColors.primary,
                                                        size: 24,
                                                      ),
                                                    ),
                                                  )
                                                : const Icon(
                                                    Icons.category,
                                                    color: AppColors.primary,
                                                    size: 24,
                                                  ),
                                          ),
                                          const SizedBox(height: 6),
                                          Text(
                                            sub.name,
                                            style: textTheme.bodySmall?.copyWith(
                                              fontSize: 11,
                                              fontWeight: FontWeight.w500,
                                              color: AppColors.textPrimary,
                                            ),
                                            maxLines: 2,
                                            overflow: TextOverflow.ellipsis,
                                            textAlign: TextAlign.center,
                                          ),
                                        ],
                                      ),
                                    );
                                  },
                                  childCount: subcategories.length,
                                ),
                              ),
                            ),

                          // "Recommended for you" header
                          SliverToBoxAdapter(
                            child: Padding(
                              padding: const EdgeInsets.fromLTRB(0, AppSpacing.xs, 0, AppSpacing.xs),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(l10n.translate('recommended_for_you'),
                                      style: textTheme.titleSmall?.copyWith(
                                          fontWeight: FontWeight.w600,
                                          color: AppColors.textPrimary)),
                                  TextButton(
                                    onPressed: _navigateToSeeAll,
                                    style: TextButton.styleFrom(
                                      padding: EdgeInsets.zero,
                                      minimumSize: Size.zero,
                                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                    ),
                                    child: Text(l10n.translate('see_all'),
                                        style: const TextStyle(
                                            fontSize: 13,
                                            color: AppColors.primary)),
                                  ),
                                ],
                              ),
                            ),
                          ),

                          // Product grid
                          if (_isLoadingProducts)
                            const SliverToBoxAdapter(
                              child: SizedBox(
                                height: 200,
                                child: Center(
                                  child: CircularProgressIndicator(
                                      color: AppColors.primary),
                                ),
                              ),
                            )
                          else if (_categoryProducts.isEmpty)
                            SliverFillRemaining(
                              hasScrollBody: false,
                              child: Container(
                                color: AppColors.productListBackground,
                                child: Center(
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
                                          Icons.inventory_2_outlined,
                                          color: Colors.white,
                                          size: 36,
                                        ),
                                      ),
                                      const SizedBox(height: 16),
                                      Text(
                                        l10n.translate('no_products_found'),
                                        style: textTheme.titleSmall?.copyWith(
                                          color: AppColors.textPrimary,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            )
                          else
                            SliverToBoxAdapter(
                              child: Container(
                                color: AppColors.productListBackground,
                                child: MasonryGridView.count(
                                  shrinkWrap: true,
                                  physics: const NeverScrollableScrollPhysics(),
                                  crossAxisCount: 2,
                                  mainAxisSpacing: 4,
                                  crossAxisSpacing: 0,
                                  padding: const EdgeInsets.fromLTRB(0, AppSpacing.xs, 0, AppSpacing.xs),
                                  itemCount: _categoryProducts.length,
                                  itemBuilder: (ctx, index) {
                                    final product = _categoryProducts[index];
                                    return GestureDetector(
                                      onTap: () => Navigator.push(
                                        context,
                                        MaterialPageRoute(
                                            builder: (_) =>
                                                ProductDetailScreen(
                                                    productId: product.id)),
                                      ),
                                      child: ProductCard(
                                        product: product,
                                        isDeal: false,
                                        compact: true,
                                      ),
                                    );
                                  },
                                ),
                              ),
                            ),

                          if (!_isLoadingProducts && _categoryProducts.isNotEmpty)
                            SliverFillRemaining(
                              hasScrollBody: false,
                              child: Container(color: AppColors.productListBackground),
                            ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
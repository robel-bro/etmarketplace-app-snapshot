// 📁 lib/widgets/hero_banner.dart – text area limited to 4 lines total
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../theme/app_theme.dart';

class HeroBanner extends StatefulWidget {
  final List<Map<String, dynamic>> banners;
  final int selectedIndex;
  final ValueChanged<int> onPageChanged;
  final void Function(String link) onBannerTap;

  const HeroBanner({
    Key? key,
    required this.banners,
    required this.selectedIndex,
    required this.onPageChanged,
    required this.onBannerTap,
  }) : super(key: key);

  @override
  State<HeroBanner> createState() => _HeroBannerState();
}

class _HeroBannerState extends State<HeroBanner> {
  late PageController _pageController;
  Timer? _autoPlayTimer;

  @override
  void initState() {
    super.initState();
    _pageController = PageController(initialPage: widget.selectedIndex);
    _startAutoPlay();
  }

  @override
  void didUpdateWidget(covariant HeroBanner oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.selectedIndex != oldWidget.selectedIndex &&
        widget.selectedIndex != _pageController.page?.round()) {
      _pageController.animateToPage(
        widget.selectedIndex,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
    }
  }

  @override
  void dispose() {
    _autoPlayTimer?.cancel();
    _pageController.dispose();
    super.dispose();
  }

  void _startAutoPlay() {
    // ★ 20 seconds per banner
    _autoPlayTimer = Timer.periodic(const Duration(seconds: 20), (_) {
      if (!mounted || widget.banners.isEmpty) return;
      final nextPage = (_pageController.page?.round() ?? 0) + 1;
      if (nextPage >= widget.banners.length) {
        _pageController.animateToPage(0,
            duration: const Duration(milliseconds: 800), curve: Curves.easeInOut);
      } else {
        _pageController.nextPage(
            duration: const Duration(milliseconds: 800), curve: Curves.easeInOut);
      }
    });
  }

  void _onPageChanged(int index) {
    widget.onPageChanged(index);
  }

  void _onDotTapped(int index) {
    _pageController.animateToPage(
      index,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
    );
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    if (widget.banners.isEmpty) return const SizedBox.shrink();

    final currentBanner = widget.banners[widget.selectedIndex];
    final title = currentBanner['title']?.toString().trim() ?? '';
    final subtitle = currentBanner['subtitle']?.toString().trim() ?? '';
    final link = currentBanner['link']?.toString() ?? '';
    final hasText = title.isNotEmpty || subtitle.isNotEmpty;
    final hasLink = link.isNotEmpty;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // ─── Image carousel with button overlay ───
        Stack(
          children: [
            SizedBox(
              height: 170,
              child: PageView.builder(
                controller: _pageController,
                onPageChanged: _onPageChanged,
                itemCount: widget.banners.length,
                itemBuilder: (context, index) {
                  final banner = widget.banners[index];
                  final imgUrl = banner['image_url']?.toString() ?? '';
                  final link = banner['link']?.toString() ?? '';
                  return GestureDetector(
                    onTap: () {
                      if (link.isNotEmpty) widget.onBannerTap(link);
                    },
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs),
                      child: Container(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(16),
                          boxShadow: [
                            BoxShadow(
                              color: AppColors.black.withOpacity(0.06),
                              blurRadius: 10,
                              offset: const Offset(0, 3),
                            ),
                          ],
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(16),
                          child: CachedNetworkImage(
                            imageUrl: imgUrl,
                            fit: BoxFit.cover,
                            width: double.infinity,
                            placeholder: (_, __) =>
                                Container(color: Colors.grey.shade200),
                            errorWidget: (_, __, ___) =>
                                Container(
                                  color: Colors.grey.shade200,
                                  child: const Icon(Icons.broken_image, color: Colors.grey),
                                ),
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
            // Dot indicators (bottom center)
            if (widget.banners.length > 1)
              Positioned(
                bottom: 10,
                left: 0,
                right: 0,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: List.generate(widget.banners.length, (index) {
                    final isActive = index == widget.selectedIndex;
                    return GestureDetector(
                      onTap: () => _onDotTapped(index),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        margin: const EdgeInsets.symmetric(horizontal: 3),
                        width: isActive ? 18 : 7,
                        height: 7,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(4),
                          color: isActive
                              ? AppColors.primary
                              : AppColors.white.withOpacity(0.8),
                        ),
                      ),
                    );
                  }),
                ),
              ),
            // Rectangular compact "Shop Now" button – bottom‑left
            if (hasLink)
              Positioned(
                bottom: 12,
                left: 16,
                child: GestureDetector(
                  onTap: () => widget.onBannerTap(link),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 5,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.primary,
                      borderRadius: BorderRadius.circular(4),
                      boxShadow: [
                        BoxShadow(
                          color: AppColors.black.withOpacity(0.2),
                          blurRadius: 4,
                          offset: const Offset(0, 1),
                        ),
                      ],
                    ),
                    child: Text(
                      'Shop Now',
                      style: textTheme.labelLarge?.copyWith(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),

        // ─── Text area – maximum 4 lines total ───
        if (hasText) ...[
          const SizedBox(height: AppSpacing.xs),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (title.isNotEmpty)
                  Text(
                    title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                      height: 1.2,
                      fontSize: 15,
                    ),
                  ),
                if (subtitle.isNotEmpty) ...[
                  if (title.isNotEmpty) const SizedBox(height: 4),
                  Text(
                    subtitle,
                    maxLines: title.isNotEmpty ? 2 : 4,
                    overflow: TextOverflow.ellipsis,
                    style: textTheme.bodySmall?.copyWith(
                      fontWeight: FontWeight.w500,
                      height: 1.3,
                      fontSize: 12,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ],
    );
  }
}
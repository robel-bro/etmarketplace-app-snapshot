// 📁 lib/widgets/quick_links_bar.dart
import 'package:flutter/material.dart';
import '../theme/app_theme.dart';   // central design tokens

class QuickLinksBar extends StatefulWidget {
  final List<Map<String, dynamic>> links;
  final String selected;
  final ValueChanged<Map<String, dynamic>> onTap;

  const QuickLinksBar({
    Key? key,
    required this.links,
    required this.selected,
    required this.onTap,
  }) : super(key: key);

  @override
  State<QuickLinksBar> createState() => _QuickLinksBarState();
}

class _QuickLinksBarState extends State<QuickLinksBar> {
  final ScrollController _scrollController = ScrollController();
  final GlobalKey _selectedKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    _scheduleCenter();
  }

  @override
  void didUpdateWidget(QuickLinksBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.selected != oldWidget.selected) {
      _scheduleCenter();
    }
  }

  void _scheduleCenter() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Future.delayed(const Duration(milliseconds: 50), () {
        _centerSelected();
      });
    });
  }

  void _centerSelected() {
    if (!_scrollController.hasClients) return;

    final idx = widget.links.indexWhere((l) => l['name'] == widget.selected);
    if (idx == -1) return;

    double itemLeft;
    double itemWidth;

    final RenderBox? renderBox =
        _selectedKey.currentContext?.findRenderObject() as RenderBox?;

    if (renderBox != null && renderBox.hasSize) {
      final offset = renderBox.localToGlobal(Offset.zero);
      itemLeft = offset.dx;
      itemWidth = renderBox.size.width;
    } else {
      // Estimate if not yet built (rare)
      itemLeft = 4.0 + idx * 122.0; // 4 padding + approx 110 item + 12 gap
      itemWidth = 110.0;
    }

    final screenWidth = MediaQuery.of(context).size.width;
    final target =
        _scrollController.offset + itemLeft - (screenWidth / 2) + (itemWidth / 2);

    _scrollController.animateTo(
      target.clamp(0.0, _scrollController.position.maxScrollExtent),
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOut,
    );
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 44,
      child: ListView.separated(
        controller: _scrollController,
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs), // 4px edge-to-edge
        itemCount: widget.links.length,
        separatorBuilder: (_, __) => const SizedBox(width: 12), // reduced from 24
        itemBuilder: (context, index) {
          final link = widget.links[index];
          final isSelected = link['name'] == widget.selected;
          return GestureDetector(
            key: isSelected ? _selectedKey : null,
            onTap: () => widget.onTap(link),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              padding: const EdgeInsets.symmetric(horizontal: 2), // tighter
              child: Center(
                child: Text(
                  link['name'],
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                    color: isSelected ? AppColors.primary : AppColors.textSecondary, // clear & readable
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

// ─── Pinned header delegate (unchanged, but tokenized) ─────────────────
class QuickLinksHeaderDelegate extends SliverPersistentHeaderDelegate {
  final List<Map<String, dynamic>> links;
  final String selected;
  final ValueChanged<Map<String, dynamic>> onTap;

  QuickLinksHeaderDelegate({
    required this.links,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlapsContent) {
    return ColoredBox(
      color: AppColors.cardBackground,   // white card, not hardcoded
      child: QuickLinksBar(
        links: links,
        selected: selected,
        onTap: onTap,
      ),
    );
  }

  @override
  double get maxExtent => 44;
  @override
  double get minExtent => 44;
  @override
  bool shouldRebuild(covariant QuickLinksHeaderDelegate oldDelegate) {
    return oldDelegate.selected != selected || oldDelegate.links != links;
  }
}
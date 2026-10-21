// lib/widgets/bottom_nav_bar.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:curved_navigation_bar/curved_navigation_bar.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import '../providers/cart_provider.dart';
import '../l10n/app_localizations.dart';

const Color primaryOrange = Color(0xFFF97316);
const Color premiumBlack = Color(0xFF0F0F0F);
const Color cardWhite = Colors.white;
const Color goldAccent = Color(0xFFD4AF37);
const Color barBackground = Color(0xFFF1F5F9);

class BottomNavBar extends ConsumerWidget {
  final int selectedIndex;
  final ValueChanged<int> onTap;
  final bool compact;

  const BottomNavBar({
    Key? key,
    required this.selectedIndex,
    required this.onTap,
    this.compact = true,
  }) : super(key: key);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final cart = ref.watch(cartProvider);
    final count = cart?.itemCount ?? 0;

    // ★ Reduced each icon size by 1 pixel
    const double catIconSize = 20.0;
    const double catActiveIconSize = 22.0;
    const double otherIconSize = 22.0;
    const double otherActiveIconSize = 24.0;
    const double labelFontSize = 13.0;

    String labelFor(int index) {
      switch (index) {
        case 0: return l10n.translate('nav_explore');
        case 1: return l10n.translate('nav_categories');
        case 2: return l10n.translate('nav_find_shop');
        case 3: return l10n.translate('nav_cart');
        case 4: return l10n.translate('nav_profile');
        default: return '';
      }
    }

    Widget _labelWidget(String text) {
      return SizedBox(
        height: 14,
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            text,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: labelFontSize,
              fontWeight: FontWeight.w700,
              color: premiumBlack,
            ),
          ),
        ),
      );
    }

    Widget buildTabIcon(PhosphorIconData regular, PhosphorIconData fill, int tabIndex) {
      final isActive = selectedIndex == tabIndex;
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            isActive ? fill : regular,
            size: isActive ? otherActiveIconSize : otherIconSize,
            color: isActive ? primaryOrange : premiumBlack,
            semanticLabel: labelFor(tabIndex),
          ),
          if (!isActive) ...[
            const SizedBox(height: 1),
            _labelWidget(labelFor(tabIndex)),
          ],
        ],
      );
    }

    Widget buildCategoriesIcon() {
      final isActive = selectedIndex == 1;
      final Color iconColor = isActive ? primaryOrange : premiumBlack;
      final double lensSize = isActive ? catActiveIconSize : catIconSize;

      Widget lensIcon() {
        if (isActive) {
          return SizedBox(
            width: lensSize,
            height: lensSize,
            child: CustomPaint(
              painter: _SolidMagnifyingGlassPainter(iconColor),
            ),
          );
        } else {
          return SizedBox(
            width: lensSize,
            height: lensSize,
            child: CustomPaint(
              painter: _OutlinedMagnifyingGlassPainter(iconColor),
            ),
          );
        }
      }

      Widget buildLines() {
        const List<double> widths = [7, 5, 7];
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: List.generate(
            widths.length,
            (index) => Container(
              margin: const EdgeInsets.symmetric(vertical: 1.5),
              width: widths[index],
              height: 2,
              decoration: BoxDecoration(
                color: iconColor,
                borderRadius: BorderRadius.circular(1),
              ),
            ),
          ),
        );
      }

      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              buildLines(),
              const SizedBox(width: 0.5),
              Transform.translate(
                offset: const Offset(-1, 0),
                child: lensIcon(),
              ),
            ],
          ),
          if (!isActive) ...[
            const SizedBox(height: 1),
            _labelWidget(labelFor(1)),
          ],
        ],
      );
    }

    // ★ Find Shop icon – still nudged upward
    Widget buildShopIcon() {
      final isActive = selectedIndex == 2;
      final label = labelFor(2);
      final double containerSize = otherActiveIconSize + 10;   // now 34
      final double innerContainerSize = otherIconSize + 4;     // now 26
      if (compact) {
        return Transform.translate(
          offset: const Offset(0, -4),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: containerSize,
                height: containerSize,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white,
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black12,
                      blurRadius: 4,
                      offset: Offset(0, 2),
                    ),
                  ],
                ),
                child: Center(
                  child: isActive
                      ? Icon(
                          PhosphorIcons.storefront(PhosphorIconsStyle.fill),
                          size: otherActiveIconSize,
                          color: primaryOrange,
                        )
                      : Container(
                          width: innerContainerSize,
                          height: innerContainerSize,
                          decoration: const BoxDecoration(
                            shape: BoxShape.circle,
                            color: premiumBlack,
                          ),
                          child: Icon(
                            PhosphorIcons.storefront(PhosphorIconsStyle.regular),
                            size: otherIconSize,
                            color: goldAccent,
                          ),
                        ),
                ),
              ),
              if (!isActive) ...[
                const SizedBox(height: 1),
                _labelWidget(label),
              ],
            ],
          ),
        );
      } else {
        return Transform.translate(
          offset: const Offset(0, -4),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: isActive ? Colors.transparent : premiumBlack,
                ),
                child: PhosphorIcon(
                  isActive
                      ? PhosphorIcons.storefront(PhosphorIconsStyle.fill)
                      : PhosphorIcons.storefront(PhosphorIconsStyle.regular),
                  size: otherActiveIconSize,
                  color: isActive ? primaryOrange : goldAccent,
                ),
              ),
              if (!isActive) ...[
                const SizedBox(height: 1),
                _labelWidget(label),
              ],
            ],
          ),
        );
      }
    }

    Widget buildCartIcon() {
      final isActive = selectedIndex == 3;
      final label = labelFor(3);
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Stack(
            clipBehavior: Clip.none,
            children: [
              Icon(
                isActive
                    ? PhosphorIcons.shoppingCartSimple(PhosphorIconsStyle.fill)
                    : PhosphorIcons.shoppingCartSimple(PhosphorIconsStyle.regular),
                size: isActive ? otherActiveIconSize : otherIconSize,
                color: isActive ? primaryOrange : premiumBlack,
                semanticLabel: label,
              ),
              if (count > 0)
                Positioned(
                  right: -6,
                  top: -6,
                  child: Container(
                    padding: const EdgeInsets.all(4),
                    decoration: const BoxDecoration(
                      color: Color(0xFFEF4444),
                      shape: BoxShape.circle,
                    ),
                    constraints: const BoxConstraints(minWidth: 16, minHeight: 16),
                    child: Text(
                      count > 99 ? '99+' : '$count',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 9,
                        fontWeight: FontWeight.w700,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ),
            ],
          ),
          if (!isActive) ...[
            const SizedBox(height: 1),
            _labelWidget(label),
          ],
        ],
      );
    }

    return CurvedNavigationBar(
      index: selectedIndex,
      height: 50,
      color: cardWhite,
      buttonBackgroundColor: Colors.transparent,
      backgroundColor: barBackground,
      animationDuration: const Duration(milliseconds: 300),
      items: [
        buildTabIcon(PhosphorIcons.house(PhosphorIconsStyle.regular), PhosphorIcons.house(PhosphorIconsStyle.fill), 0),
        buildCategoriesIcon(),
        buildShopIcon(),
        buildCartIcon(),
        buildTabIcon(PhosphorIcons.user(PhosphorIconsStyle.regular), PhosphorIcons.user(PhosphorIconsStyle.fill), 4),
      ],
      onTap: (index) => onTap(index),
    );
  }
}

// ★ Solid magnifying glass – stronger 3D highlight (unchanged)
class _SolidMagnifyingGlassPainter extends CustomPainter {
  final Color color;
  _SolidMagnifyingGlassPainter(this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final strokeWidth = size.width * 0.07;
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width * 0.36;

    final handleStart = Offset(center.dx + radius * 0.7, center.dy + radius * 0.7);
    final handleEnd = Offset(handleStart.dx + (radius * 0.61), handleStart.dy + (radius * 0.61));
    canvas.drawLine(
      handleStart,
      handleEnd,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth
        ..strokeCap = StrokeCap.round,
    );

    canvas.drawCircle(center, radius, Paint()..color = color..style = PaintingStyle.fill);

    final highlightOffset = Offset(
      center.dx - radius * 0.25,
      center.dy - radius * 0.35,
    );
    final highlightRadius = radius * 0.30;
    canvas.drawCircle(
      highlightOffset,
      highlightRadius,
      Paint()..color = Colors.white.withOpacity(0.45),
    );

    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

// ★ Outlined magnifying glass – no highlight (unchanged)
class _OutlinedMagnifyingGlassPainter extends CustomPainter {
  final Color color;
  _OutlinedMagnifyingGlassPainter(this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final strokeWidth = size.width * 0.07;
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width * 0.36;

    final handleStart = Offset(center.dx + radius * 0.7, center.dy + radius * 0.7);
    final handleEnd = Offset(handleStart.dx + (radius * 0.61), handleStart.dy + (radius * 0.61));
    canvas.drawLine(
      handleStart,
      handleEnd,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth
        ..strokeCap = StrokeCap.round,
    );

    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
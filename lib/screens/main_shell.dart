// lib/screens/main_shell.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import '../providers/cart_provider.dart';
import '../providers/tab_provider.dart';
import 'home_screen.dart';
import 'category_products_screen.dart';
import 'find_shop_screen.dart';
import 'cart_screen.dart';
import 'profile_screen.dart';
import 'package:et_marketplace_app/utils/translations.dart';


const Color pOrange = Color(0xFFF97316);
const Color pBlack = Color(0xFF0F0F0F);
const Color pWhite = Colors.white;
const Color pGold = Color(0xFFD4AF37);
const Color pGrey = Color(0xFF0F0F0F);

class MainShell extends ConsumerStatefulWidget {
  final int initialTab;
  MainShell({Key? key, this.initialTab = 0}) : super(key: key);

  @override
  ConsumerState<MainShell> createState() => _MainShellState();
}

class _MainShellState extends ConsumerState<MainShell> {
  late int _tab;

  static const _pages = [
    HomeScreen(),
    CategoryProductsScreen(),
    FindShopScreen(),
    CartScreen(),
    ProfileScreen(),
  ];

  final _labels = ['Explore', 'Categories', 'Find Shop', 'Cart', 'Profile'];

  @override
  void initState() {
    super.initState();
    _tab = widget.initialTab;
  }

  void _switchTab(int index) {
    setState(() => _tab = index);
    ref.read(tabProvider.notifier).state = index;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: _pages[_tab],
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          color: pWhite,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          boxShadow: [
            BoxShadow(color: Colors.black.withOpacity(0.06), blurRadius: 16, offset: Offset(0, -4)),
          ],
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
            child: Row(
              children: [
                _tabItem(PhosphorIcons.house(PhosphorIconsStyle.regular), PhosphorIcons.house(PhosphorIconsStyle.fill), 0),
                _tabItem(PhosphorIcons.squaresFour(PhosphorIconsStyle.regular), PhosphorIcons.squaresFour(PhosphorIconsStyle.fill), 1),
                _shopItem(2),
                _cartItem(3),
                _tabItem(PhosphorIcons.userCircle(PhosphorIconsStyle.regular), PhosphorIcons.userCircle(PhosphorIconsStyle.fill), 4),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _tabItem(PhosphorIconData icon, PhosphorIconData activeIcon, int index) {
    final active = _tab == index;
    final color = active ? pOrange : pBlack;
    return Expanded(
      child: GestureDetector(
        onTap: () => _switchTab(index),
        child: Padding(
          padding: EdgeInsets.symmetric(vertical: 2),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              AnimatedContainer(
                duration: Duration(milliseconds: 150),
                padding: EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: active ? pOrange.withOpacity(0.08) : Colors.transparent,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: PhosphorIcon(active ? activeIcon : icon, color: color, size: 22),
              ),
              SizedBox(height: 2),
              Text(_labels[index], style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: active ? pOrange : pGrey)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _shopItem(int index) {
    final active = _tab == index;
    return Expanded(
      child: GestureDetector(
        onTap: () => _switchTab(index),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: EdgeInsets.all(6),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: active ? LinearGradient(colors: [pOrange, Color(0xFFFF8C42)], begin: Alignment.topLeft, end: Alignment.bottomRight) : null,
                color: active ? null : pBlack,
                boxShadow: active ? [BoxShadow(color: pOrange.withOpacity(0.35), blurRadius: 10, offset: Offset(0, 2))] : null,
              ),
              child: PhosphorIcon(active ? PhosphorIcons.storefront(PhosphorIconsStyle.fill) : PhosphorIcons.storefront(PhosphorIconsStyle.regular), color: active ? Colors.white : pGold, size: 20),
            ),
            SizedBox(height: 2),
            Text('Find Shop', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: active ? pOrange : pGrey)),
          ],
        ),
      ),
    );
  }

  Widget _cartItem(int index) {
    final active = _tab == index;
    final cart = ref.watch(cartProvider);
    final count = cart?.itemCount ?? 0;
    final color = active ? pOrange : pBlack;
    return Expanded(
      child: GestureDetector(
        onTap: () => _switchTab(index),
        child: Padding(
          padding: EdgeInsets.symmetric(vertical: 2),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              AnimatedContainer(
                duration: Duration(milliseconds: 150),
                padding: EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: active ? pOrange.withOpacity(0.08) : Colors.transparent,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    PhosphorIcon(active ? PhosphorIcons.shoppingBag(PhosphorIconsStyle.fill) : PhosphorIcons.shoppingBag(PhosphorIconsStyle.regular), color: color, size: 22),
                    if (count > 0)
                      Positioned(
                        right: -6, top: -6,
                        child: Container(
                          padding: EdgeInsets.all(3),
                          decoration: BoxDecoration(color: pOrange, shape: BoxShape.circle, border: Border.all(color: Colors.white, width: 1.5)),
                          constraints: BoxConstraints(minWidth: 14, minHeight: 14),
                          child: Text(count > 9 ? '9+' : '$count', style: TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.w800), textAlign: TextAlign.center),
                        ),
                      ),
                  ],
                ),
              ),
              SizedBox(height: 2),
              Text('Cart', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: active ? pOrange : pGrey)),
            ],
          ),
        ),
      ),
    );
  }
}
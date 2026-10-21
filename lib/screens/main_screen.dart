// lib/screens/main_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/tab_provider.dart';
import '../providers/auth_provider.dart';   // ★ added
import '../widgets/bottom_nav_bar.dart';
import 'home_screen.dart';
import 'category_products_screen.dart';
import 'find_shop_screen.dart';
import 'cart_screen.dart';
import 'profile_screen.dart';

class MainScreen extends ConsumerStatefulWidget {
  const MainScreen({Key? key}) : super(key: key);
  @override
  ConsumerState<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends ConsumerState<MainScreen> {
  static final List<Widget> _pages = [
    const HomeScreen(),
    const CategoryProductsScreen(),
    const FindShopScreen(),
    const CartScreen(),
    const ProfileScreen(),
  ];

  @override
  void initState() {
    super.initState();
    // Refresh the user session every time the main screen is shown.
    // This picks up role changes (e.g., admin approval / vendor deletion) immediately.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(authProvider.notifier).refresh();
    });
  }

  @override
  Widget build(BuildContext context) {
    final selectedIndex = ref.watch(tabProvider);
    return Scaffold(
      body: IndexedStack(
        index: selectedIndex,
        children: _pages,
      ),
      bottomNavigationBar: BottomNavBar(
        selectedIndex: selectedIndex,
        onTap: (index) {
          ref.read(tabProvider.notifier).state = index;
        },
      ),
    );
  }
}
// lib/main.dart
import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'api/client.dart';
import 'providers/auth_provider.dart';
import 'providers/tab_provider.dart';
import 'providers/bottom_bar_visibility.dart';
import 'services/push_notification.dart';

// Localisation
import 'l10n/app_localizations.dart';
import 'l10n/et_material_localizations.dart';
import 'l10n/et_cupertino_localizations.dart';
import 'providers/locale_provider.dart';

// Screens
import 'screens/welcome_screen.dart';
import 'screens/main_screen.dart';
import 'screens/login_screen.dart';
import 'screens/home_screen.dart';
import 'screens/find_shop_screen.dart';
import 'screens/category_products_screen.dart';
import 'screens/profile_screen.dart';
import 'screens/about_screen.dart';
import 'screens/terms_screen.dart';
import 'screens/privacy_screen.dart';
import 'screens/address_book_screen.dart';
import 'screens/account_details_screen.dart';
import 'screens/orders_screen.dart';
import 'screens/order_tracking_screen.dart';
import 'screens/cart_screen.dart';
import 'screens/wishlist_screen.dart';
import 'screens/compare_screen.dart';
import 'screens/checkout_screen.dart';
import 'screens/register_screen.dart';
import 'screens/product_detail_screen.dart';
import 'screens/shop_detail_screen.dart';
import 'screens/notifications_screen.dart';
import 'screens/become_seller_screen.dart';
import 'screens/seller_dashboard_screen.dart';
import 'screens/search_screen.dart';
import 'screens/seller_setup_screen.dart';
import 'screens/price_alerts_screen.dart';

// Product listing screens
import 'screens/all_products_screen.dart';
import 'screens/flash_deals_screen.dart';
import 'screens/super_deals_screen.dart';
import 'screens/hot_deals_screen.dart';
import 'screens/trending_screen.dart';
import 'screens/new_arrivals_screen.dart';
import 'screens/best_sellers_screen.dart';
import 'screens/packages_screen.dart';
import 'screens/collections_screen.dart';

// Package & Collection Detail Screens
import 'screens/package_detail_screen.dart';
import 'screens/collection_detail_screen.dart';

import 'models/category.dart';
import 'models/user.dart';
import 'theme/app_theme.dart';

final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();
final RouteObserver<PageRoute> routeObserver = RouteObserver<PageRoute>();

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await dotenv.load();
  ApiClient.init();

  await Firebase.initializeApp();
  await PushNotification.init();

  // ★ No token registration here – AuthNotifier handles it after login/session check.

  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.dark,
      systemNavigationBarColor: Color(0xFFF8F8F8),
      systemNavigationBarIconBrightness: Brightness.dark,
    ),
  );

  runApp(const ProviderScope(child: MyApp()));
}

// ── Splash page that decides the first screen ──
class SplashPage extends ConsumerStatefulWidget {
  const SplashPage({Key? key}) : super(key: key);
  @override
  ConsumerState<SplashPage> createState() => _SplashPageState();
}

class _SplashPageState extends ConsumerState<SplashPage> {
  @override
  void initState() {
    super.initState();
    _boot();
  }

  Future<void> _boot() async {
    // Wait until the auth provider has finished loading
    final authNotifier = ref.read(authProvider.notifier);
    await authNotifier.checkSession();

    // Read the final user – null if no valid token
    final authState = ref.read(authProvider);
    User? user;
    authState.whenData((u) => user = u);

    if (!mounted) return;

    // Check the welcome flag
    final prefs = await SharedPreferences.getInstance();
    final hasSeenWelcome = prefs.getBool('has_seen_welcome') ?? false;

    // Decide which screen to show
    if (user != null) {
      // Already logged in → go to main
      Navigator.pushReplacementNamed(context, '/main');
    } else if (!hasSeenWelcome) {
      // First time → show the welcome carousel
      Navigator.pushReplacementNamed(context, '/welcome');
    } else {
      // ★ Returning guest → go to main, never login
      Navigator.pushReplacementNamed(context, '/main');
    }
  }

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      backgroundColor: Colors.white,
      body: Center(child: CircularProgressIndicator(color: AppColors.primary)),
    );
  }
}

class MyApp extends ConsumerWidget {
  const MyApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    bottomBarVisibility.value = true;

    final selectedLocale = ref.watch(localeProvider);

    return MaterialApp(
      title: 'ET Marketplace',
      debugShowCheckedModeBanner: false,
      navigatorKey: navigatorKey,
      navigatorObservers: [routeObserver],
      theme: buildAppTheme(),

      // ★ Updated text scale: respects system setting within tight range
      builder: (context, child) {
        final mediaQuery = MediaQuery.of(context);
        final scale = mediaQuery.textScaleFactor.clamp(0.95, 1.0);
        return MediaQuery(
          data: mediaQuery.copyWith(textScaleFactor: scale),
          child: child!,
        );
      },

      locale: selectedLocale,
      supportedLocales: const [
        Locale('en'),
        Locale('am'),
        Locale('om'),
        Locale('ti'),
      ],
      localizationsDelegates: const [
        AppLocalizations.delegate,
        _EtMaterialLocalizationsDelegate(),
        _EtCupertinoLocalizationsDelegate(),
        GlobalWidgetsLocalizations.delegate,
      ],
      localeResolutionCallback: (deviceLocale, supportedLocales) {
        if (selectedLocale != null) return selectedLocale;
        if (deviceLocale != null && supportedLocales.contains(deviceLocale)) {
          return deviceLocale;
        }
        return const Locale('en');
      },
      home: const SplashPage(),
      routes: {
        '/welcome': (context) => const WelcomeScreen(),
        '/main': (context) => const MainScreen(),
        '/login': (context) => const LoginScreen(),
        '/register': (context) => const RegisterScreen(),
        '/wishlist': (context) => const WishlistScreen(),
        '/compare': (context) => const CompareScreen(),

        '/checkout': (context) => const AuthGuard(child: CheckoutScreen()),

        '/orders': (context) => const OrdersScreen(),
        '/account-details': (context) => const AccountDetailsScreen(),
        '/address-book': (context) => const AddressBookScreen(),
        '/about': (context) => const AboutScreen(),
        '/terms': (context) => const TermsScreen(),
        '/privacy': (context) => const PrivacyScreen(),
        '/notifications': (context) => const NotificationsScreen(),
        '/become-seller': (context) => const BecomeSellerScreen(),

        '/seller-dashboard': (context) => const AuthGuard(
              requiredRole: 'seller',
              child: SellerDashboardScreen(),
            ),

        '/seller-setup': (context) => const SellerSetupScreen(),
        '/price-alerts': (context) => const PriceAlertsScreen(),
        '/all-products': (context) => const AllProductsScreen(),
        '/flash-deals': (context) => const FlashDealsScreen(),
        '/super-deals': (context) => const SuperDealsScreen(),
        '/hot-deals': (context) => const HotDealsScreen(),
        '/trending': (context) => const TrendingScreen(),
        '/new-arrivals': (context) => const NewArrivalsScreen(),
        '/best-sellers': (context) => const BestSellersScreen(),
        '/packages': (context) => const PackagesScreen(),
        '/collections': (context) => const CollectionsScreen(),
      },
      onGenerateRoute: (settings) {
        if (settings.name == '/product') {
          final productId = settings.arguments as int?;
          if (productId == null) return _errorRoute('Invalid product ID');
          return MaterialPageRoute(builder: (_) => ProductDetailScreen(productId: productId));
        }
        if (settings.name == '/category') {
          final args = settings.arguments as Map<String, dynamic>?;
          if (args == null) return _errorRoute('Missing category arguments');
          return MaterialPageRoute(
            builder: (_) => CategoryProductsScreen(
              initialCategoryId: args['categoryId'],
              categoryName: args['categoryName'],
            ),
          );
        }
        if (settings.name == '/shop') {
          final shopId = settings.arguments as String?;
          if (shopId == null) return _errorRoute('Invalid shop ID');
          return MaterialPageRoute(builder: (_) => ShopDetailScreen(shopId: int.parse(shopId)));
        }
        if (settings.name == '/order-tracking') {
          final orderId = settings.arguments as int?;
          if (orderId == null) return _errorRoute('Invalid order ID');
          return MaterialPageRoute(builder: (_) => OrderTrackingScreen(orderId: orderId));
        }
        if (settings.name == '/package') {
          final packageId = settings.arguments as int?;
          if (packageId == null) return _errorRoute('Invalid package ID');
          return MaterialPageRoute(builder: (_) => PackageDetailScreen(packageId: packageId));
        }
        if (settings.name == '/collection-detail') {
          final slug = settings.arguments as String?;
          if (slug == null) return _errorRoute('Invalid collection slug');
          return MaterialPageRoute(builder: (_) => CollectionDetailScreen(slug: slug));
        }

        return _errorRoute('Route not found: ${settings.name}');
      },
    );
  }

  Route<dynamic> _errorRoute(String message) {
    return MaterialPageRoute(
      builder: (context) => Scaffold(
        appBar: AppBar(title: const Text('Navigation Error')),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.warning_amber_rounded, size: 48, color: Colors.red),
                const SizedBox(height: 16),
                Text(message, textAlign: TextAlign.center),
                const SizedBox(height: 24),
                ElevatedButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Go Back'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ── Auth guard widget ──
class AuthGuard extends ConsumerWidget {
  final Widget child;
  final String? requiredRole;
  const AuthGuard({required this.child, this.requiredRole, Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(authProvider);
    return auth.when(
      data: (user) {
        if (user == null) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            Navigator.pushReplacementNamed(context, '/login');
          });
          return const Scaffold(body: Center(child: CircularProgressIndicator()));
        }
        if (requiredRole != null && !user.roles.contains(requiredRole)) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            Navigator.pushReplacementNamed(context, '/main');
          });
          return const Scaffold(body: Center(child: CircularProgressIndicator()));
        }
        return child;
      },
      loading: () => const Scaffold(body: Center(child: CircularProgressIndicator())),
      error: (_, __) => const Scaffold(body: Center(child: Text('Error'))),
    );
  }
}

// ── Custom delegates for Ethiopian languages ──
class _EtMaterialLocalizationsDelegate
    extends LocalizationsDelegate<MaterialLocalizations> {
  const _EtMaterialLocalizationsDelegate();

  @override
  bool isSupported(Locale locale) =>
      EtMaterialLocalizations.isSupported(locale);

  @override
  Future<MaterialLocalizations> load(Locale locale) =>
      EtMaterialLocalizations.load(locale);

  @override
  bool shouldReload(covariant LocalizationsDelegate<MaterialLocalizations> old) =>
      false;
}

class _EtCupertinoLocalizationsDelegate
    extends LocalizationsDelegate<CupertinoLocalizations> {
  const _EtCupertinoLocalizationsDelegate();

  @override
  bool isSupported(Locale locale) =>
      EtCupertinoLocalizations.isSupported(locale);

  @override
  Future<CupertinoLocalizations> load(Locale locale) =>
      EtCupertinoLocalizations.load(locale);

  @override
  bool shouldReload(covariant LocalizationsDelegate<CupertinoLocalizations> old) =>
      false;
}
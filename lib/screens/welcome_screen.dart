// 📁 lib/screens/welcome_screen.dart
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'dart:async';
import 'package:shared_preferences/shared_preferences.dart';   // ★ added
import '../theme/app_theme.dart';
import '../l10n/app_localizations.dart';
import 'login_screen.dart';
import 'register_screen.dart';

class WelcomeScreen extends StatefulWidget {
  const WelcomeScreen({Key? key}) : super(key: key);

  @override
  State<WelcomeScreen> createState() => _WelcomeScreenState();
}

class _WelcomeScreenState extends State<WelcomeScreen> {
  late PageController _pageController;
  int _currentPage = 0;
  Timer? _autoSlideTimer;
  Timer? _resumeTimer;
  bool _isUserInteracting = false;
  int _slideCount = 0;

  List<OnboardingSlide> _buildSlides(AppLocalizations l10n) => [
    OnboardingSlide(
      illustration: 'assets/images/welcome_slide1.svg',
      tagline: 'SHOP LOCAL',
      headline: 'Discover Ethiopia’s\nFinest Marketplace',
      subtext: 'Thousands of products from trusted local sellers, handpicked for you.',
    ),
    OnboardingSlide(
      illustration: 'assets/images/welcome_slide2.svg',
      tagline: 'FAST DELIVERY',
      headline: 'Lightning-Fast\nDelivery Nationwide',
      subtext: 'Reliable shipping to every corner of Ethiopia. Track your order in real time.',
    ),
    OnboardingSlide(
      illustration: 'assets/images/welcome_slide3.svg',
      tagline: 'SECURE PAYMENTS',
      headline: '100% Safe &\nSecure Transactions',
      subtext: 'Pay with Telebirr, Chapa, or cash on delivery. Your data is always protected.',
    ),
    OnboardingSlide(
      illustration: 'assets/images/welcome_slide4.svg',
      tagline: 'SELL & GROW',
      headline: 'Turn Your Passion\nInto Profit',
      subtext: 'Open your free store in minutes and reach millions of Ethiopian buyers.',
    ),
    OnboardingSlide(
      illustration: 'assets/images/welcome_slide5.svg',
      tagline: 'JOIN THE FAMILY',
      headline: 'Welcome to\nET Marketplace',
      subtext: 'Create a free account, browse as a guest, or sign in.',
      isLast: true,
    ),
  ];

  @override
  void initState() {
    super.initState();
    _pageController = PageController();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _startAutoSlide();
    });
  }

  @override
  void dispose() {
    _autoSlideTimer?.cancel();
    _resumeTimer?.cancel();
    _pageController.dispose();
    super.dispose();
  }

  void _startAutoSlide() {
    _autoSlideTimer?.cancel();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _autoSlideTimer = Timer.periodic(const Duration(seconds: 5), (timer) {
        if (!mounted || _isUserInteracting) return;
        if (_slideCount == 0) return;
        if (!_pageController.hasClients) return;
        if (_pageController.position.pixels ==
            _pageController.position.maxScrollExtent) {
          timer.cancel();
          return;
        }
        _pageController.nextPage(
          duration: const Duration(milliseconds: 700),
          curve: Curves.easeInOut,
        );
      });
    });
  }

  void _onUserInteractionStart() {
    _isUserInteracting = true;
    _resumeTimer?.cancel();
  }

  void _onUserInteractionEnd() {
    _resumeTimer?.cancel();
    _resumeTimer = Timer(const Duration(milliseconds: 500), () {
      _isUserInteracting = false;
    });
  }

  void _onPageChanged(int page) {
    setState(() => _currentPage = page);
    if (page < _slideCount - 1 && _autoSlideTimer == null) {
      _startAutoSlide();
    }
  }

  void _goToNextPage() {
    _onUserInteractionStart();
    if (_currentPage < _slideCount - 1) {
      _pageController.nextPage(
        duration: const Duration(milliseconds: 500),
        curve: Curves.easeInOut,
      );
    }
    _onUserInteractionEnd();
  }

  void _onSkip() {
    _onUserInteractionStart();
    if (_slideCount > 0) {
      _pageController.animateToPage(
        _slideCount - 1,
        duration: const Duration(milliseconds: 400),
        curve: Curves.easeInOut,
      );
    }
    _onUserInteractionEnd();
  }

  void _onBack() {
    _onUserInteractionStart();
    if (_currentPage > 0) {
      _pageController.previousPage(
        duration: const Duration(milliseconds: 400),
        curve: Curves.easeInOut,
      );
    }
    _onUserInteractionEnd();
  }

  // ★ Save the welcome flag and navigate
  Future<void> _completeOnboarding(String routeName) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('has_seen_welcome', true);
    if (!mounted) return;
    Navigator.pushReplacementNamed(context, routeName);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final slides = _buildSlides(l10n);
    _slideCount = slides.length;
    final isLast = slides[_currentPage].isLast;
    final bottomPadding = MediaQuery.of(context).padding.bottom;
    final screenHeight = MediaQuery.of(context).size.height;
    final textTheme = Theme.of(context).textTheme;

    return Scaffold(
      backgroundColor: AppColors.pageBackground,
      body: Stack(
        children: [
          // ── Background gradient ──
          Positioned.fill(
            child: Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Color(0xFFFFF7F0),
                    Color(0xFFFFFDF9),
                    Color(0xFFFDF6F0),
                  ],
                ),
              ),
            ),
          ),
          // ── Decorative circles ──
          Positioned(
            top: -120,
            right: -80,
            child: IgnorePointer(
              child: Container(
                width: 300,
                height: 300,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [
                      AppColors.primary.withOpacity(0.15),
                      AppColors.primary.withOpacity(0.04),
                      Colors.transparent,
                    ],
                    stops: const [0.0, 0.5, 1.0],
                  ),
                ),
              ),
            ),
          ),
          Positioned(
            bottom: -100,
            left: -60,
            child: IgnorePointer(
              child: Container(
                width: 280,
                height: 280,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [
                      AppColors.primary.withOpacity(0.12),
                      AppColors.primary.withOpacity(0.03),
                      Colors.transparent,
                    ],
                    stops: const [0.0, 0.5, 1.0],
                  ),
                ),
              ),
            ),
          ),
          Positioned.fill(
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 30, sigmaY: 30),
              child: Container(
                color: Colors.white.withOpacity(0.15),
              ),
            ),
          ),

          // ── Content ──
          SafeArea(
            child: Column(
              children: [
                Padding(
                  padding: EdgeInsets.only(left: 20, right: 20, top: screenHeight * 0.012),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      SizedBox(
                        width: 44,
                        height: 44,
                        child: _currentPage > 0
                            ? IconButton(
                                icon: const Icon(Icons.arrow_back_rounded, size: 20),
                                color: AppColors.textPrimary,
                                onPressed: _onBack,
                                splashRadius: 20,
                              )
                            : null,
                      ),
                      if (!isLast)
                        SizedBox(
                          height: 44,
                          child: TextButton(
                            onPressed: _onSkip,
                            style: TextButton.styleFrom(
                              foregroundColor: AppColors.textMuted,
                              padding: const EdgeInsets.symmetric(horizontal: 12),
                            ),
                            child: Text(
                              l10n.translate('skip'),
                              style: textTheme.bodyMedium?.copyWith(
                                fontWeight: FontWeight.w600,
                                color: AppColors.textMuted,
                              ),
                            ),
                          ),
                        )
                      else
                        const SizedBox(width: 44),
                    ],
                  ),
                ),

                Expanded(
                  child: NotificationListener<ScrollNotification>(
                    onNotification: (notification) {
                      if (notification is ScrollStartNotification && notification.dragDetails != null) {
                        _onUserInteractionStart();
                      } else if (notification is ScrollEndNotification) {
                        _onUserInteractionEnd();
                      }
                      return false;
                    },
                    child: PageView.builder(
                      controller: _pageController,
                      onPageChanged: _onPageChanged,
                      itemCount: slides.length,
                      physics: const BouncingScrollPhysics(),
                      itemBuilder: (context, index) => _buildSlide(context, slides[index], textTheme),
                    ),
                  ),
                ),

                Padding(
                  padding: EdgeInsets.only(left: 24, right: 24, bottom: screenHeight * 0.04 + bottomPadding),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _buildDots(slides.length),
                      SizedBox(height: screenHeight * 0.03),
                      if (isLast) ...[
                        _buildPrimaryButton(l10n.translate('sign_in'), () {
                          _completeOnboarding('/login');
                        }),
                        const SizedBox(height: 12),
                        _buildSecondaryButton(l10n.translate('create_free_account'), () {
                          _completeOnboarding('/register');
                        }),
                        const SizedBox(height: 16),
                        _buildGhostButton(l10n.translate('browse_as_guest'), () {
                          _completeOnboarding('/main');
                        }),
                      ] else ...[
                        _buildPrimaryButton(l10n.translate('continue'), _goToNextPage),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSlide(BuildContext context, OnboardingSlide slide, TextTheme textTheme) {
    final illustrationSize = _illustrationSize(context);
    final headlineSize = _responsiveFontSize(context, baseSize: 30);
    final subtextSize = _responsiveFontSize(context, baseSize: 14.5);
    final horizontalPadding = MediaQuery.of(context).size.width * 0.08;

    return Center(
      child: SingleChildScrollView(
        physics: const NeverScrollableScrollPhysics(),
        padding: EdgeInsets.symmetric(horizontal: horizontalPadding),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(color: AppColors.primary.withOpacity(0.12), blurRadius: 60, spreadRadius: 8),
                ],
              ),
              child: SvgPicture.asset(slide.illustration, width: illustrationSize, height: illustrationSize, fit: BoxFit.contain),
            ),
            SizedBox(height: MediaQuery.of(context).size.height * 0.035),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 7),
              decoration: BoxDecoration(
                color: AppColors.primary.withOpacity(0.08),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                slide.tagline,
                textAlign: TextAlign.center,
                style: textTheme.bodySmall?.copyWith(fontSize: 11, fontWeight: FontWeight.w800, color: AppColors.primary, letterSpacing: 3.5),
              ),
            ),
            SizedBox(height: MediaQuery.of(context).size.height * 0.022),
            Text(
              slide.headline,
              textAlign: TextAlign.center,
              style: textTheme.headlineMedium?.copyWith(fontSize: headlineSize, fontWeight: FontWeight.w900, color: AppColors.textPrimary, height: 1.15, letterSpacing: -0.5),
            ),
            SizedBox(height: MediaQuery.of(context).size.height * 0.018),
            Text(
              slide.subtext,
              textAlign: TextAlign.center,
              maxLines: 4,
              overflow: TextOverflow.ellipsis,
              style: textTheme.bodyMedium?.copyWith(fontSize: subtextSize, color: AppColors.textMuted, height: 1.55, fontWeight: FontWeight.w500),
            ),
          ],
        ),
      ),
    );
  }

  double _responsiveFontSize(BuildContext context, {required double baseSize, double minScale = 0.7, double maxScale = 1.0}) {
    final width = MediaQuery.of(context).size.width;
    const baseWidth = 390.0;
    final scale = (width / baseWidth).clamp(minScale, maxScale);
    return baseSize * scale;
  }

  double _illustrationSize(BuildContext context) {
    final height = MediaQuery.of(context).size.height;
    return (height * 0.30).clamp(160.0, 300.0);
  }

  Widget _buildDots(int slideCount) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(slideCount, (index) {
        final isActive = _currentPage == index;
        return AnimatedContainer(
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeInOut,
          margin: const EdgeInsets.symmetric(horizontal: 5),
          width: isActive ? 24.0 : 8.0,
          height: 8.0,
          decoration: BoxDecoration(color: isActive ? AppColors.primary : AppColors.borderLight, borderRadius: BorderRadius.circular(4)),
        );
      }),
    );
  }

  Widget _buildPrimaryButton(String label, VoidCallback onPressed) {
    return SizedBox(
      width: double.infinity,
      height: 52,
      child: ElevatedButton(
        onPressed: onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.primary,
          foregroundColor: Colors.white,
          elevation: 0,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppShapes.radiusSm)),
          padding: const EdgeInsets.symmetric(vertical: 14),
        ),
        child: Text(label, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
      ),
    );
  }

  Widget _buildSecondaryButton(String label, VoidCallback onPressed) {
    return SizedBox(
      width: double.infinity,
      height: 52,
      child: OutlinedButton(
        onPressed: onPressed,
        style: OutlinedButton.styleFrom(
          backgroundColor: AppColors.cardBackground.withOpacity(0.5),
          foregroundColor: AppColors.textPrimary,
          side: const BorderSide(color: AppColors.borderLight, width: 1),
          elevation: 0,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppShapes.radiusSm)),
          padding: const EdgeInsets.symmetric(vertical: 14),
        ),
        child: Text(label, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
      ),
    );
  }

  Widget _buildGhostButton(String label, VoidCallback onPressed) {
    return TextButton(
      onPressed: onPressed,
      style: TextButton.styleFrom(
        foregroundColor: AppColors.textMuted,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      ),
      child: Text(label, style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600, color: AppColors.textMuted)),
    );
  }
}

// ──────────────────────────────────────────────
// 📦 DATA MODEL (unchanged)
// ──────────────────────────────────────────────
class OnboardingSlide {
  final String illustration;
  final String tagline;
  final String headline;
  final String subtext;
  final bool isLast;

  const OnboardingSlide({
    required this.illustration,
    required this.tagline,
    required this.headline,
    required this.subtext,
    this.isLast = false,
  });
}
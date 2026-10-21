// 📁 lib/screens/register_screen.dart
import 'dart:async';
import 'dart:convert';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_html/flutter_html.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import '../providers/auth_provider.dart';
import '../theme/app_theme.dart';
import '../l10n/app_localizations.dart';
import '../api/client.dart';
import 'login_screen.dart';
import 'welcome_screen.dart';
import 'main_screen.dart';
import 'seller_setup_screen.dart';

const List<String> _allowedRegions = [
  'Addis Ababa', 'Dire Dawa', 'Mekelle', 'Bahir Dar', 'Hawassa',
];

class RegisterScreen extends ConsumerStatefulWidget {
  const RegisterScreen({Key? key}) : super(key: key);
  @override
  ConsumerState<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends ConsumerState<RegisterScreen>
    with SingleTickerProviderStateMixin {
  final _formKey = GlobalKey<FormState>();
  final _phoneCtrl = TextEditingController();
  final _nameCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  final _confirmCtrl = TextEditingController();

  bool _isLoading = false;
  bool _obscurePassword = true;
  bool _obscureConfirm = true;
  bool _isOtpStep = false;
  bool _isBuyer = true;
  bool _isBulkSupplier = false;
  String? _errorMessage;

  // password strength fields
  bool _hasMinLength = false;
  bool _hasUppercase = false;
  bool _hasLowercase = false;
  bool _hasDigit = false;
  bool _hasSpecialChar = false;

  bool _detectingLocation = true;
  String? _detectedRegion;
  String? _locationError;

  late AnimationController _entranceController;
  late Animation<double> _fadeAnimation;
  late Animation<Offset> _slideAnimation;

  final List<TextEditingController> _otpCtrls =
      List.generate(6, (_) => TextEditingController());
  final List<FocusNode> _otpNodes = List.generate(6, (_) => FocusNode());

  bool _showTerms = false;
  bool _showPrivacy = false;
  bool _agreedToTerms = false;

  @override
  void initState() {
    super.initState();
    _entranceController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    )..forward();
    _fadeAnimation = CurvedAnimation(
      parent: _entranceController,
      curve: const Interval(0.2, 1.0, curve: Curves.easeOutCubic),
    );
    _slideAnimation = Tween<Offset>(
      begin: const Offset(0, 0.06),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _entranceController,
      curve: const Interval(0.2, 1.0, curve: Curves.easeOutQuart),
    ));

    // listen to password changes for strength indicator
    _passwordCtrl.addListener(_updatePasswordStrength);
    _detectLocation();
  }

  @override
  void dispose() {
    _passwordCtrl.removeListener(_updatePasswordStrength);
    _entranceController.dispose();
    _phoneCtrl.dispose();
    _nameCtrl.dispose();
    _passwordCtrl.dispose();
    _confirmCtrl.dispose();
    for (var c in _otpCtrls) c.dispose();
    for (var n in _otpNodes) n.dispose();
    super.dispose();
  }

  void _updatePasswordStrength() {
    final password = _passwordCtrl.text;
    setState(() {
      _hasMinLength = password.length >= 8;
      _hasUppercase = password.contains(RegExp(r'[A-Z]'));
      _hasLowercase = password.contains(RegExp(r'[a-z]'));
      _hasDigit = password.contains(RegExp(r'\d'));
      _hasSpecialChar = password.contains(RegExp(r'[^A-Za-z0-9]'));
    });
  }

  // ─── Location detection (unchanged) ──────────────────
  Future<void> _detectLocation() async {
    try {
      final permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        final requested = await Geolocator.requestPermission();
        if (requested == LocationPermission.denied) {
          setState(() {
            _locationError = 'Location permission denied. Cannot verify your area.';
            _detectingLocation = false;
          });
          return;
        }
      }
      if (permission == LocationPermission.deniedForever) {
        setState(() {
          _locationError = 'Location permission permanently denied. Cannot verify your area.';
          _detectingLocation = false;
        });
        return;
      }

      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.low,
        timeLimit: const Duration(seconds: 8),
      );

      final uri = Uri.https('nominatim.openstreetmap.org', '/reverse', {
        'lat': position.latitude.toString(),
        'lon': position.longitude.toString(),
        'format': 'json',
      });

      final response = await http.get(uri);
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final address = data['address'] ?? {};
        final city = address['city'] ?? address['town'] ?? address['state'] ?? '';
        final region = city.isNotEmpty ? city : (address['state'] ?? '');

        if (region.isNotEmpty) {
          final matched = _allowedRegions.any(
            (r) => region.toLowerCase().contains(r.toLowerCase()),
          );
          if (matched) {
            setState(() {
              _detectedRegion = region;
              _detectingLocation = false;
            });
          } else {
            setState(() {
              _locationError = "We don't currently serve your area ($region). "
                  "We only operate in: ${_allowedRegions.join(', ')}";
              _detectingLocation = false;
            });
          }
        } else {
          setState(() {
            _locationError = 'Could not determine your location. Please try again.';
            _detectingLocation = false;
          });
        }
      } else {
        setState(() {
          _locationError = 'Could not verify your location. Please try again.';
          _detectingLocation = false;
        });
      }
    } on TimeoutException {
      setState(() {
        _locationError = 'Location request timed out. Please check your connection.';
        _detectingLocation = false;
      });
    } catch (e) {
      setState(() {
        _locationError = 'Could not determine your location. Please try again.';
        _detectingLocation = false;
      });
    }
  }

  void _goBack() {
    if (_isOtpStep) {
      setState(() => _isOtpStep = false);
      return;
    }
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (_) => const WelcomeScreen()),
      (route) => false,
    );
  }

  bool _isValidEthiopianPhone(String number) {
    final cleaned = number.replaceAll(RegExp(r'\D'), '');
    return RegExp(r'^[79]\d{8}$').hasMatch(cleaned);
  }

  Future<void> _sendOtp() async {
    final l10n = AppLocalizations.of(context);
    if (!_formKey.currentState!.validate()) return;

    if (!_isValidEthiopianPhone(_phoneCtrl.text.trim())) {
      setState(() {
        _errorMessage = 'Enter a valid Ethiopian phone number (9 digits, starting with 9 or 7).';
      });
      return;
    }

    if (!_agreedToTerms) {
      setState(() => _errorMessage = l10n.translate('agree_to_terms_required'));
      return;
    }

    if (_locationError != null && _detectedRegion == null) {
      setState(() => _errorMessage = _locationError);
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    final auth = ref.read(authProvider.notifier);
    final success = await auth.register(
      '+251${_phoneCtrl.text.trim().replaceAll(RegExp(r'\D'), '')}',
      _nameCtrl.text.trim(),
      _passwordCtrl.text.trim(),
      region: _detectedRegion,
    );
    if (!mounted) return;
    setState(() => _isLoading = false);
    if (success) {
      setState(() => _isOtpStep = true);
    } else {
      setState(() => _errorMessage = l10n.translate('register_failed'));
    }
  }

  Future<void> _verifyOtp() async {
    final l10n = AppLocalizations.of(context);
    final code = _otpCtrls.map((c) => c.text).join();
    if (code.length != 6) {
      setState(() => _errorMessage = l10n.translate('register_enter_complete_code'));
      return;
    }
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });
    final auth = ref.read(authProvider.notifier);
    final success = await auth.verifyRegisterOtp(
      phone: '+251${_phoneCtrl.text.trim().replaceAll(RegExp(r'\D'), '')}',
      code: code,
    );
    if (!mounted) return;
    setState(() => _isLoading = false);
    if (success) {
      if (!_isBuyer) {
        Navigator.pushAndRemoveUntil(
          context,
          MaterialPageRoute(
            builder: (_) => SellerSetupScreen(isBulkSupplier: _isBulkSupplier),
          ),
          (route) => false,
        );
      } else {
        Navigator.pushAndRemoveUntil(
          context,
          MaterialPageRoute(builder: (_) => const MainScreen()),
          (route) => false,
        );
      }
    } else {
      setState(() => _errorMessage = l10n.translate('register_invalid_otp'));
    }
  }

  void _onOtpChanged(int index, String value) {
    if (value.length > 1) {
      final digits = value.split('').where((c) => RegExp(r'\d').hasMatch(c)).toList();
      for (int i = 0; i < _otpCtrls.length && i < digits.length; i++) {
        _otpCtrls[i].text = digits[i];
      }
      _otpNodes[_otpCtrls.length - 1].requestFocus();
      return;
    }
    if (value.isNotEmpty) {
      _otpCtrls[index].text = value;
      if (index < 5) _otpNodes[index + 1].requestFocus();
    }
  }

  void _resendOtp() {
    final l10n = AppLocalizations.of(context);
    ref.read(authProvider.notifier).resendRegisterOtp(
        phone: '+251${_phoneCtrl.text.trim().replaceAll(RegExp(r'\D'), '')}');
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(l10n.translate('register_otp_resent'),
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
        backgroundColor: AppColors.primary,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppShapes.radiusSm)),
        margin: const EdgeInsets.all(16),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  double _responsiveFont(BuildContext context, double base) {
    final width = MediaQuery.of(context).size.width;
    return (base * (width / 390)).clamp(base * 0.8, base * 1.05);
  }

  Future<void> _showFullLegalModal(String title, String key) async {
    String content = '';
    try {
      final res = await ApiClient.instance.get('/legal/$key');
      content = res.data?['body'] ?? 'Could not load the document.';
    } catch (_) {
      content = 'Could not load the document.';
    }
    if (!mounted) return;
    showDialog(
      context: context,
      useSafeArea: false,
      builder: (_) => Scaffold(
        appBar: AppBar(
          title: Text(title),
          backgroundColor: AppColors.cardBackground,
          leading: IconButton(
            icon: const Icon(Icons.close, color: AppColors.textPrimary),
            onPressed: () => Navigator.pop(context),
          ),
        ),
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Html(
            data: content,
            style: {
              'body': Style(fontSize: FontSize(14), color: AppColors.textPrimary, lineHeight: LineHeight(1.5), margin: Margins.zero),
              'h2': Style(fontSize: FontSize(16), fontWeight: FontWeight.w600, color: AppColors.textPrimary, margin: Margins.only(top: 16, bottom: 6), padding: HtmlPaddings.only(bottom: 6), border: Border(bottom: BorderSide(color: AppColors.borderLight, width: 1))),
              'p': Style(margin: Margins.only(bottom: 10)),
              'ul': Style(margin: Margins.only(bottom: 10)),
              'li': Style(margin: Margins.only(bottom: 2)),
            },
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      backgroundColor: AppColors.pageBackground,
      body: Stack(
        children: [
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
          Positioned(
            top: -120, right: -80,
            child: IgnorePointer(
              child: Container(
                width: 300, height: 300,
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
          Positioned(
            bottom: -100, left: -60,
            child: IgnorePointer(
              child: Container(
                width: 280, height: 280,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [
                      AppColors.primary.withOpacity(0.1),
                      AppColors.primary.withOpacity(0.02),
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
              filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
              child: Container(color: Colors.white.withOpacity(0.05)),
            ),
          ),
          if (_detectingLocation)
            const Center(child: CircularProgressIndicator(color: AppColors.primary))
          else
            SafeArea(
              child: _isOtpStep ? _buildOtpPage(l10n) : _buildRegPage(l10n),
            ),
        ],
      ),
    );
  }

  Widget _buildRegPage(AppLocalizations l10n) {
    final screenHeight = MediaQuery.of(context).size.height;
    final screenWidth = MediaQuery.of(context).size.width;
    final textTheme = Theme.of(context).textTheme;
    final headlineSize = _responsiveFont(context, 26);
    final subtextSize = _responsiveFont(context, 14);
    final bottomPadding = MediaQuery.of(context).padding.bottom;
    final illustrationSize = (screenHeight * 0.13).clamp(90.0, 130.0);

    final subtitle = _isBuyer
        ? l10n.translate('register_buyer_subtitle')
        : l10n.translate('register_seller_subtitle');

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.only(left: AppSpacing.sm, top: AppSpacing.xxs),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: _goBack,
                borderRadius: BorderRadius.circular(AppShapes.radiusMd),
                child: Container(
                  width: 40, height: 40,
                  decoration: BoxDecoration(
                    color: AppColors.hoverState,
                    borderRadius: BorderRadius.circular(AppShapes.radiusMd),
                    border: Border.all(color: AppColors.borderLight),
                  ),
                  child: const Icon(Icons.arrow_back_rounded,
                      color: AppColors.textPrimary, size: 20),
                ),
              ),
            ),
          ),
        ),
        Expanded(
          child: SingleChildScrollView(
            physics: const BouncingScrollPhysics(),
            padding: EdgeInsets.fromLTRB(
                screenWidth * 0.06, 4, screenWidth * 0.06, bottomPadding + 24),
            child: FadeTransition(
              opacity: _fadeAnimation,
              child: SlideTransition(
                position: _slideAnimation,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SvgPicture.asset(
                      'assets/images/register_illustration.svg',
                      width: illustrationSize, height: illustrationSize,
                      fit: BoxFit.contain,
                    ),
                    SizedBox(height: screenHeight * 0.012),
                    Text(
                      l10n.translate('register_create_account'),
                      textAlign: TextAlign.center,
                      style: textTheme.headlineMedium?.copyWith(
                        fontSize: headlineSize, fontWeight: FontWeight.w900,
                        color: AppColors.textPrimary, letterSpacing: -0.5, height: 1.15,
                      ),
                    ),
                    SizedBox(height: screenHeight * 0.006),
                    AnimatedSwitcher(
                      duration: const Duration(milliseconds: 300),
                      child: Text(
                        subtitle,
                        key: ValueKey(subtitle),
                        textAlign: TextAlign.center,
                        style: textTheme.bodyLarge?.copyWith(
                          fontSize: subtextSize, color: AppColors.textMuted,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                    SizedBox(height: screenHeight * 0.022),

                    if (_locationError != null && _detectedRegion == null)
                      Container(
                        width: double.infinity,
                        margin: const EdgeInsets.only(bottom: 16),
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.red.shade50,
                          borderRadius: BorderRadius.circular(AppShapes.radiusMd),
                          border: Border.all(color: Colors.red.shade200),
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.location_off, color: Colors.red.shade700, size: 18),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                _locationError!,
                                style: TextStyle(
                                  color: Colors.red.shade700, fontSize: 13,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),

                    Container(
                      padding: EdgeInsets.all(screenWidth * 0.05),
                      decoration: BoxDecoration(
                        color: AppColors.cardBackground.withOpacity(0.85),
                        borderRadius: BorderRadius.circular(AppShapes.radiusLg),
                        border: Border.all(color: Colors.white.withOpacity(0.6), width: 1.5),
                        boxShadow: [
                          BoxShadow(
                            color: AppColors.primary.withOpacity(0.08),
                            blurRadius: 40, spreadRadius: 5,
                          ),
                        ],
                      ),
                      child: _buildRegForm(l10n),
                    ),
                    SizedBox(height: screenHeight * 0.022),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Flexible(
                          child: Text(
                            l10n.translate('register_already_have_account'),
                            style: textTheme.bodyMedium?.copyWith(
                              color: AppColors.textMuted, fontWeight: FontWeight.w500,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        GestureDetector(
                          onTap: () => Navigator.pushReplacement(
                            context,
                            MaterialPageRoute(builder: (_) => const LoginScreen()),
                          ),
                          child: Text(
                            l10n.translate('register_sign_in'),
                            style: textTheme.bodyMedium?.copyWith(
                              color: AppColors.primary, fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildRegForm(AppLocalizations l10n) {
    final textTheme = Theme.of(context).textTheme;
    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Role selector (unchanged)
          Container(
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              color: AppColors.cardBackground,
              borderRadius: BorderRadius.circular(AppShapes.radiusMd),
              border: Border.all(color: AppColors.borderLight),
            ),
            child: Row(
              children: [
                Expanded(
                  child: GestureDetector(
                    onTap: () => setState(() => _isBuyer = true),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      curve: Curves.easeInOut,
                      padding: const EdgeInsets.symmetric(vertical: 11),
                      decoration: BoxDecoration(
                        color: AppColors.cardBackground,
                        borderRadius: BorderRadius.circular(AppShapes.radiusSm),
                        border: _isBuyer
                            ? Border.all(color: AppColors.primary.withOpacity(0.5), width: 1.5)
                            : Border.all(color: Colors.transparent, width: 1.5),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.person_outline, size: 18,
                              color: _isBuyer ? AppColors.primary : AppColors.textMuted),
                          const SizedBox(width: 6),
                          Text(
                            l10n.translate('register_buyer'),
                            style: TextStyle(
                              fontSize: 14, fontWeight: FontWeight.w700,
                              color: _isBuyer ? AppColors.primary : AppColors.textMuted,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: GestureDetector(
                    onTap: () => setState(() => _isBuyer = false),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      curve: Curves.easeInOut,
                      padding: const EdgeInsets.symmetric(vertical: 11),
                      decoration: BoxDecoration(
                        color: AppColors.cardBackground,
                        borderRadius: BorderRadius.circular(AppShapes.radiusSm),
                        border: !_isBuyer
                            ? Border.all(color: AppColors.primary.withOpacity(0.5), width: 1.5)
                            : Border.all(color: Colors.transparent, width: 1.5),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.store_outlined, size: 18,
                              color: !_isBuyer ? AppColors.primary : AppColors.textMuted),
                          const SizedBox(width: 6),
                          Text(
                            l10n.translate('register_seller'),
                            style: TextStyle(
                              fontSize: 14, fontWeight: FontWeight.w700,
                              color: !_isBuyer ? AppColors.primary : AppColors.textMuted,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),

          _buildLabel(l10n.translate('register_full_name'), textTheme),
          const SizedBox(height: 6),
          _buildInput(
              controller: _nameCtrl,
              hint: l10n.translate('register_full_name_hint'),
              icon: Icons.person_outline_rounded),

          const SizedBox(height: 14),

          // Phone
          _buildLabel(l10n.translate('register_phone_number'), textTheme),
          const SizedBox(height: 6),
          Container(
            decoration: BoxDecoration(
              color: AppColors.hoverState,
              borderRadius: BorderRadius.circular(AppShapes.radiusMd),
              border: Border.all(color: AppColors.borderLight),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 15),
                  decoration: BoxDecoration(
                    border: Border(right: BorderSide(color: AppColors.borderLight)),
                  ),
                  child: Row(
                    children: const [
                      Text('🇪🇹', style: TextStyle(fontSize: 18)),
                      SizedBox(width: 4),
                      Text('+251', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                    ],
                  ),
                ),
                Expanded(
                  child: TextFormField(
                    controller: _phoneCtrl,
                    keyboardType: TextInputType.phone,
                    cursorColor: AppColors.primary,
                    style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                          fontWeight: FontWeight.w500, color: AppColors.textPrimary,
                        ),
                    decoration: InputDecoration(
                      hintText: '9XX XXX XXX',
                      hintStyle: Theme.of(context).textTheme.bodyLarge?.copyWith(
                            color: AppColors.textMuted, fontWeight: FontWeight.w400,
                          ),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 15),
                      border: InputBorder.none,
                      enabledBorder: InputBorder.none,
                      focusedBorder: InputBorder.none,
                      errorBorder: InputBorder.none,
                    ),
                    inputFormatters: [
                      FilteringTextInputFormatter.digitsOnly,
                      LengthLimitingTextInputFormatter(9),
                    ],
                    validator: (v) {
                      if (v == null || v.isEmpty) return 'Required';
                      if (!_isValidEthiopianPhone('+251$v'))
                        return 'Enter a valid Ethiopian number (9 digits, start with 9 or 7)';
                      return null;
                    },
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Ethio Telecom (9XX) or Safaricom (7XX) – 9 digits',
            style: TextStyle(fontSize: 11, color: AppColors.textMuted),
          ),

          const SizedBox(height: 14),

          // Password with strength indicator
          _buildLabel(l10n.translate('register_password'), textTheme),
          const SizedBox(height: 6),
          _buildInput(
            controller: _passwordCtrl,
            hint: l10n.translate('register_password_hint'),
            icon: Icons.lock_outline_rounded,
            obscure: _obscurePassword,
            suffix: IconButton(
              icon: Icon(
                _obscurePassword ? Icons.visibility_off_rounded : Icons.visibility_rounded,
                color: AppColors.textMuted, size: 20,
              ),
              onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
              splashRadius: 16,
            ),
            validator: (v) {
              if (v == null || v.isEmpty) return 'Required';
              if (!RegExp(r'^(?=.*[a-z])(?=.*[A-Z])(?=.*\d)(?=.*[^A-Za-z0-9])').hasMatch(v)) {
                return 'Password must include uppercase, lowercase, digit, and special character';
              }
              if (v.length < 8) return 'At least 8 characters';
              return null;
            },
          ),
          if (_passwordCtrl.text.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(left: 4, top: 6),
              child: _buildPasswordStrengthIndicator(),
            ),

          const SizedBox(height: 14),

          _buildLabel(l10n.translate('register_confirm_password'), textTheme),
          const SizedBox(height: 6),
          _buildInput(
            controller: _confirmCtrl,
            hint: l10n.translate('register_confirm_password_hint'),
            icon: Icons.lock_outline_rounded,
            obscure: _obscureConfirm,
            suffix: IconButton(
              icon: Icon(
                _obscureConfirm ? Icons.visibility_off_rounded : Icons.visibility_rounded,
                color: AppColors.textMuted, size: 20,
              ),
              onPressed: () => setState(() => _obscureConfirm = !_obscureConfirm),
              splashRadius: 16,
            ),
            validator: (v) => v != _passwordCtrl.text
                ? l10n.translate('register_passwords_not_match')
                : null,
          ),

          if (!_isBuyer) ...[
            const SizedBox(height: 16),
            CheckboxListTile(
              value: _isBulkSupplier,
              onChanged: (val) => setState(() => _isBulkSupplier = val ?? false),
              title: Text(
                l10n.translate('register_bulk_supplier_label'),
                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
              ),
              controlAffinity: ListTileControlAffinity.leading,
              activeColor: AppColors.primary,
              contentPadding: EdgeInsets.zero,
            ),
          ],

          // Legal summaries
          const SizedBox(height: 12),
          _buildLegalAccordion(
            title: _isBuyer ? 'Terms of Service' : 'Seller Agreement & Terms',
            icon: Icons.article_outlined,
            expanded: _showTerms,
            onToggle: () => setState(() => _showTerms = !_showTerms),
            summary: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'ET Marketplace connects buyers with independent sellers. '
                  'Sellers are responsible for quality, legality, and tax obligations.',
                  style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
                ),
                const SizedBox(height: 4),
                InkWell(
                  onTap: () => _showFullLegalModal('Terms of Service', 'terms'),
                  child: Text(
                    'Read full Terms →',
                    style: TextStyle(color: AppColors.primary, fontWeight: FontWeight.w600, fontSize: 12),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 6),
          _buildLegalAccordion(
            title: 'Privacy Policy',
            icon: Icons.lock_outline,
            expanded: _showPrivacy,
            onToggle: () => setState(() => _showPrivacy = !_showPrivacy),
            summary: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'We collect phone number, full name, location data, delivery addresses. '
                  'Data is used for order fulfilment and legal compliance.',
                  style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
                ),
                const SizedBox(height: 4),
                InkWell(
                  onTap: () => _showFullLegalModal('Privacy Policy', 'privacy'),
                  child: Text(
                    'Read full Privacy Policy →',
                    style: TextStyle(color: AppColors.primary, fontWeight: FontWeight.w600, fontSize: 12),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          CheckboxListTile(
            value: _agreedToTerms,
            onChanged: (val) => setState(() => _agreedToTerms = val ?? false),
            title: Text(
              _isBuyer
                  ? 'I have read and agree to the Terms of Service, Privacy Policy, and Buyer Protection.'
                  : 'I have read and agree to the Seller Agreement, Terms, and Privacy Policy.',
              style: const TextStyle(fontSize: 12),
            ),
            controlAffinity: ListTileControlAffinity.leading,
            activeColor: AppColors.primary,
            contentPadding: EdgeInsets.zero,
          ),

          if (_errorMessage != null) ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: AppColors.error.withOpacity(0.05),
                borderRadius: BorderRadius.circular(AppShapes.radiusSm),
                border: Border.all(color: AppColors.error.withOpacity(0.15)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.error_outline_rounded, color: AppColors.error, size: 16),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _errorMessage!,
                      style: textTheme.bodySmall?.copyWith(
                        color: AppColors.error, fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],

          const SizedBox(height: 22),
          SizedBox(
            height: 48,
            child: ElevatedButton(
              onPressed: _isLoading ? null : _sendOtp,
              style: AppComponentStyles.primaryButton.copyWith(
                shape: WidgetStatePropertyAll(
                  RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(AppShapes.radiusMd)),
                ),
              ),
              child: _isLoading
                  ? const SizedBox(height: 22, width: 22,
                      child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white))
                  : Text(l10n.translate('register_continue'),
                      style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
            ),
          ),
        ],
      ),
    );
  }

  // ★ Password strength indicator widget
  Widget _buildPasswordStrengthIndicator() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _strengthRow('At least 8 characters', _hasMinLength),
        _strengthRow('Contains uppercase letter', _hasUppercase),
        _strengthRow('Contains lowercase letter', _hasLowercase),
        _strengthRow('Contains digit', _hasDigit),
        _strengthRow('Contains special character', _hasSpecialChar),
      ],
    );
  }

  Widget _strengthRow(String text, bool valid) {
    return Row(
      children: [
        Icon(
          valid ? Icons.check_circle : Icons.circle_outlined,
          size: 14,
          color: valid ? AppColors.success : AppColors.textMuted,
        ),
        const SizedBox(width: 6),
        Text(
          text,
          style: TextStyle(
            fontSize: 11,
            color: valid ? AppColors.textPrimary : AppColors.textMuted,
          ),
        ),
      ],
    );
  }

  // Rest of the helper methods (unchanged) ──────────────────
  Widget _buildLegalAccordion({
    required String title, required IconData icon,
    required bool expanded, required VoidCallback onToggle,
    required Widget summary,
  }) {
    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: AppColors.borderLight),
        borderRadius: BorderRadius.circular(AppShapes.radiusSm),
      ),
      child: Column(
        children: [
          InkWell(
            onTap: onToggle,
            borderRadius: BorderRadius.circular(AppShapes.radiusSm),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              child: Row(
                children: [
                  Icon(icon, size: 16, color: AppColors.primary),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(title,
                        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                  ),
                  Icon(expanded ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down,
                      color: AppColors.textMuted),
                ],
              ),
            ),
          ),
          AnimatedCrossFade(
            firstChild: const SizedBox.shrink(),
            secondChild: Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
              child: summary,
            ),
            crossFadeState: expanded ? CrossFadeState.showSecond : CrossFadeState.showFirst,
            duration: const Duration(milliseconds: 200),
          ),
        ],
      ),
    );
  }

  Widget _buildOtpPage(AppLocalizations l10n) {
    final screenHeight = MediaQuery.of(context).size.height;
    final screenWidth = MediaQuery.of(context).size.width;
    final textTheme = Theme.of(context).textTheme;
    final headlineSize = _responsiveFont(context, 24);
    final subtextSize = _responsiveFont(context, 13.5);
    final bottomPadding = MediaQuery.of(context).padding.bottom;

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.only(left: AppSpacing.sm, top: AppSpacing.xxs),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: _goBack,
                borderRadius: BorderRadius.circular(AppShapes.radiusMd),
                child: Container(
                  width: 40, height: 40,
                  decoration: BoxDecoration(
                    color: AppColors.hoverState,
                    borderRadius: BorderRadius.circular(AppShapes.radiusMd),
                    border: Border.all(color: AppColors.borderLight),
                  ),
                  child: const Icon(Icons.arrow_back_rounded,
                      color: AppColors.textPrimary, size: 20),
                ),
              ),
            ),
          ),
        ),
        Expanded(
          child: SingleChildScrollView(
            physics: const BouncingScrollPhysics(),
            padding: EdgeInsets.fromLTRB(
                screenWidth * 0.06, 4, screenWidth * 0.06, bottomPadding + 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(height: screenHeight * 0.02),
                Container(
                  width: 80, height: 80,
                  decoration: BoxDecoration(
                    color: AppColors.primary.withOpacity(0.08),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.message_rounded,
                      color: AppColors.primary, size: 38),
                ),
                SizedBox(height: screenHeight * 0.024),
                Text(
                  l10n.translate('register_otp_title'),
                  textAlign: TextAlign.center,
                  style: textTheme.headlineMedium?.copyWith(
                    fontSize: headlineSize, fontWeight: FontWeight.w900,
                    color: AppColors.textPrimary, letterSpacing: -0.4,
                  ),
                ),
                SizedBox(height: screenHeight * 0.008),
                Text(
                  l10n.translate('register_otp_subtitle')
                      .replaceAll('{phone}', '+251${_phoneCtrl.text.replaceAll(RegExp(r'\D'), '')}'),
                  textAlign: TextAlign.center,
                  style: textTheme.bodyLarge?.copyWith(
                    fontSize: subtextSize, color: AppColors.textMuted,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                SizedBox(height: screenHeight * 0.024),
                Container(
                  padding: EdgeInsets.all(screenWidth * 0.05),
                  decoration: BoxDecoration(
                    color: AppColors.cardBackground.withOpacity(0.85),
                    borderRadius: BorderRadius.circular(AppShapes.radiusLg),
                    border: Border.all(color: Colors.white.withOpacity(0.6), width: 1.5),
                    boxShadow: [
                      BoxShadow(
                        color: AppColors.primary.withOpacity(0.08),
                        blurRadius: 40, spreadRadius: 5,
                      ),
                    ],
                  ),
                  child: _buildOtpForm(l10n),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildOtpForm(AppLocalizations l10n) {
    final screenWidth = MediaQuery.of(context).size.width;
    final textTheme = Theme.of(context).textTheme;
    final otpBoxSize = ((screenWidth - 48) / 6).clamp(42.0, 54.0);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          l10n.translate('register_verification_code'),
          style: textTheme.bodyMedium?.copyWith(
            fontWeight: FontWeight.w700, color: AppColors.textPrimary,
          ),
        ),
        const SizedBox(height: 12),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: List.generate(6, (index) {
            return SizedBox(
              width: otpBoxSize, height: otpBoxSize * 1.2,
              child: TextFormField(
                controller: _otpCtrls[index],
                focusNode: _otpNodes[index],
                textAlign: TextAlign.center,
                keyboardType: TextInputType.number,
                maxLength: 1,
                cursorColor: AppColors.primary,
                style: textTheme.headlineMedium?.copyWith(
                  fontWeight: FontWeight.w700, color: AppColors.textPrimary,
                ),
                decoration: InputDecoration(
                  counterText: '',
                  filled: true,
                  fillColor: AppColors.hoverState,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(AppShapes.radiusSm),
                    borderSide: const BorderSide(color: AppColors.borderLight),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(AppShapes.radiusSm),
                    borderSide: const BorderSide(color: AppColors.borderLight),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(AppShapes.radiusSm),
                    borderSide: const BorderSide(color: AppColors.primary, width: 2),
                  ),
                  contentPadding: EdgeInsets.zero,
                ),
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                onChanged: (val) => _onOtpChanged(index, val),
              ),
            );
          }),
        ),
        if (_errorMessage != null) ...[
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: AppColors.error.withOpacity(0.05),
              borderRadius: BorderRadius.circular(AppShapes.radiusSm),
              border: Border.all(color: AppColors.error.withOpacity(0.15)),
            ),
            child: Row(
              children: [
                const Icon(Icons.error_outline_rounded, color: AppColors.error, size: 16),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _errorMessage!,
                    style: textTheme.bodySmall?.copyWith(
                      color: AppColors.error, fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
        const SizedBox(height: 22),
        SizedBox(
          height: 48,
          child: ElevatedButton(
            onPressed: _isLoading ? null : _verifyOtp,
            style: AppComponentStyles.primaryButton.copyWith(
              shape: WidgetStatePropertyAll(
                RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(AppShapes.radiusMd)),
              ),
            ),
            child: _isLoading
                ? const SizedBox(height: 22, width: 22,
                    child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white))
                : Text(l10n.translate('register_verify_continue'),
                    style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
          ),
        ),
        const SizedBox(height: 14),
        Center(
          child: TextButton(
            onPressed: _resendOtp,
            style: TextButton.styleFrom(
              foregroundColor: AppColors.primary,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            ),
            child: Text(l10n.translate('register_resend_code'),
                style: textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w700, color: AppColors.primary)),
          ),
        ),
      ],
    );
  }

  Widget _buildLabel(String text, TextTheme textTheme) {
    return Padding(
      padding: const EdgeInsets.only(left: 2),
      child: Text(
        text,
        style: textTheme.bodySmall?.copyWith(
          fontWeight: FontWeight.w700, color: AppColors.textPrimary,
        ),
      ),
    );
  }

  Widget _buildInput({
    required TextEditingController controller,
    required String hint,
    required IconData icon,
    TextInputType? keyboardType,
    bool obscure = false,
    Widget? suffix,
    String? Function(String?)? validator,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.hoverState,
        borderRadius: BorderRadius.circular(AppShapes.radiusMd),
        border: Border.all(color: AppColors.borderLight),
      ),
      child: TextFormField(
        controller: controller,
        obscureText: obscure,
        keyboardType: keyboardType,
        cursorColor: AppColors.primary,
        cursorWidth: 1.5,
        style: Theme.of(context).textTheme.bodyLarge?.copyWith(
              fontWeight: FontWeight.w500, color: AppColors.textPrimary,
            ),
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: Theme.of(context).textTheme.bodyLarge?.copyWith(
                color: AppColors.textMuted, fontWeight: FontWeight.w400,
              ),
          prefixIcon: Icon(icon, color: AppColors.primary, size: 20),
          suffixIcon: suffix,
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 14, vertical: 15),
          border: InputBorder.none,
          enabledBorder: InputBorder.none,
          focusedBorder: InputBorder.none,
          errorBorder: InputBorder.none,
          focusedErrorBorder: InputBorder.none,
        ),
        validator: validator ??
            ((v) => (v == null || v.trim().isEmpty)
                ? '${AppLocalizations.of(context).translate('register_required')}'
                : null),
      ),
    );
  }
}
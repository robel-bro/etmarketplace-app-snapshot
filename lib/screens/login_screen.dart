// lib/screens/login_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';
import '../providers/auth_provider.dart';
import '../theme/app_theme.dart';
import '../l10n/app_localizations.dart';
import 'register_screen.dart';
import 'main_screen.dart';
import 'forgot_password_screen.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({Key? key}) : super(key: key);

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen>
    with TickerProviderStateMixin {
  final _formKey = GlobalKey<FormState>();
  final _phoneController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _isLoading = false;
  bool _obscurePassword = true;
  String? _errorText;               // ★ inline error message

  late AnimationController _entranceController;
  late Animation<double> _fadeAnimation;
  late Animation<Offset> _slideAnimation;

  @override
  void initState() {
    super.initState();
    _entranceController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..forward();
    _fadeAnimation = CurvedAnimation(
      parent: _entranceController,
      curve: const Interval(0.2, 1.0, curve: Curves.easeOutCubic),
    );
    _slideAnimation = Tween<Offset>(
      begin: const Offset(0, 0.08),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _entranceController,
      curve: const Interval(0.2, 1.0, curve: Curves.easeOutQuart),
    ));
  }

  @override
  void dispose() {
    _entranceController.dispose();
    _phoneController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  void _safeBack() {
    if (Navigator.of(context).canPop()) {
      Navigator.of(context).pop();
    } else {
      Navigator.of(context).pushNamedAndRemoveUntil('/welcome', (_) => false);
    }
  }

  void _clearError() {
    if (_errorText != null) setState(() => _errorText = null);
  }

  Future<void> _login() async {
    final l10n = AppLocalizations.of(context);
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isLoading = true;
      _errorText = null;
    });

    try {
      final success = await ref.read(authProvider.notifier).login(
            _phoneController.text.trim(),
            _passwordController.text.trim(),
          );

      if (!mounted) return;
      setState(() => _isLoading = false);

      if (success) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const MainScreen()),
        );
      } else {
        setState(() => _errorText = l10n.translate('login_invalid_phone_or_password'));
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _errorText = l10n.translate('login_something_went_wrong');
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final screenHeight = MediaQuery.of(context).size.height;
    final screenWidth = MediaQuery.of(context).size.width;
    final textTheme = Theme.of(context).textTheme;
    final illustrationSize = (screenHeight * 0.22).clamp(150.0, 230.0);
    final bottomPadding = MediaQuery.of(context).padding.bottom;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (bool didPop, _) {
        if (!didPop) _safeBack();
      },
      child: Scaffold(
        backgroundColor: AppColors.pageBackground,
        body: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Color(0xFFFFFBF9),
                Colors.white,
                Colors.white,
              ],
              stops: [0.0, 0.3, 1.0],
            ),
          ),
          child: SafeArea(
            child: Stack(
              children: [
                Positioned(
                  top: -80,
                  right: -60,
                  child: Container(
                    width: 200,
                    height: 200,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: RadialGradient(
                        colors: [
                          AppColors.primary.withOpacity(0.06),
                          AppColors.primary.withOpacity(0.02),
                          Colors.transparent,
                        ],
                        stops: const [0.0, 0.5, 1.0],
                      ),
                    ),
                  ),
                ),
                Positioned(
                  bottom: screenHeight * 0.3,
                  left: -40,
                  child: Container(
                    width: 160,
                    height: 160,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: RadialGradient(
                        colors: [
                          AppColors.primary.withOpacity(0.05),
                          AppColors.primary.withOpacity(0.01),
                          Colors.transparent,
                        ],
                        stops: const [0.0, 0.5, 1.0],
                      ),
                    ),
                  ),
                ),

                Positioned(
                  top: 8,
                  left: 16,
                  child: Material(
                    color: Colors.transparent,
                    child: InkWell(
                      onTap: _safeBack,
                      borderRadius: BorderRadius.circular(16),
                      splashColor: AppColors.primary.withOpacity(0.1),
                      highlightColor: AppColors.primary.withOpacity(0.05),
                      child: Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.9),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                              color: AppColors.borderLight.withOpacity(0.8),
                              width: 1),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.04),
                              blurRadius: 10,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: const Icon(
                          Icons.arrow_back_rounded,
                          color: AppColors.textPrimary,
                          size: 22,
                        ),
                      ),
                    ),
                  ),
                ),

                Center(
                  child: SingleChildScrollView(
                    padding: EdgeInsets.only(bottom: bottomPadding + 24),
                    child: FadeTransition(
                      opacity: _fadeAnimation,
                      child: SlideTransition(
                        position: _slideAnimation,
                        child: Padding(
                          padding: EdgeInsets.symmetric(
                              horizontal: screenWidth * 0.072),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              SizedBox(height: screenHeight * 0.04),

                              TweenAnimationBuilder<double>(
                                tween: Tween(begin: 0.85, end: 1.0),
                                duration: const Duration(milliseconds: 1000),
                                curve: Curves.easeOutBack,
                                builder: (context, value, child) {
                                  return Transform.scale(
                                    scale: value,
                                    child: child,
                                  );
                                },
                                child: Container(
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    boxShadow: [
                                      BoxShadow(
                                        color: AppColors.primary.withOpacity(0.12),
                                        blurRadius: 70,
                                        spreadRadius: 12,
                                      ),
                                      BoxShadow(
                                        color: AppColors.primary.withOpacity(0.06),
                                        blurRadius: 40,
                                        spreadRadius: 4,
                                      ),
                                    ],
                                  ),
                                  child: SvgPicture.asset(
                                    'assets/images/login_illustration.svg',
                                    width: illustrationSize,
                                    height: illustrationSize,
                                    fit: BoxFit.contain,
                                    placeholderBuilder: (_) => Container(
                                      width: illustrationSize,
                                      height: illustrationSize,
                                      decoration: BoxDecoration(
                                        color: AppColors.hoverState,
                                        borderRadius:
                                            BorderRadius.circular(24),
                                        gradient: LinearGradient(
                                          colors: [
                                            AppColors.hoverState,
                                            AppColors.hoverState
                                                .withOpacity(0.5),
                                          ],
                                          begin: Alignment.topLeft,
                                          end: Alignment.bottomRight,
                                        ),
                                      ),
                                      child: const Center(
                                        child: CircularProgressIndicator(
                                          color: AppColors.primary,
                                          strokeWidth: 3,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ),

                              SizedBox(height: screenHeight * 0.025),

                              Text(
                                l10n.translate('login_welcome_back'),
                                textAlign: TextAlign.center,
                                style: textTheme.headlineMedium?.copyWith(
                                  fontSize: 30,
                                  fontWeight: FontWeight.w900,
                                  color: AppColors.textPrimary,
                                  letterSpacing: -0.7,
                                  height: 1.1,
                                  shadows: [
                                    Shadow(
                                      color: Colors.black.withOpacity(0.03),
                                      blurRadius: 2,
                                      offset: const Offset(0, 1),
                                    ),
                                  ],
                                ),
                              ),

                              SizedBox(height: screenHeight * 0.01),

                              Text(
                                l10n.translate('login_sign_in_subtitle'),
                                textAlign: TextAlign.center,
                                style: textTheme.bodyLarge?.copyWith(
                                  color: AppColors.textMuted,
                                  fontWeight: FontWeight.w500,
                                  letterSpacing: -0.2,
                                ),
                              ),

                              SizedBox(height: screenHeight * 0.035),

                              Container(
                                padding: EdgeInsets.all(screenWidth * 0.06),
                                decoration: BoxDecoration(
                                  color: AppColors.cardBackground,
                                  borderRadius:
                                      BorderRadius.circular(AppShapes.radiusLg),
                                  border: Border.all(
                                      color: AppColors.borderLight, width: 1),
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.black.withOpacity(0.04),
                                      blurRadius: 16,
                                      offset: const Offset(0, 6),
                                    ),
                                  ],
                                ),
                                child: Form(
                                  key: _formKey,
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.stretch,
                                    children: [
                                      _buildLabel(l10n.translate('login_phone_number'), textTheme),
                                      const SizedBox(height: AppSpacing.xs),
                                      _buildInput(
                                        controller: _phoneController,
                                        hint: l10n.translate('login_phone_hint'),
                                        icon: Icons.phone_android_rounded,
                                        keyboardType: TextInputType.phone,
                                        onChanged: (_) => _clearError(),
                                        validator: (v) =>
                                            (v == null || v.isEmpty)
                                                ? l10n.translate('login_enter_phone')
                                                : null,
                                      ),
                                      SizedBox(height: screenHeight * 0.022),

                                      _buildLabel(l10n.translate('login_password'), textTheme),
                                      const SizedBox(height: AppSpacing.xs),
                                      _buildInput(
                                        controller: _passwordController,
                                        hint: l10n.translate('login_password_hint'),
                                        icon: Icons.lock_outline_rounded,
                                        obscure: _obscurePassword,
                                        onChanged: (_) => _clearError(),
                                        suffix: IconButton(
                                          icon: AnimatedSwitcher(
                                            duration: const Duration(
                                                milliseconds: 200),
                                            child: Icon(
                                              _obscurePassword
                                                  ? Icons
                                                      .visibility_off_rounded
                                                  : Icons
                                                      .visibility_rounded,
                                              key: ValueKey(
                                                  _obscurePassword),
                                              color: AppColors.textMuted,
                                              size: 20,
                                            ),
                                          ),
                                          onPressed: () => setState(() =>
                                              _obscurePassword =
                                                  !_obscurePassword),
                                          splashRadius: 18,
                                        ),
                                        validator: (v) =>
                                            v == null || v.isEmpty
                                                ? l10n.translate('login_enter_password')
                                                : null,
                                      ),
                                      SizedBox(height: screenHeight * 0.012),

                                      // Forgot password
                                      Align(
                                        alignment: Alignment.centerRight,
                                        child: TextButton(
                                          onPressed: () {
                                            Navigator.push(
                                              context,
                                              MaterialPageRoute(
                                                builder: (_) => ForgotPasswordScreen(
                                                  phone: _phoneController.text.trim().isNotEmpty
                                                      ? _phoneController.text.trim()
                                                      : null,
                                                ),
                                              ),
                                            );
                                          },
                                          style: TextButton.styleFrom(
                                            padding: EdgeInsets.zero,
                                            minimumSize: const Size(0, 0),
                                            tapTargetSize:
                                                MaterialTapTargetSize.shrinkWrap,
                                            foregroundColor:
                                                AppColors.textMuted,
                                          ),
                                          child: Text(
                                            l10n.translate('login_forgot_password'),
                                            style: textTheme.bodySmall?.copyWith(
                                              color: AppColors.textMuted,
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                        ),
                                      ),

                                      // ★ Inline error message
                                      if (_errorText != null) ...[
                                        const SizedBox(height: 12),
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                                          decoration: BoxDecoration(
                                            color: AppColors.error.withOpacity(0.08),
                                            borderRadius: BorderRadius.circular(AppShapes.radiusSm),
                                          ),
                                          child: Row(
                                            children: [
                                              Icon(Icons.error_outline_rounded,
                                                  color: AppColors.error, size: 18),
                                              const SizedBox(width: 8),
                                              Expanded(
                                                child: Text(
                                                  _errorText!,
                                                  style: TextStyle(color: AppColors.error, fontSize: 13),
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ],

                                      SizedBox(height: screenHeight * 0.028),

                                      SizedBox(
                                        height: 48,
                                        child: ElevatedButton(
                                          onPressed: _isLoading ? null : _login,
                                          style: AppComponentStyles.primaryButton.copyWith(
                                            shape: WidgetStatePropertyAll(
                                              RoundedRectangleBorder(
                                                borderRadius: BorderRadius.circular(AppShapes.radiusMd),
                                              ),
                                            ),
                                          ),
                                          child: _isLoading
                                              ? const SizedBox(height: 22, width: 22, child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white))
                                              : Text(l10n.translate('login_sign_in'), style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),

                              SizedBox(height: screenHeight * 0.032),

                              Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Flexible(
                                    child: Text(
                                      l10n.translate('login_dont_have_account'),
                                      style: textTheme.bodyMedium?.copyWith(
                                        color: AppColors.textMuted,
                                        fontWeight: FontWeight.w500,
                                      ),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                  Material(
                                    color: Colors.transparent,
                                    child: InkWell(
                                      onTap: () => Navigator.push(
                                        context,
                                        MaterialPageRoute(
                                            builder: (_) =>
                                                const RegisterScreen()),
                                      ),
                                      borderRadius:
                                          BorderRadius.circular(8),
                                      splashColor: AppColors.primary
                                          .withOpacity(0.1),
                                      highlightColor: AppColors.primary
                                          .withOpacity(0.05),
                                      child: Padding(
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 6, vertical: 4),
                                        child: Text(
                                          l10n.translate('login_sign_up'),
                                          style: const TextStyle(
                                            color: AppColors.primary,
                                            fontWeight: FontWeight.w700,
                                            fontSize: 14,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),

                              SizedBox(height: screenHeight * 0.03),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildLabel(String text, TextTheme textTheme) {
    return Padding(
      padding: const EdgeInsets.only(left: 2),
      child: Text(
        text,
        style: textTheme.bodyMedium?.copyWith(
          fontWeight: FontWeight.w700,
          color: AppColors.textPrimary,
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
    ValueChanged<String>? onChanged,
    String? Function(String?)? validator,
  }) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppShapes.radiusMd),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.03),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AppShapes.radiusMd),
        child: Container(
          decoration: BoxDecoration(
            color: AppColors.hoverState,
            border: Border.all(color: AppColors.borderLight, width: 1),
            borderRadius: BorderRadius.circular(AppShapes.radiusMd),
          ),
          child: TextFormField(
            controller: controller,
            obscureText: obscure,
            keyboardType: keyboardType,
            style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: AppColors.textPrimary,
                ),
            cursorColor: AppColors.primary,
            cursorWidth: 1.8,
            cursorRadius: const Radius.circular(2),
            onChanged: onChanged,
            decoration: InputDecoration(
              hintText: hint,
              hintStyle: Theme.of(context)
                  .textTheme
                  .bodyLarge
                  ?.copyWith(color: AppColors.textMuted, fontWeight: FontWeight.w400),
              prefixIcon: Container(
                margin: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppColors.primary.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(AppShapes.radiusSm),
                ),
                child: Icon(icon, color: AppColors.primary, size: 22),
              ),
              suffixIcon: suffix,
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
              border: InputBorder.none,
              enabledBorder: InputBorder.none,
              focusedBorder: InputBorder.none,
              errorBorder: InputBorder.none,
              focusedErrorBorder: InputBorder.none,
            ),
            validator: validator,
          ),
        ),
      ),
    );
  }
}
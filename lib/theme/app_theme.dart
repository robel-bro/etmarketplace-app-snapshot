// lib/theme/app_theme.dart
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

// ============================================================
// 1. COLOR TOKENS – high contrast, exactly web spec
// ============================================================
class AppColors {
  // Primary Brand Orange
  static const Color primary = Color(0xFFF97519);
  static const Color primaryHover = Color(0xFFE86A12);
  static const Color primaryActive = Color(0xFFCC5A0F);
  static const Color primaryLight = Color(0xFFFFF1E8);

  // Text
  static const Color textPrimary = Color(0xFF111827);
  static const Color textSecondary = Color(0xFF374151);
  static const Color textMuted = Color(0xFF6B7280);

  // Backgrounds
  static const Color pageBackground = Color(0xFFFFFFFF);           // pure white (global)
  static const Color productListBackground = Color(0xFFF5F5F5);   // light grey for product grids
  static const Color cardBackground = Color(0xFFFFFFFF);           // white cards
  static const Color hoverState = Color(0xFFF9FAFB);

  // Borders
  static const Color borderLight = Color(0xFFE5E7EB);
  static const Color borderMedium = Color(0xFFD1D5DB);

  // Semantic
  static const Color success = Color(0xFF22C55E);
  static const Color error = Color(0xFFEF4444);
  static const Color warning = Color(0xFFF59E0B);
  static const Color info = Color(0xFF3B82F6);

  // Star
  static const Color starGold = Color(0xFFF5A623);

  // Pure
  static const Color white = Colors.white;
  static const Color black = Colors.black;
}

// ============================================================
// 2. TYPOGRAPHY SCALE – dense, highly legible
// ============================================================
class AppTextStyles {
  static const TextStyle sectionTitle = TextStyle(
    fontSize: 24,
    fontWeight: FontWeight.w700,
    color: AppColors.textPrimary,
    height: 1.2,
  );

  static const TextStyle cardTitle = TextStyle(
    fontSize: 13,
    fontWeight: FontWeight.w600,
    color: AppColors.textPrimary,
    height: 1.2,
  );

  static const TextStyle cardPrice = TextStyle(
    fontSize: 16,
    fontWeight: FontWeight.w700,
    color: AppColors.textPrimary,
    letterSpacing: -0.3,
    height: 1.2,
  );

  static const TextStyle cardMeta = TextStyle(
    fontSize: 11,
    fontWeight: FontWeight.w500,
    color: AppColors.textSecondary,
    height: 1.2,
  );

  static const TextStyle body = TextStyle(
    fontSize: 15,
    fontWeight: FontWeight.w500,
    color: AppColors.textPrimary,
    height: 1.5,
  );

  static const TextStyle buttonLabel = TextStyle(
    fontSize: 14,
    fontWeight: FontWeight.w600,
    letterSpacing: 0.2,
  );
}

// ============================================================
// 3. SPACING GRID (4px base – 1 unit = 4px)
// ============================================================
class AppSpacing {
  static const double xxs = 2;
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 24;
  static const double xxl = 32;

  static const double screenHorizontal = 8;
  static const double screenVertical = 12;
}

// ============================================================
// 4. SHAPES – crisp, no decorative fluff
// ============================================================
class AppShapes {
  static const double radiusSm = 4;
  static const double radiusMd = 6;
  static const double radiusLg = 8;
  static const double radiusFull = 999;
}

// ============================================================
// 5. COMPONENT STYLES
// ============================================================
class AppComponentStyles {
  static ButtonStyle primaryButton = ElevatedButton.styleFrom(
    backgroundColor: AppColors.primary,
    foregroundColor: AppColors.white,
    elevation: 0,
    padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.xs),
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(AppShapes.radiusSm),
    ),
    textStyle: AppTextStyles.buttonLabel,
    minimumSize: const Size(0, 40),
  );

  static ButtonStyle secondaryButton = OutlinedButton.styleFrom(
    backgroundColor: AppColors.cardBackground,
    foregroundColor: AppColors.textPrimary,
    elevation: 0,
    padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.xs),
    side: const BorderSide(color: AppColors.borderLight, width: 1),
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(AppShapes.radiusSm),
    ),
    textStyle: AppTextStyles.buttonLabel.copyWith(color: AppColors.textPrimary),
    minimumSize: const Size(0, 40),
  );
}

// ============================================================
// 6. LIGHT THEME BUILDER
// ============================================================
ThemeData buildAppTheme() {
  final interTextTheme = GoogleFonts.interTextTheme();

  return ThemeData(
    useMaterial3: true,
    brightness: Brightness.light,

    scaffoldBackgroundColor: AppColors.pageBackground,   // white global

    colorScheme: const ColorScheme.light(
      primary: AppColors.primary,
      onPrimary: AppColors.white,
      secondary: AppColors.primaryLight,
      onSecondary: AppColors.textPrimary,
      surface: AppColors.cardBackground,
      onSurface: AppColors.textPrimary,
      error: AppColors.error,
      background: AppColors.pageBackground,
      onBackground: AppColors.textPrimary,
    ),

    appBarTheme: const AppBarTheme(
      backgroundColor: AppColors.cardBackground,
      foregroundColor: AppColors.textPrimary,
      elevation: 0,
      scrolledUnderElevation: 0.5,
      centerTitle: false,
      titleTextStyle: TextStyle(
        fontSize: 18,
        fontWeight: FontWeight.w600,
        color: AppColors.textPrimary,
      ),
      iconTheme: IconThemeData(color: AppColors.textPrimary, size: 22),
    ),

    bottomNavigationBarTheme: const BottomNavigationBarThemeData(
      backgroundColor: AppColors.cardBackground,
      selectedItemColor: AppColors.primary,
      unselectedItemColor: AppColors.textSecondary,
      type: BottomNavigationBarType.fixed,
      elevation: 0,
      selectedLabelStyle: TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
      unselectedLabelStyle: TextStyle(fontSize: 11, fontWeight: FontWeight.w500),
    ),

    cardTheme: CardThemeData(
      color: AppColors.cardBackground,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppShapes.radiusSm),
      ),
      margin: EdgeInsets.zero,
    ),

    textTheme: interTextTheme.copyWith(
      displayLarge: AppTextStyles.sectionTitle,
      headlineMedium: AppTextStyles.cardTitle,
      titleMedium: AppTextStyles.cardPrice,
      bodyLarge: AppTextStyles.body,
      bodyMedium: AppTextStyles.body.copyWith(fontSize: 14, fontWeight: FontWeight.w400),
      bodySmall: AppTextStyles.cardMeta,
      labelMedium: AppTextStyles.cardMeta,
      labelLarge: AppTextStyles.buttonLabel,
    ),

    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: AppColors.cardBackground,
      contentPadding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: AppSpacing.xs,
      ),
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
        borderSide: const BorderSide(color: AppColors.primary, width: 1.5),
      ),
      hintStyle: AppTextStyles.cardMeta,
    ),

    iconTheme: const IconThemeData(color: AppColors.textSecondary, size: 20),

    dividerTheme: const DividerThemeData(
      color: AppColors.borderLight,
      thickness: 1,
      space: 1,
    ),
  );
}
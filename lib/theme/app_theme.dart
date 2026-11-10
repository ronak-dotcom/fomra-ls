import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class AppColors {
  // ── Brand ── Fomra blue (#3B82F6) ────────────────────────────────────────────
  static const Color primary      = Color(0xFF3B82F6);
  static const Color primaryLight = Color(0xFF60A5FA);
  static const Color primaryDark  = Color(0xFF2563EB);
  static const Color secondary    = Color(0xFF8B5CF6); // violet-500 (purple accent)
  static const Color accent       = Color(0xFF3B82F6);
  static const Color accentLight  = Color(0xFFFBBF24);
  static const Color purple       = Color(0xFF8B5CF6);
  static const Color cyan         = Color(0xFF06B6D4);

  // ── Surface (light) ─────────────────────────────────────────────────────────
  static const Color background   = Color(0xFFF8FAFC); // slate-50
  static const Color surface      = Color(0xFFFFFFFF);
  static const Color surfaceVar   = Color(0xFFF1F5F9); // slate-100
  static const Color border       = Color(0xFFE2E8F0); // slate-200

  // ── Text (light) ─────────────────────────────────────────────────────────────
  // One slate family (matching the slate surfaces), each step readable on
  // white: secondary 7.6:1, tertiary 4.8:1 — the old gray-400 tertiary
  // (2.5:1) used for field labels was below the 4.5:1 minimum.
  static const Color textPrimary   = Color(0xFF0F172A); // slate-900
  static const Color textSecondary = Color(0xFF475569); // slate-600
  static const Color textTertiary  = Color(0xFF64748B); // slate-500

  // ── Dark surfaces (enterprise dashboard) ──────────────────────────────────────
  static const Color darkBackground    = Color(0xFF0B1220);
  static const Color darkBackgroundEnd = Color(0xFF111827);
  static const Color darkSurface       = Color(0xFF161B22);
  static const Color darkSurfaceVar    = Color(0xFF1C2128);
  static const Color darkBorder        = Color(0xFF2A3441);
  static const Color darkDivider       = Color(0xFF263241);
  static const Color sidebarDark       = Color(0xFF0F172A);
  static const Color darkNavBar        = Color(0xCC0F172A); // 80% matte nav
  static const Color darkTextPrimary   = Color(0xFFF8FAFC);
  static const Color darkTextSecondary = Color(0xFF94A3B8);
  // Lifted from slate-500 (3.2:1 on dark cards) to clear 4.5:1.
  static const Color darkTextTertiary  = Color(0xFF7C8AA0);

  /// Subtle modal scrim for centered dialogs — lighter than Flutter's default black54.
  static const Color modalScrim = Color(0x40000000); // black @ 25%

  // ── Semantic ─────────────────────────────────────────────────────────────────
  static const Color success = Color(0xFF10B981); // emerald-500
  static const Color warning = Color(0xFFF59E0B); // amber-500
  static const Color error   = Color(0xFFEF4444); // red-500
  static const Color info    = Color(0xFF3B82F6);

  // ── Gradients ────────────────────────────────────────────────────────────────
  static const LinearGradient primaryGradient = LinearGradient(
    colors: [Color(0xFF3B82F6), Color(0xFF2563EB)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  /// Header / hero surfaces — blue gradient for light chrome.
  static const LinearGradient heroGradient = primaryGradient;

  /// Deep charcoal page background for dark dashboard.
  static const LinearGradient darkPageGradient = LinearGradient(
    colors: [darkBackground, darkBackgroundEnd],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  /// Subtle dark navbar wash (used under backdrop blur).
  static const LinearGradient darkNavGradient = LinearGradient(
    colors: [Color(0xE60F172A), Color(0xD9111827)],
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
  );

  // ── Radius tokens ───────────────────────────────────────────────────────────
  static const double radiusXs = 12; // chips, small controls
  static const double radiusSm = 16; // buttons, inputs
  static const double radiusMd = 20; // cards
  static const double radiusLg = 24; // large cards, bottom sheets
  static const double radiusXl = 28; // hero surfaces

  // ── Shadow tokens ─────────────────────────────────────────────────────────────
  // Light cards: a soft, close shadow. The previous 28px blur pushed 10px down
  // left a grey band under every card that read as a double border.
  static const List<BoxShadow> cardShadow = [
    BoxShadow(color: Color(0x0F0F172A), blurRadius: 12, offset: Offset(0, 3)),
    BoxShadow(color: Color(0x0A0F172A), blurRadius: 2,  offset: Offset(0, 1)),
  ];

  static const List<BoxShadow> elevatedShadow = [
    BoxShadow(color: Color(0x1A0F172A), blurRadius: 24, offset: Offset(0, 10)),
    BoxShadow(color: Color(0x0D0F172A), blurRadius: 6,  offset: Offset(0, 2)),
  ];

  /// Soft elevation for dark cards — no heavy glows.
  static const List<BoxShadow> darkCardShadow = [
    BoxShadow(color: Color(0x40000000), blurRadius: 16, offset: Offset(0, 4)),
    BoxShadow(color: Color(0x1A000000), blurRadius: 4,  offset: Offset(0, 1)),
  ];

  static const List<BoxShadow> darkElevatedShadow = [
    BoxShadow(color: Color(0x50000000), blurRadius: 24, offset: Offset(0, 8)),
    BoxShadow(color: Color(0x26000000), blurRadius: 8,  offset: Offset(0, 2)),
  ];

  static List<BoxShadow> coloredShadow(Color color) => [
    BoxShadow(color: color.withValues(alpha: 0.22), blurRadius: 14, offset: const Offset(0, 5)),
    BoxShadow(color: color.withValues(alpha: 0.10), blurRadius: 4,  offset: const Offset(0, 1)),
  ];
}

/// Spacing scale from the design brief: 4 · 8 · 12 · 16 · 24 · 32 · 48.
/// Use these instead of magic numbers so gaps stay consistent app-wide.
class AppSpacing {
  const AppSpacing._();
  static const double xxs = 4;
  static const double xs  = 8;
  static const double sm  = 12;
  static const double md  = 16;
  static const double lg  = 24;
  static const double xl  = 32;
  static const double xxl = 48;

  // Ready-made SizedBox gaps for column/row layouts.
  static const SizedBox gapXxs = SizedBox(height: xxs, width: xxs);
  static const SizedBox gapXs  = SizedBox(height: xs,  width: xs);
  static const SizedBox gapSm  = SizedBox(height: sm,  width: sm);
  static const SizedBox gapMd  = SizedBox(height: md,  width: md);
  static const SizedBox gapLg  = SizedBox(height: lg,  width: lg);
  static const SizedBox gapXl  = SizedBox(height: xl,  width: xl);
}

/// Consistent icon sizing from the brief: primary 28 · secondary 22 · small 18.
class AppIconSize {
  const AppIconSize._();
  static const double primary   = 28;
  static const double secondary = 22;
  static const double small     = 18;
}

/// Motion tokens — brief calls for 150–250ms with easing.
class AppMotion {
  const AppMotion._();
  static const Duration fast   = Duration(milliseconds: 150);
  static const Duration normal = Duration(milliseconds: 200);
  static const Duration slow   = Duration(milliseconds: 250);
  static const Curve curve     = Curves.easeOutCubic;
}

const _fontFamily = 'Inter';

TextTheme _textTheme({
  required Color primary,
  required Color secondary,
  required Color tertiary,
}) =>
    TextTheme(
      displayLarge:  TextStyle(fontSize: 42, fontWeight: FontWeight.w800, letterSpacing: -1.4, height: 1.08, color: primary),
      displayMedium: TextStyle(fontSize: 34, fontWeight: FontWeight.w800, letterSpacing: -0.9, height: 1.12, color: primary),
      headlineLarge: TextStyle(fontSize: 28, fontWeight: FontWeight.w800, letterSpacing: -0.6, height: 1.18, color: primary),
      headlineMedium:TextStyle(fontSize: 23, fontWeight: FontWeight.w700, letterSpacing: -0.4, height: 1.22, color: primary),
      titleLarge:    TextStyle(fontSize: 19, fontWeight: FontWeight.w700, letterSpacing: -0.2, height: 1.28, color: primary),
      titleMedium:   TextStyle(fontSize: 15, fontWeight: FontWeight.w600, letterSpacing: 0.0,  height: 1.35, color: primary),
      titleSmall:    TextStyle(fontSize: 13, fontWeight: FontWeight.w600, letterSpacing: 0.1,  height: 1.35, color: primary),
      bodyLarge:     TextStyle(fontSize: 15, fontWeight: FontWeight.w400, letterSpacing: 0.0,  height: 1.55, color: primary),
      bodyMedium:    TextStyle(fontSize: 15, fontWeight: FontWeight.w400, letterSpacing: 0.0,  height: 1.55, color: secondary),
      bodySmall:     TextStyle(fontSize: 13, fontWeight: FontWeight.w400, letterSpacing: 0.0,  height: 1.5,  color: secondary),
      labelLarge:    TextStyle(fontSize: 14, fontWeight: FontWeight.w600, letterSpacing: 0.1,  color: primary),
      labelMedium:   TextStyle(fontSize: 11, fontWeight: FontWeight.w500, letterSpacing: 0.4,  color: secondary),
      labelSmall:    TextStyle(fontSize: 10, fontWeight: FontWeight.w500, letterSpacing: 0.5,  color: tertiary),
    );

ThemeData appTheme() {
  const fontFamily = _fontFamily;

  final textTheme = _textTheme(
    primary: AppColors.textPrimary,
    secondary: AppColors.textSecondary,
    tertiary: AppColors.textTertiary,
  );

  return ThemeData(
    useMaterial3: true,
    fontFamily: fontFamily,
    textTheme: textTheme,
    colorScheme: ColorScheme.fromSeed(
      seedColor: AppColors.primary,
      primary:   AppColors.primary,
      secondary: AppColors.secondary,
      tertiary:  AppColors.accent,
      surface:   AppColors.surface,
      error:     AppColors.error,
    ),
    scaffoldBackgroundColor: AppColors.background,
    appBarTheme: const AppBarTheme(
      backgroundColor: Colors.transparent,
      foregroundColor: Colors.white,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      systemOverlayStyle: SystemUiOverlayStyle.light,
      titleTextStyle: TextStyle(
        fontFamily: fontFamily,
        color: Colors.white,
        fontSize: 18,
        fontWeight: FontWeight.w700,
        letterSpacing: 0.1,
      ),
      iconTheme: IconThemeData(color: Colors.white),
    ),
    drawerTheme: const DrawerThemeData(backgroundColor: AppColors.primary),
    cardTheme: CardThemeData(
      color: AppColors.surface,
      elevation: 0,
      shadowColor: Colors.transparent,
      surfaceTintColor: Colors.transparent,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppColors.radiusMd),
        side: const BorderSide(color: AppColors.border, width: 1),
      ),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        elevation: 0,
        shadowColor: Colors.transparent,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppColors.radiusSm)),
        padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
        textStyle: const TextStyle(
            fontFamily: fontFamily,
            fontSize: 14,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.1),
      ),
    ),
    // FilledButton had no theme, so in dark mode Material derived a dark
    // label colour for the blue fill (grey "Create Task" text). Match the
    // elevated button: white text, same size and shape.
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppColors.radiusSm)),
        textStyle: const TextStyle(
            fontFamily: fontFamily,
            fontSize: 14,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.1),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: AppColors.primary,
        side: const BorderSide(color: AppColors.primary, width: 1.2),
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppColors.radiusSm)),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 13),
        textStyle: const TextStyle(
            fontFamily: fontFamily,
            fontSize: 14,
            fontWeight: FontWeight.w700),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: AppColors.primary,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        textStyle: const TextStyle(
            fontFamily: fontFamily,
            fontSize: 14,
            fontWeight: FontWeight.w600),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: AppColors.surface,
      isDense: true,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: AppColors.border),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: AppColors.border),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: AppColors.primary, width: 2),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: AppColors.error),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: AppColors.error, width: 2),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      hintStyle: const TextStyle(
          fontFamily: fontFamily,
          color: AppColors.textTertiary,
          fontSize: 14),
      labelStyle: const TextStyle(
          fontFamily: fontFamily,
          color: AppColors.textSecondary,
          fontSize: 14),
    ),
    chipTheme: ChipThemeData(
      // Colour is required: without it a chip whose label sets no colour
      // paints white, invisible on light surfaces.
      labelStyle: const TextStyle(
          fontFamily: fontFamily,
          fontSize: 12,
          fontWeight: FontWeight.w500,
          color: AppColors.textPrimary),
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppColors.radiusXs)),
      side: const BorderSide(color: AppColors.border),
    ),
    tabBarTheme: const TabBarThemeData(
      indicatorSize: TabBarIndicatorSize.tab,
      labelStyle: TextStyle(
          fontFamily: fontFamily,
          fontSize: 13,
          fontWeight: FontWeight.w600),
      unselectedLabelStyle: TextStyle(
          fontFamily: fontFamily,
          fontSize: 13,
          fontWeight: FontWeight.w400),
    ),
    floatingActionButtonTheme: FloatingActionButtonThemeData(
      backgroundColor: AppColors.primary,
      foregroundColor: Colors.white,
      elevation: 4,
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppColors.radiusMd)),
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: AppColors.textPrimary,
      contentTextStyle: const TextStyle(
          fontFamily: fontFamily,
          color: Colors.white,
          fontSize: 14),
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppColors.radiusSm)),
      behavior: SnackBarBehavior.floating,
    ),
    dividerTheme: const DividerThemeData(
        color: AppColors.border, thickness: 1, space: 1),
    listTileTheme: const ListTileThemeData(
      contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 4),
    ),
  );
}

ThemeData appThemeDark() {
  const fontFamily = _fontFamily;

  final textTheme = _textTheme(
    primary: AppColors.darkTextPrimary,
    secondary: AppColors.darkTextSecondary,
    tertiary: AppColors.darkTextTertiary,
  );

  return ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    fontFamily: fontFamily,
    textTheme: textTheme,
    colorScheme: ColorScheme.fromSeed(
      seedColor: AppColors.primary,
      brightness: Brightness.dark,
      primary:   AppColors.primary,
      secondary: AppColors.secondary,
      tertiary:  AppColors.accent,
      surface:   AppColors.darkSurface,
      onSurface: AppColors.darkTextPrimary,
      error:     AppColors.error,
    ),
    scaffoldBackgroundColor: AppColors.darkBackground,
    appBarTheme: const AppBarTheme(
      backgroundColor: Colors.transparent,
      foregroundColor: AppColors.darkTextPrimary,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      systemOverlayStyle: SystemUiOverlayStyle.light,
      titleTextStyle: TextStyle(
        fontFamily: fontFamily,
        color: AppColors.darkTextPrimary,
        fontSize: 18,
        fontWeight: FontWeight.w700,
        letterSpacing: 0.1,
      ),
      iconTheme: IconThemeData(color: AppColors.darkTextPrimary),
    ),
    drawerTheme: const DrawerThemeData(backgroundColor: AppColors.sidebarDark),
    cardTheme: CardThemeData(
      color: AppColors.darkSurface,
      elevation: 0,
      shadowColor: Colors.transparent,
      surfaceTintColor: Colors.transparent,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppColors.radiusMd),
        side: const BorderSide(color: AppColors.darkBorder, width: 1),
      ),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        elevation: 0,
        shadowColor: Colors.transparent,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppColors.radiusSm)),
        padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
        textStyle: const TextStyle(
            fontFamily: fontFamily,
            fontSize: 14,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.1),
      ),
    ),
    // FilledButton had no theme, so in dark mode Material derived a dark
    // label colour for the blue fill (grey "Create Task" text). Match the
    // elevated button: white text, same size and shape.
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppColors.radiusSm)),
        textStyle: const TextStyle(
            fontFamily: fontFamily,
            fontSize: 14,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.1),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: AppColors.primary,
        side: const BorderSide(color: AppColors.primary, width: 1.2),
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppColors.radiusSm)),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 13),
        textStyle: const TextStyle(
            fontFamily: fontFamily,
            fontSize: 14,
            fontWeight: FontWeight.w700),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: AppColors.primary,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        textStyle: const TextStyle(
            fontFamily: fontFamily,
            fontSize: 14,
            fontWeight: FontWeight.w600),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: AppColors.darkSurfaceVar,
      isDense: true,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: AppColors.darkBorder),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: AppColors.darkBorder),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: AppColors.primary, width: 2),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: AppColors.error),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: AppColors.error, width: 2),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      hintStyle: const TextStyle(
          fontFamily: fontFamily,
          color: AppColors.darkTextTertiary,
          fontSize: 14),
      labelStyle: const TextStyle(
          fontFamily: fontFamily,
          color: AppColors.darkTextSecondary,
          fontSize: 14),
    ),
    chipTheme: ChipThemeData(
      labelStyle: const TextStyle(
          fontFamily: fontFamily,
          fontSize: 12,
          fontWeight: FontWeight.w500,
          color: AppColors.darkTextPrimary),
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppColors.radiusXs)),
      side: const BorderSide(color: AppColors.darkBorder),
    ),
    tabBarTheme: const TabBarThemeData(
      indicatorSize: TabBarIndicatorSize.tab,
      labelStyle: TextStyle(
          fontFamily: fontFamily,
          fontSize: 13,
          fontWeight: FontWeight.w600),
      unselectedLabelStyle: TextStyle(
          fontFamily: fontFamily,
          fontSize: 13,
          fontWeight: FontWeight.w400),
    ),
    floatingActionButtonTheme: FloatingActionButtonThemeData(
      backgroundColor: AppColors.primary,
      foregroundColor: Colors.white,
      elevation: 4,
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppColors.radiusMd)),
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: AppColors.darkSurface,
      contentTextStyle: const TextStyle(
          fontFamily: fontFamily,
          color: AppColors.darkTextPrimary,
          fontSize: 14),
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppColors.radiusSm)),
      behavior: SnackBarBehavior.floating,
    ),
    dividerTheme: const DividerThemeData(
        color: AppColors.darkDivider, thickness: 1, space: 1),
    listTileTheme: const ListTileThemeData(
      contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 4),
    ),
  );
}

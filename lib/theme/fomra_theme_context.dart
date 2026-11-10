import 'package:flutter/material.dart';
import 'app_theme.dart';

/// Theme-aware colors for screens that previously hard-coded light palette.
extension FomraThemeContext on BuildContext {
  bool get isDarkMode => Theme.of(this).brightness == Brightness.dark;

  Color get fomraPageBg =>
      isDarkMode ? AppColors.darkBackground : AppColors.background;

  /// Optional full-page gradient (dark dashboard background).
  LinearGradient? get fomraPageGradient =>
      isDarkMode ? AppColors.darkPageGradient : null;

  Color get fomraSurface =>
      isDarkMode ? AppColors.darkSurface : AppColors.surface;

  Color get fomraSurfaceVar =>
      isDarkMode ? AppColors.darkSurfaceVar : AppColors.surfaceVar;

  Color get fomraBorder =>
      isDarkMode ? AppColors.darkBorder : AppColors.border;

  Color get fomraDivider =>
      isDarkMode ? AppColors.darkDivider : AppColors.border;

  Color get fomraTextPrimary =>
      isDarkMode ? AppColors.darkTextPrimary : AppColors.textPrimary;

  Color get fomraTextSecondary =>
      isDarkMode ? AppColors.darkTextSecondary : AppColors.textSecondary;

  Color get fomraTextTertiary =>
      isDarkMode ? AppColors.darkTextTertiary : AppColors.textTertiary;

  List<BoxShadow> get fomraCardShadow =>
      isDarkMode ? AppColors.darkCardShadow : AppColors.cardShadow;

  List<BoxShadow> get fomraElevatedShadow =>
      isDarkMode ? AppColors.darkElevatedShadow : AppColors.elevatedShadow;

  Color get fomraHoverBg =>
      isDarkMode ? const Color(0xFF2C2C2E) : const Color(0xFFF5F5F7);

  Color get fomraIconChipBg =>
      isDarkMode ? const Color(0xFF2C2C2E) : const Color(0xFFF2F2F5);

  Color get fomraSidebarBg =>
      isDarkMode ? AppColors.sidebarDark : AppColors.ink;

  /// App bar / header chrome — ink black in light, dark wash in dark mode.
  LinearGradient get fomraHeroGradient =>
      isDarkMode ? AppColors.darkNavGradient : AppColors.heroGradient;
}

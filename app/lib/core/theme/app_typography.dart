import 'package:flutter/material.dart';

import '../locale/app_locale.dart';
import 'app_colors.dart';

abstract final class AppTypography {
  static const TextTheme _englishTextTheme = TextTheme(
    displayMedium: TextStyle(
      fontFamily: 'SpaceGrotesk',
      fontSize: 40,
      fontWeight: FontWeight.w700,
      height: 1.05,
      letterSpacing: -1.2,
      color: AppColors.onSurface,
    ),
    displaySmall: TextStyle(
      fontFamily: 'SpaceGrotesk',
      fontSize: 32,
      fontWeight: FontWeight.w700,
      height: 1.1,
      letterSpacing: -0.8,
      color: AppColors.onSurface,
    ),
    headlineLarge: TextStyle(
      fontFamily: 'SpaceGrotesk',
      fontSize: 28,
      fontWeight: FontWeight.w700,
      height: 1.15,
      letterSpacing: -0.6,
      color: AppColors.onSurface,
    ),
    headlineMedium: TextStyle(
      fontFamily: 'SpaceGrotesk',
      fontSize: 22,
      fontWeight: FontWeight.w700,
      height: 1.15,
      letterSpacing: -0.3,
      color: AppColors.onSurface,
    ),
    headlineSmall: TextStyle(
      fontFamily: 'SpaceGrotesk',
      fontSize: 20,
      fontWeight: FontWeight.w600,
      height: 1.16,
      letterSpacing: -0.2,
      color: AppColors.onSurface,
    ),
    titleLarge: TextStyle(
      fontFamily: 'SpaceGrotesk',
      fontSize: 18,
      fontWeight: FontWeight.w700,
      height: 1.2,
      color: AppColors.onSurface,
    ),
    titleMedium: TextStyle(
      fontFamily: 'SpaceGrotesk',
      fontSize: 16,
      fontWeight: FontWeight.w600,
      height: 1.25,
      color: AppColors.onSurface,
    ),
    titleSmall: TextStyle(
      fontFamily: 'Inter',
      fontSize: 14,
      fontWeight: FontWeight.w600,
      height: 1.28,
      color: AppColors.onSurface,
    ),
    bodyLarge: TextStyle(
      fontFamily: 'Inter',
      fontSize: 16,
      fontWeight: FontWeight.w400,
      height: 1.5,
      color: AppColors.onSurface,
    ),
    bodyMedium: TextStyle(
      fontFamily: 'Inter',
      fontSize: 14,
      fontWeight: FontWeight.w400,
      height: 1.45,
      color: AppColors.onSurfaceMuted,
    ),
    bodySmall: TextStyle(
      fontFamily: 'Inter',
      fontSize: 12,
      fontWeight: FontWeight.w400,
      height: 1.42,
      color: AppColors.onSurfaceMuted,
    ),
    labelLarge: TextStyle(
      fontFamily: 'Inter',
      fontSize: 13,
      fontWeight: FontWeight.w600,
      height: 1.2,
      letterSpacing: 0.3,
      color: AppColors.onSurface,
    ),
    labelMedium: TextStyle(
      fontFamily: 'Inter',
      fontSize: 11,
      fontWeight: FontWeight.w700,
      height: 1.1,
      letterSpacing: 1.2,
      color: AppColors.onSurfaceMuted,
    ),
    labelSmall: TextStyle(
      fontFamily: 'Inter',
      fontSize: 10,
      fontWeight: FontWeight.w700,
      height: 1.1,
      letterSpacing: 1.4,
      color: AppColors.onSurfaceMuted,
    ),
  );

  static TextTheme _eastAsianTextTheme([String? fontFamily]) {
    return TextTheme(
      displayMedium: TextStyle(
        fontFamily: fontFamily,
        fontSize: 36,
        fontWeight: FontWeight.w700,
        height: 1.12,
        color: AppColors.onSurface,
      ),
      displaySmall: TextStyle(
        fontFamily: fontFamily,
        fontSize: 30,
        fontWeight: FontWeight.w700,
        height: 1.14,
        color: AppColors.onSurface,
      ),
      headlineLarge: TextStyle(
        fontFamily: fontFamily,
        fontSize: 26,
        fontWeight: FontWeight.w700,
        height: 1.18,
        color: AppColors.onSurface,
      ),
      headlineMedium: TextStyle(
        fontFamily: fontFamily,
        fontSize: 22,
        fontWeight: FontWeight.w700,
        height: 1.2,
        color: AppColors.onSurface,
      ),
      headlineSmall: TextStyle(
        fontFamily: fontFamily,
        fontSize: 19,
        fontWeight: FontWeight.w600,
        height: 1.24,
        color: AppColors.onSurface,
      ),
      titleLarge: TextStyle(
        fontFamily: fontFamily,
        fontSize: 18,
        fontWeight: FontWeight.w700,
        height: 1.24,
        color: AppColors.onSurface,
      ),
      titleMedium: TextStyle(
        fontFamily: fontFamily,
        fontSize: 16,
        fontWeight: FontWeight.w600,
        height: 1.3,
        color: AppColors.onSurface,
      ),
      titleSmall: TextStyle(
        fontFamily: fontFamily,
        fontSize: 14,
        fontWeight: FontWeight.w600,
        height: 1.34,
        color: AppColors.onSurface,
      ),
      bodyLarge: TextStyle(
        fontFamily: fontFamily,
        fontSize: 16,
        fontWeight: FontWeight.w400,
        height: 1.56,
        color: AppColors.onSurface,
      ),
      bodyMedium: TextStyle(
        fontFamily: fontFamily,
        fontSize: 14,
        fontWeight: FontWeight.w400,
        height: 1.5,
        color: AppColors.onSurfaceMuted,
      ),
      bodySmall: TextStyle(
        fontFamily: fontFamily,
        fontSize: 12,
        fontWeight: FontWeight.w400,
        height: 1.46,
        color: AppColors.onSurfaceMuted,
      ),
      labelLarge: TextStyle(
        fontFamily: fontFamily,
        fontSize: 13,
        fontWeight: FontWeight.w600,
        height: 1.28,
        color: AppColors.onSurface,
      ),
      labelMedium: TextStyle(
        fontFamily: fontFamily,
        fontSize: 11,
        fontWeight: FontWeight.w600,
        height: 1.2,
        color: AppColors.onSurfaceMuted,
      ),
      labelSmall: TextStyle(
        fontFamily: fontFamily,
        fontSize: 10,
        fontWeight: FontWeight.w600,
        height: 1.18,
        color: AppColors.onSurfaceMuted,
      ),
    );
  }

  static const TextTheme _chineseTextTheme = TextTheme(
    displayMedium: TextStyle(
      fontFamily: 'NotoSansSC',
      fontSize: 36,
      fontWeight: FontWeight.w700,
      height: 1.12,
      color: AppColors.onSurface,
    ),
    displaySmall: TextStyle(
      fontFamily: 'NotoSansSC',
      fontSize: 30,
      fontWeight: FontWeight.w700,
      height: 1.14,
      color: AppColors.onSurface,
    ),
    headlineLarge: TextStyle(
      fontFamily: 'NotoSansSC',
      fontSize: 26,
      fontWeight: FontWeight.w700,
      height: 1.18,
      color: AppColors.onSurface,
    ),
    headlineMedium: TextStyle(
      fontFamily: 'NotoSansSC',
      fontSize: 22,
      fontWeight: FontWeight.w700,
      height: 1.2,
      color: AppColors.onSurface,
    ),
    headlineSmall: TextStyle(
      fontFamily: 'NotoSansSC',
      fontSize: 19,
      fontWeight: FontWeight.w600,
      height: 1.24,
      color: AppColors.onSurface,
    ),
    titleLarge: TextStyle(
      fontFamily: 'NotoSansSC',
      fontSize: 18,
      fontWeight: FontWeight.w700,
      height: 1.24,
      color: AppColors.onSurface,
    ),
    titleMedium: TextStyle(
      fontFamily: 'NotoSansSC',
      fontSize: 16,
      fontWeight: FontWeight.w600,
      height: 1.3,
      color: AppColors.onSurface,
    ),
    titleSmall: TextStyle(
      fontFamily: 'NotoSansSC',
      fontSize: 14,
      fontWeight: FontWeight.w600,
      height: 1.34,
      color: AppColors.onSurface,
    ),
    bodyLarge: TextStyle(
      fontFamily: 'NotoSansSC',
      fontSize: 16,
      fontWeight: FontWeight.w400,
      height: 1.56,
      color: AppColors.onSurface,
    ),
    bodyMedium: TextStyle(
      fontFamily: 'NotoSansSC',
      fontSize: 14,
      fontWeight: FontWeight.w400,
      height: 1.5,
      color: AppColors.onSurfaceMuted,
    ),
    bodySmall: TextStyle(
      fontFamily: 'NotoSansSC',
      fontSize: 12,
      fontWeight: FontWeight.w400,
      height: 1.46,
      color: AppColors.onSurfaceMuted,
    ),
    labelLarge: TextStyle(
      fontFamily: 'NotoSansSC',
      fontSize: 13,
      fontWeight: FontWeight.w600,
      height: 1.28,
      color: AppColors.onSurface,
    ),
    labelMedium: TextStyle(
      fontFamily: 'NotoSansSC',
      fontSize: 11,
      fontWeight: FontWeight.w600,
      height: 1.2,
      color: AppColors.onSurfaceMuted,
    ),
    labelSmall: TextStyle(
      fontFamily: 'NotoSansSC',
      fontSize: 10,
      fontWeight: FontWeight.w600,
      height: 1.18,
      color: AppColors.onSurfaceMuted,
    ),
  );

  static TextTheme textThemeFor(Locale locale) {
    if (isSimplifiedChineseLocale(locale)) {
      return _chineseTextTheme;
    }
    if (usesCjkTypographyLocale(locale)) {
      return _eastAsianTextTheme(appFontFamilyForLocale(locale));
    }
    return _englishTextTheme;
  }
}

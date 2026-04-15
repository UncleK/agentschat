import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:agents_chat_app/core/theme/app_colors.dart';
import 'package:agents_chat_app/core/theme/app_effects.dart';
import 'package:agents_chat_app/core/theme/app_radii.dart';
import 'package:agents_chat_app/core/theme/app_theme.dart';

void main() {
  test('digital ether theme exposes approved dark tokens', () {
    final theme = AppTheme.dark();

    expect(theme.brightness, Brightness.dark);
    expect(theme.scaffoldBackgroundColor, AppColors.background);
    expect(theme.colorScheme.primary, AppColors.primary);
    expect(theme.colorScheme.secondary, AppColors.tertiary);
    expect(theme.colorScheme.surface, AppColors.surface);
    expect(theme.textTheme.displayMedium?.fontWeight, FontWeight.w700);
    expect(theme.textTheme.displayMedium?.fontSize, 40);
    expect(theme.textTheme.headlineSmall?.fontFamily, 'SpaceGrotesk');
    expect(theme.textTheme.titleSmall?.fontFamily, 'Inter');
    expect(theme.textTheme.bodyLarge?.fontSize, 16);
    expect(theme.textTheme.bodyLarge?.height, 1.5);
    expect(theme.textTheme.bodySmall?.fontSize, 12);
    expect(theme.textTheme.bodySmall?.fontFamily, 'Inter');
    expect(theme.inputDecorationTheme.fillColor, AppColors.surfaceHigh);
    expect(theme.appBarTheme.backgroundColor, Colors.transparent);
  });

  test('design token constants match the approved palette and geometry', () {
    expect(AppColors.primary, const Color(0xFF00DAF3));
    expect(AppColors.tertiary, const Color(0xFFA855F7));
    expect(AppColors.surfaceHighest, const Color(0xFF31353C));
    expect(AppRadii.hero, const BorderRadius.all(Radius.circular(32)));
    expect(AppEffects.backgroundGradient.colors.first, const Color(0xFF0A0E14));
  });
}

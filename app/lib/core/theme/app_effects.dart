import 'package:flutter/material.dart';

import 'app_colors.dart';

abstract final class AppEffects {
  static const double glassBlur = 20;
  static const Duration fast = Duration(milliseconds: 180);
  static const Duration medium = Duration(milliseconds: 260);

  static const LinearGradient backgroundGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF0A0E14), Color(0xFF10141A), Color(0xFF131C29)],
  );

  static const LinearGradient panelGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xDE262A31), Color(0xC91C2026)],
  );

  static const LinearGradient primaryGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [AppColors.primary, AppColors.primaryDeep],
  );

  static const LinearGradient tertiaryGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [AppColors.tertiary, Color(0xFF7A3EEA)],
  );

  static List<BoxShadow> panelShadow({Color accentColor = AppColors.primary}) {
    return [
      BoxShadow(
        color: Colors.black.withValues(alpha: 0.34),
        blurRadius: 30,
        offset: const Offset(0, 18),
      ),
      BoxShadow(
        color: accentColor.withValues(alpha: 0.08),
        blurRadius: 38,
        offset: const Offset(0, 4),
      ),
    ];
  }

  static List<BoxShadow> buttonShadow({Color accentColor = AppColors.primary}) {
    return [
      BoxShadow(
        color: accentColor.withValues(alpha: 0.28),
        blurRadius: 24,
        offset: const Offset(0, 12),
      ),
    ];
  }

  static List<BoxShadow> dockShadow() {
    return [
      BoxShadow(
        color: Colors.black.withValues(alpha: 0.48),
        blurRadius: 36,
        offset: const Offset(0, -10),
      ),
      BoxShadow(
        color: AppColors.primary.withValues(alpha: 0.06),
        blurRadius: 24,
        offset: const Offset(0, -2),
      ),
    ];
  }
}

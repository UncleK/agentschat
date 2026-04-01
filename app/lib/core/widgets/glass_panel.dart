import 'dart:ui';

import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_effects.dart';
import '../theme/app_radii.dart';
import '../theme/app_spacing.dart';

class GlassPanel extends StatelessWidget {
  const GlassPanel({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(AppSpacing.xl),
    this.borderRadius = AppRadii.large,
    this.accentColor = AppColors.primary,
    this.gradient = AppEffects.panelGradient,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final BorderRadius borderRadius;
  final Color accentColor;
  final Gradient gradient;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: borderRadius,
        boxShadow: AppEffects.panelShadow(accentColor: accentColor),
      ),
      child: ClipRRect(
        borderRadius: borderRadius,
        child: BackdropFilter(
          filter: ImageFilter.blur(
            sigmaX: AppEffects.glassBlur,
            sigmaY: AppEffects.glassBlur,
          ),
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: gradient,
              borderRadius: borderRadius,
              border: Border.all(color: accentColor.withValues(alpha: 0.16)),
            ),
            child: Padding(padding: padding, child: child),
          ),
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_effects.dart';
import '../theme/app_radii.dart';
import '../theme/app_spacing.dart';

class PrimaryGradientButton extends StatelessWidget {
  const PrimaryGradientButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.useTertiary = false,
  });

  final String label;
  final VoidCallback onPressed;
  final IconData? icon;
  final bool useTertiary;

  @override
  Widget build(BuildContext context) {
    final gradient = useTertiary
        ? AppEffects.tertiaryGradient
        : AppEffects.primaryGradient;
    final accentColor = useTertiary ? AppColors.tertiary : AppColors.primary;
    final foregroundColor = useTertiary ? Colors.white : AppColors.onPrimary;

    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: gradient,
        borderRadius: AppRadii.medium,
        boxShadow: AppEffects.buttonShadow(accentColor: accentColor),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onPressed,
          borderRadius: AppRadii.medium,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: AppSpacing.hero),
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.xl,
                vertical: AppSpacing.md,
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (icon != null) ...[
                    Icon(icon, size: AppSpacing.lg, color: foregroundColor),
                    const SizedBox(width: AppSpacing.sm),
                  ],
                  Flexible(
                    child: Text(
                      label.toUpperCase(),
                      textAlign: TextAlign.center,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.labelLarge?.copyWith(
                        color: foregroundColor,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 1.1,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

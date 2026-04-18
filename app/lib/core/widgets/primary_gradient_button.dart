import 'package:flutter/material.dart';

import '../locale/app_localization_extensions.dart';
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
    this.compact = false,
  });

  final String label;
  final VoidCallback onPressed;
  final IconData? icon;
  final bool useTertiary;
  final bool compact;

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
            constraints: BoxConstraints(
              minHeight: compact ? 42 : AppSpacing.hero,
            ),
            child: Padding(
              padding: EdgeInsets.symmetric(
                horizontal: compact ? AppSpacing.md : AppSpacing.xl,
                vertical: compact ? AppSpacing.xs : AppSpacing.md,
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (icon != null) ...[
                    Icon(
                      icon,
                      size: compact ? AppSpacing.md : AppSpacing.lg,
                      color: foregroundColor,
                    ),
                    SizedBox(width: compact ? AppSpacing.xs : AppSpacing.sm),
                  ],
                  Flexible(
                    child: Text(
                      context.localeAwareCaps(label),
                      textAlign: TextAlign.center,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.labelLarge?.copyWith(
                        color: foregroundColor,
                        fontWeight: FontWeight.w700,
                        letterSpacing: context.localeAwareLetterSpacing(
                          latin: 1.1,
                          chinese: 0,
                        ),
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

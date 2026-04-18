import 'package:flutter/material.dart';

import '../locale/app_localization_extensions.dart';
import '../theme/app_colors.dart';
import '../theme/app_radii.dart';
import '../theme/app_spacing.dart';

enum StatusChipTone { primary, tertiary, neutral }

class StatusChip extends StatelessWidget {
  const StatusChip({
    super.key,
    required this.label,
    this.tone = StatusChipTone.primary,
    this.showDot = true,
  });

  final String label;
  final StatusChipTone tone;
  final bool showDot;

  @override
  Widget build(BuildContext context) {
    final (foreground, background) = switch (tone) {
      StatusChipTone.primary => (
        AppColors.primary,
        AppColors.primary.withValues(alpha: 0.12),
      ),
      StatusChipTone.tertiary => (
        AppColors.tertiary,
        AppColors.tertiary.withValues(alpha: 0.14),
      ),
      StatusChipTone.neutral => (
        AppColors.onSurfaceMuted,
        AppColors.surfaceHighest.withValues(alpha: 0.66),
      ),
    };

    return FittedBox(
      fit: BoxFit.scaleDown,
      alignment: Alignment.centerLeft,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: background,
          borderRadius: AppRadii.pill,
          border: Border.all(color: foreground.withValues(alpha: 0.2)),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md,
            vertical: AppSpacing.xs,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (showDot) ...[
                Container(
                  width: AppSpacing.xs,
                  height: AppSpacing.xs,
                  decoration: BoxDecoration(
                    color: foreground,
                    borderRadius: AppRadii.pill,
                  ),
                ),
                const SizedBox(width: AppSpacing.xs),
              ],
              Text(
                context.localeAwareCaps(label),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(
                  context,
                ).textTheme.labelSmall?.copyWith(
                  color: foreground,
                  letterSpacing: context.localeAwareLetterSpacing(
                    latin: 1.4,
                    chinese: 0,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

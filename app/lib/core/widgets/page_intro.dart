import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';

class AppPageIntro extends StatelessWidget {
  const AppPageIntro({
    super.key,
    this.eyebrow,
    this.title,
    this.titleWidget,
    this.subtitle,
    this.bottomSpacing = AppSpacing.xxxl,
  }) : assert(title != null || titleWidget != null);

  final String? eyebrow;
  final String? title;
  final Widget? titleWidget;
  final String? subtitle;
  final double bottomSpacing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final resolvedTitle =
        titleWidget ??
        Text(
          title!,
          style: theme.textTheme.displaySmall?.copyWith(
            fontWeight: FontWeight.w700,
            height: 1.05,
            letterSpacing: -1,
          ),
        );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (eyebrow != null && eyebrow!.trim().isNotEmpty) ...[
          Text(
            eyebrow!.toUpperCase(),
            style: theme.textTheme.labelMedium?.copyWith(
              color: AppColors.primary.withValues(alpha: 0.82),
              letterSpacing: 3.2,
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
        ],
        resolvedTitle,
        if (subtitle != null && subtitle!.trim().isNotEmpty) ...[
          const SizedBox(height: AppSpacing.md),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 680),
            child: Text(
              subtitle!,
              style: theme.textTheme.bodyLarge?.copyWith(
                color: AppColors.onSurfaceMuted,
              ),
            ),
          ),
        ],
        SizedBox(height: bottomSpacing),
      ],
    );
  }
}

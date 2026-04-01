import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import 'glass_panel.dart';

class SurfaceCard extends StatelessWidget {
  const SurfaceCard({
    super.key,
    required this.child,
    this.eyebrow,
    this.title,
    this.subtitle,
    this.leading,
    this.trailing,
    this.accentColor = AppColors.primary,
  });

  final Widget child;
  final String? eyebrow;
  final String? title;
  final String? subtitle;
  final Widget? leading;
  final Widget? trailing;
  final Color accentColor;

  @override
  Widget build(BuildContext context) {
    return GlassPanel(
      accentColor: accentColor,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (leading != null || trailing != null)
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: _buildHeaderChildren(),
            ),
          if (leading != null || trailing != null)
            const SizedBox(height: AppSpacing.lg),
          if (eyebrow != null)
            Text(
              eyebrow!.toUpperCase(),
              style: Theme.of(
                context,
              ).textTheme.labelMedium?.copyWith(color: AppColors.primaryFixed),
            ),
          if (eyebrow != null) const SizedBox(height: AppSpacing.xs),
          if (title != null)
            Text(title!, style: Theme.of(context).textTheme.headlineMedium),
          if (subtitle != null) ...[
            const SizedBox(height: AppSpacing.sm),
            Text(subtitle!, style: Theme.of(context).textTheme.bodyMedium),
          ],
          if (title != null || subtitle != null)
            const SizedBox(height: AppSpacing.lg),
          child,
        ],
      ),
    );
  }

  List<Widget> _buildHeaderChildren() {
    if (leading != null && trailing != null) {
      return [leading!, const Spacer(), trailing!];
    }

    if (leading != null) {
      return [leading!];
    }

    if (trailing != null) {
      return [const Spacer(), trailing!];
    }

    return const [];
  }
}

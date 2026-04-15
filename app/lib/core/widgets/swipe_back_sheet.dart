import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_effects.dart';
import '../theme/app_radii.dart';
import '../theme/app_spacing.dart';

Future<T?> showSwipeBackSheet<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  bool barrierDismissible = true,
}) {
  return Navigator.of(context).push<T>(
    _SwipeBackSheetRoute<T>(
      builder: builder,
      barrierDismissible: barrierDismissible,
      barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
    ),
  );
}

class _SwipeBackSheetRoute<T> extends PopupRoute<T> {
  _SwipeBackSheetRoute({
    required this.builder,
    required this.barrierDismissible,
    required this.barrierLabel,
  });

  final WidgetBuilder builder;

  @override
  final bool barrierDismissible;

  @override
  final String barrierLabel;

  @override
  Color get barrierColor => Colors.black.withValues(alpha: 0.54);

  @override
  Duration get transitionDuration => AppEffects.medium;

  @override
  Widget buildPage(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
  ) {
    return _SwipeBackSheetScaffold(
      onDismiss: () => navigator?.maybePop(),
      barrierDismissible: barrierDismissible,
      child: builder(context),
    );
  }

  @override
  Widget buildTransitions(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    final offsetAnimation = Tween<Offset>(
      begin: const Offset(0, 0.08),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: animation, curve: Curves.easeOutCubic));

    return FadeTransition(
      opacity: animation,
      child: SlideTransition(position: offsetAnimation, child: child),
    );
  }
}

class _SwipeBackSheetScaffold extends StatefulWidget {
  const _SwipeBackSheetScaffold({
    required this.child,
    required this.onDismiss,
    required this.barrierDismissible,
  });

  final Widget child;
  final VoidCallback onDismiss;
  final bool barrierDismissible;

  @override
  State<_SwipeBackSheetScaffold> createState() =>
      _SwipeBackSheetScaffoldState();
}

class _SwipeBackSheetScaffoldState extends State<_SwipeBackSheetScaffold> {
  static const double _edgeActivationWidth = 44;
  static const double _dismissDistance = 84;
  static const double _dismissVelocity = 540;

  double _dragOffset = 0;
  bool _isTrackingEdgeSwipe = false;

  void _handleHorizontalDragStart(DragStartDetails details) {
    _isTrackingEdgeSwipe = details.globalPosition.dx <= _edgeActivationWidth;
  }

  void _handleHorizontalDragUpdate(DragUpdateDetails details) {
    if (!_isTrackingEdgeSwipe) {
      return;
    }

    setState(() {
      _dragOffset = (_dragOffset + details.delta.dx).clamp(0, 220);
    });
  }

  void _handleHorizontalDragEnd(DragEndDetails details) {
    if (!_isTrackingEdgeSwipe) {
      return;
    }

    final shouldDismiss =
        _dragOffset >= _dismissDistance ||
        details.primaryVelocity != null &&
            details.primaryVelocity! >= _dismissVelocity;
    _isTrackingEdgeSwipe = false;

    if (shouldDismiss) {
      widget.onDismiss();
      return;
    }

    setState(() {
      _dragOffset = 0;
    });
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: true,
      child: Material(
        type: MaterialType.transparency,
        child: Stack(
          children: [
            Positioned.fill(
              child: GestureDetector(
                onTap: widget.barrierDismissible ? widget.onDismiss : null,
                behavior: HitTestBehavior.opaque,
              ),
            ),
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.translucent,
                onHorizontalDragStart: _handleHorizontalDragStart,
                onHorizontalDragUpdate: _handleHorizontalDragUpdate,
                onHorizontalDragEnd: _handleHorizontalDragEnd,
                child: Transform.translate(
                  offset: Offset(_dragOffset, 0),
                  child: SafeArea(
                    child: Align(
                      alignment: Alignment.bottomCenter,
                      child: widget.child,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class DockIconButton extends StatelessWidget {
  const DockIconButton({
    super.key,
    this.buttonKey,
    required this.icon,
    required this.onPressed,
    this.iconSize = 20,
    this.size = 48,
    this.backgroundColor = AppColors.primary,
    this.foregroundColor = AppColors.onPrimary,
    this.borderColor,
  });

  final Key? buttonKey;
  final IconData icon;
  final VoidCallback? onPressed;
  final double iconSize;
  final double size;
  final Color backgroundColor;
  final Color foregroundColor;
  final Color? borderColor;

  @override
  Widget build(BuildContext context) {
    final outlineColor = borderColor ?? backgroundColor.withValues(alpha: 0.24);

    return SizedBox.square(
      dimension: size,
      child: FilledButton(
        key: buttonKey,
        onPressed: onPressed,
        style: FilledButton.styleFrom(
          backgroundColor: backgroundColor,
          foregroundColor: foregroundColor,
          disabledBackgroundColor: backgroundColor.withValues(alpha: 0.3),
          disabledForegroundColor: foregroundColor.withValues(alpha: 0.5),
          padding: EdgeInsets.zero,
          shape: RoundedRectangleBorder(
            borderRadius: AppRadii.medium,
            side: BorderSide(color: outlineColor),
          ),
        ),
        child: Icon(icon, size: iconSize),
      ),
    );
  }
}

class SwipeBackSheetBackButton extends StatelessWidget {
  const SwipeBackSheetBackButton({
    super.key,
    this.label = 'Back',
    this.onPressed,
  });

  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return TextButton.icon(
      key: const Key('sheet-bottom-back-button'),
      onPressed: onPressed ?? () => Navigator.of(context).maybePop(),
      style: TextButton.styleFrom(
        foregroundColor: AppColors.primary,
        backgroundColor: AppColors.surfaceHighest.withValues(alpha: 0.5),
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.lg,
          vertical: AppSpacing.sm,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: AppRadii.pill,
          side: BorderSide(color: AppColors.primary.withValues(alpha: 0.18)),
        ),
      ),
      icon: const Icon(Icons.arrow_back_rounded, size: 18),
      label: Text(
        label.toUpperCase(),
        style: Theme.of(context).textTheme.labelMedium?.copyWith(
          color: AppColors.primary,
          fontWeight: FontWeight.w700,
          letterSpacing: 1.2,
        ),
      ),
    );
  }
}

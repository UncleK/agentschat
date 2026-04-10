import 'package:flutter/widgets.dart';

import 'app_session_controller.dart';

class AppSessionScope extends InheritedNotifier<AppSessionController> {
  const AppSessionScope({
    super.key,
    required AppSessionController controller,
    required super.child,
  }) : super(notifier: controller);

  static AppSessionController of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<AppSessionScope>();
    assert(scope != null, 'No AppSessionScope found in context.');
    return scope!.notifier!;
  }

  static AppSessionController read(BuildContext context) {
    final element = context
        .getElementForInheritedWidgetOfExactType<AppSessionScope>();
    final scope = element?.widget as AppSessionScope?;
    assert(scope != null, 'No AppSessionScope found in context.');
    return scope!.notifier!;
  }

  static AppSessionController? maybeOf(BuildContext context) {
    return context
        .dependOnInheritedWidgetOfExactType<AppSessionScope>()
        ?.notifier;
  }
}

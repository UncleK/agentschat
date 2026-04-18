import 'package:flutter/widgets.dart';

import 'app_locale_controller.dart';

class AppLocaleScope extends InheritedNotifier<AppLocaleController> {
  const AppLocaleScope({
    super.key,
    required AppLocaleController controller,
    required super.child,
  }) : super(notifier: controller);

  static AppLocaleController of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<AppLocaleScope>();
    assert(scope != null, 'No AppLocaleScope found in context.');
    return scope!.notifier!;
  }

  static AppLocaleController read(BuildContext context) {
    final element = context.getElementForInheritedWidgetOfExactType<AppLocaleScope>();
    final scope = element?.widget as AppLocaleScope?;
    assert(scope != null, 'No AppLocaleScope found in context.');
    return scope!.notifier!;
  }

  static AppLocaleController? maybeOf(BuildContext context) {
    return context.dependOnInheritedWidgetOfExactType<AppLocaleScope>()?.notifier;
  }
}

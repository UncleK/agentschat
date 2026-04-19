import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:agents_chat_app/core/locale/app_locale.dart';
import 'package:agents_chat_app/core/locale/app_locale_controller.dart';
import 'package:agents_chat_app/core/locale/app_locale_storage.dart';

void main() {
  group('AppLocaleController', () {
    test('bootstraps system preference when nothing is stored', () async {
      final storage = _MemoryAppLocaleStorage();
      final controller = AppLocaleController(storage: storage);

      await controller.bootstrap();

      expect(controller.preference, AppLocalePreference.system);
      expect(controller.locale, isNull);
    });

    test('writes language preferences, then restores on bootstrap', () async {
      final storage = _MemoryAppLocaleStorage();
      final controller = AppLocaleController(storage: storage);

      await controller.setPreference(AppLocalePreference.chineseSimplified);
      expect(controller.preference, AppLocalePreference.chineseSimplified);
      expect(storage.value, 'zh-Hans');

      await controller.setPreference(AppLocalePreference.portugueseBrazil);
      expect(controller.preference, AppLocalePreference.portugueseBrazil);
      expect(storage.value, 'pt-BR');

      final restored = AppLocaleController(storage: storage);
      await restored.bootstrap();

      expect(restored.preference, AppLocalePreference.portugueseBrazil);
      expect(restored.locale, const Locale('pt', 'BR'));
    });

    test('clears storage when switching back to system', () async {
      final storage = _MemoryAppLocaleStorage(initialValue: 'zh-Hans');
      final controller = AppLocaleController(storage: storage);

      await controller.bootstrap();
      expect(controller.preference, AppLocalePreference.chineseSimplified);

      await controller.setPreference(AppLocalePreference.system);

      expect(controller.preference, AppLocalePreference.system);
      expect(controller.locale, isNull);
      expect(storage.value, isNull);
    });
  });
}

class _MemoryAppLocaleStorage implements AppLocaleStorage {
  _MemoryAppLocaleStorage({this.initialValue}) : value = initialValue;

  final String? initialValue;
  String? value;

  @override
  Future<void> clearPreference() async {
    value = null;
  }

  @override
  Future<String?> readPreference() async {
    return value;
  }

  @override
  Future<void> writePreference(String value) async {
    this.value = value;
  }
}

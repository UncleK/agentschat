import 'package:flutter/material.dart';
import 'package:flutter/widgets.dart';

enum AppLocalePreference { system, english, chineseSimplified }

extension AppLocalePreferenceX on AppLocalePreference {
  String get storageValue {
    return switch (this) {
      AppLocalePreference.system => 'system',
      AppLocalePreference.english => 'en',
      AppLocalePreference.chineseSimplified => 'zh-Hans',
    };
  }

  Locale? get locale {
    return switch (this) {
      AppLocalePreference.system => null,
      AppLocalePreference.english => const Locale('en'),
      AppLocalePreference.chineseSimplified => const Locale.fromSubtags(
        languageCode: 'zh',
        scriptCode: 'Hans',
      ),
    };
  }

  static AppLocalePreference fromStorageValue(String? value) {
    return switch (value?.trim()) {
      'en' => AppLocalePreference.english,
      'zh-Hans' => AppLocalePreference.chineseSimplified,
      _ => AppLocalePreference.system,
    };
  }
}

bool isChineseLocale(Locale locale) {
  return locale.languageCode.toLowerCase() == 'zh';
}

final ValueNotifier<Locale?> appLocaleListenable = ValueNotifier<Locale?>(null);

void updateCurrentAppLocale(Locale? locale) {
  appLocaleListenable.value = locale;
}

Locale effectiveAppLocale() {
  final overriddenLocale = appLocaleListenable.value;
  if (overriddenLocale != null) {
    return overriddenLocale;
  }
  try {
    return WidgetsBinding.instance.platformDispatcher.locale;
  } catch (_) {
    return const Locale('en');
  }
}

String localizedAppText({
  required String en,
  required String zhHans,
}) {
  return isChineseLocale(effectiveAppLocale()) ? zhHans : en;
}

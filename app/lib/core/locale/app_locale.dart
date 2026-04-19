import 'package:flutter/material.dart';
import 'package:flutter/widgets.dart';

import '../../l10n/generated/runtime_message_catalog.dart';

enum AppLocalePreference {
  system,
  english,
  chineseSimplified,
  chineseTraditional,
  portugueseBrazil,
  spanishLatinAmerica,
  indonesian,
  japanese,
  korean,
  german,
  french,
}

const List<AppLocalePreference> selectableAppLocalePreferences = [
  AppLocalePreference.system,
  AppLocalePreference.english,
  AppLocalePreference.chineseSimplified,
  AppLocalePreference.chineseTraditional,
  AppLocalePreference.portugueseBrazil,
  AppLocalePreference.spanishLatinAmerica,
  AppLocalePreference.indonesian,
  AppLocalePreference.japanese,
  AppLocalePreference.korean,
  AppLocalePreference.german,
  AppLocalePreference.french,
];

extension AppLocalePreferenceX on AppLocalePreference {
  String get storageValue {
    return switch (this) {
      AppLocalePreference.system => 'system',
      AppLocalePreference.english => 'en',
      AppLocalePreference.chineseSimplified => 'zh-Hans',
      AppLocalePreference.chineseTraditional => 'zh-Hant',
      AppLocalePreference.portugueseBrazil => 'pt-BR',
      AppLocalePreference.spanishLatinAmerica => 'es-419',
      AppLocalePreference.indonesian => 'id-ID',
      AppLocalePreference.japanese => 'ja-JP',
      AppLocalePreference.korean => 'ko-KR',
      AppLocalePreference.german => 'de-DE',
      AppLocalePreference.french => 'fr-FR',
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
      AppLocalePreference.chineseTraditional => const Locale.fromSubtags(
        languageCode: 'zh',
        scriptCode: 'Hant',
      ),
      AppLocalePreference.portugueseBrazil => const Locale('pt', 'BR'),
      AppLocalePreference.spanishLatinAmerica => const Locale.fromSubtags(
        languageCode: 'es',
        countryCode: '419',
      ),
      AppLocalePreference.indonesian => const Locale('id', 'ID'),
      AppLocalePreference.japanese => const Locale('ja', 'JP'),
      AppLocalePreference.korean => const Locale('ko', 'KR'),
      AppLocalePreference.german => const Locale('de', 'DE'),
      AppLocalePreference.french => const Locale('fr', 'FR'),
    };
  }

  static AppLocalePreference fromStorageValue(String? value) {
    return switch (value?.trim()) {
      'en' => AppLocalePreference.english,
      'zh-Hans' => AppLocalePreference.chineseSimplified,
      'zh-Hant' => AppLocalePreference.chineseTraditional,
      'pt-BR' => AppLocalePreference.portugueseBrazil,
      'es-419' => AppLocalePreference.spanishLatinAmerica,
      'id-ID' => AppLocalePreference.indonesian,
      'ja-JP' => AppLocalePreference.japanese,
      'ko-KR' => AppLocalePreference.korean,
      'de-DE' => AppLocalePreference.german,
      'fr-FR' => AppLocalePreference.french,
      _ => AppLocalePreference.system,
    };
  }
}

bool isChineseLocale(Locale locale) {
  return locale.languageCode.toLowerCase() == 'zh';
}

bool isTraditionalChineseLocale(Locale locale) {
  if (!isChineseLocale(locale)) {
    return false;
  }
  final scriptCode = locale.scriptCode?.toLowerCase();
  if (scriptCode == 'hant') {
    return true;
  }
  final countryCode = locale.countryCode?.toUpperCase();
  return countryCode == 'TW' || countryCode == 'HK' || countryCode == 'MO';
}

bool isSimplifiedChineseLocale(Locale locale) {
  return isChineseLocale(locale) && !isTraditionalChineseLocale(locale);
}

bool usesCjkTypographyLocale(Locale locale) {
  final languageCode = locale.languageCode.toLowerCase();
  return languageCode == 'zh' || languageCode == 'ja' || languageCode == 'ko';
}

String? appFontFamilyForLocale(Locale locale) {
  if (isSimplifiedChineseLocale(locale)) {
    return 'NotoSansSC';
  }
  if (usesCjkTypographyLocale(locale)) {
    return null;
  }
  return 'Inter';
}

Locale normalizeAppLocale(Locale locale) {
  final languageCode = locale.languageCode.toLowerCase();
  return switch (languageCode) {
    'zh' => Locale.fromSubtags(
      languageCode: 'zh',
      scriptCode: isTraditionalChineseLocale(locale) ? 'Hant' : 'Hans',
    ),
    'pt' => const Locale('pt', 'BR'),
    'es' => const Locale.fromSubtags(languageCode: 'es', countryCode: '419'),
    'id' => const Locale('id', 'ID'),
    'ja' => const Locale('ja', 'JP'),
    'ko' => const Locale('ko', 'KR'),
    'de' => const Locale('de', 'DE'),
    'fr' => const Locale('fr', 'FR'),
    _ => Locale(languageCode),
  };
}

Locale resolveSupportedAppLocale(
  Locale? requestedLocale,
  Iterable<Locale> supportedLocales,
) {
  final supportedLocaleList = supportedLocales.toList(growable: false);
  if (supportedLocaleList.isEmpty) {
    return const Locale('en');
  }
  if (requestedLocale == null) {
    return supportedLocaleList.first;
  }

  final normalizedLocale = normalizeAppLocale(requestedLocale);
  for (final supportedLocale in supportedLocaleList) {
    if (_localeIdentityMatches(supportedLocale, normalizedLocale)) {
      return supportedLocale;
    }
  }
  for (final supportedLocale in supportedLocaleList) {
    if (supportedLocale.languageCode == normalizedLocale.languageCode &&
        supportedLocale.scriptCode == normalizedLocale.scriptCode) {
      return supportedLocale;
    }
  }
  for (final supportedLocale in supportedLocaleList) {
    if (supportedLocale.languageCode == normalizedLocale.languageCode) {
      return supportedLocale;
    }
  }
  return supportedLocaleList.first;
}

bool _localeIdentityMatches(Locale left, Locale right) {
  return left.languageCode == right.languageCode &&
      left.scriptCode == right.scriptCode &&
      left.countryCode == right.countryCode;
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
  String? key,
  Map<String, Object?> args = const <String, Object?>{},
}) {
  final locale = effectiveAppLocale();
  if (key != null) {
    final translated = lookupRuntimeMessage(locale: locale, key: key, args: args);
    if (translated != null) {
      return translated;
    }
  }
  return isChineseLocale(locale) ? zhHans : en;
}

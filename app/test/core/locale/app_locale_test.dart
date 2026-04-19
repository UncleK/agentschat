import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:agents_chat_app/core/locale/app_locale.dart';
import 'package:agents_chat_app/l10n/generated/app_localizations.dart';

void main() {
  group('AppLocalePreferenceX', () {
    test('restores newly added storage values', () {
      expect(
        AppLocalePreferenceX.fromStorageValue('zh-Hant'),
        AppLocalePreference.chineseTraditional,
      );
      expect(
        AppLocalePreferenceX.fromStorageValue('es-419'),
        AppLocalePreference.spanishLatinAmerica,
      );
      expect(
        AppLocalePreferenceX.fromStorageValue('fr-FR'),
        AppLocalePreference.french,
      );
    });
  });

  group('resolveSupportedAppLocale', () {
    test('maps Chinese system locales to Hans or Hant', () {
      expect(
        resolveSupportedAppLocale(
          const Locale('zh', 'CN'),
          AppLocalizations.supportedLocales,
        ),
        const Locale.fromSubtags(languageCode: 'zh', scriptCode: 'Hans'),
      );
      expect(
        resolveSupportedAppLocale(
          const Locale('zh', 'TW'),
          AppLocalizations.supportedLocales,
        ),
        const Locale.fromSubtags(languageCode: 'zh', scriptCode: 'Hant'),
      );
    });

    test('normalizes regional rollouts to app locales', () {
      expect(
        resolveSupportedAppLocale(
          const Locale('es', 'MX'),
          AppLocalizations.supportedLocales,
        ),
        const Locale.fromSubtags(languageCode: 'es', countryCode: '419'),
      );
      expect(
        resolveSupportedAppLocale(
          const Locale('pt', 'PT'),
          AppLocalizations.supportedLocales,
        ),
        const Locale('pt', 'BR'),
      );
    });
  });
}

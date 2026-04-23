import 'package:flutter/material.dart';

import 'app_locale.dart';
import '../../l10n/generated/app_localizations.dart';
import '../../l10n/generated/runtime_message_catalog.dart';

extension AppLocalizationBuildContextX on BuildContext {
  AppLocalizations get l10n {
    final localization = Localizations.of<AppLocalizations>(
      this,
      AppLocalizations,
    );
    if (localization != null) {
      return localization;
    }
    return lookupAppLocalizations(
      resolveSupportedAppLocale(appLocale, AppLocalizations.supportedLocales),
    );
  }

  Locale get appLocale => resolveSupportedAppLocale(
    Localizations.maybeLocaleOf(this) ?? effectiveAppLocale(),
    AppLocalizations.supportedLocales,
  );

  bool get usesWideGlyphTypography => usesCjkTypographyLocale(appLocale);

  String localizedText({
    required String en,
    required String zhHans,
    String? key,
    Map<String, Object?> args = const <String, Object?>{},
  }) {
    if (key != null) {
      final translated = lookupRuntimeMessage(
        locale: appLocale,
        key: key,
        args: args,
      );
      if (translated != null) {
        return translated;
      }
    }
    return isChineseLocale(appLocale) ? zhHans : en;
  }

  String localeAwareCaps(String value) {
    return usesWideGlyphTypography ? value : value.toUpperCase();
  }

  double localeAwareLetterSpacing({required double latin, double chinese = 0}) {
    return usesWideGlyphTypography ? chinese : latin;
  }
}

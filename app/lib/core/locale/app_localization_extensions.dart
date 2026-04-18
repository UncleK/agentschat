import 'package:flutter/material.dart';

import 'app_locale.dart';
import '../../l10n/generated/app_localizations.dart';
import '../../l10n/generated/app_localizations_en.dart';
import '../../l10n/generated/app_localizations_zh.dart';

extension AppLocalizationBuildContextX on BuildContext {
  AppLocalizations get l10n {
    final localization = Localizations.of<AppLocalizations>(
      this,
      AppLocalizations,
    );
    if (localization != null) {
      return localization;
    }
    return isChineseLocale(appLocale)
        ? AppLocalizationsZh()
        : AppLocalizationsEn();
  }

  Locale get appLocale =>
      Localizations.maybeLocaleOf(this) ?? effectiveAppLocale();

  bool get usesChineseTypography => isChineseLocale(appLocale);

  String localizedText({
    required String en,
    required String zhHans,
  }) {
    return usesChineseTypography ? zhHans : en;
  }

  String localeAwareCaps(String value) {
    return usesChineseTypography ? value : value.toUpperCase();
  }

  double localeAwareLetterSpacing({
    required double latin,
    double chinese = 0,
  }) {
    return usesChineseTypography ? chinese : latin;
  }
}

import 'package:flutter/material.dart';

import 'app_locale.dart';
import 'app_locale_storage.dart';

class AppLocaleController extends ChangeNotifier {
  AppLocaleController({required this.storage});

  final AppLocaleStorage storage;

  AppLocalePreference _preference = AppLocalePreference.system;

  AppLocalePreference get preference => _preference;

  Locale? get locale => _preference.locale;

  Future<void> bootstrap() async {
    final storedValue = await storage.readPreference();
    final nextPreference = AppLocalePreferenceX.fromStorageValue(storedValue);
    if (_preference == nextPreference) {
      return;
    }
    _preference = nextPreference;
    notifyListeners();
  }

  Future<void> setPreference(AppLocalePreference preference) async {
    if (_preference == preference) {
      return;
    }
    final previousPreference = _preference;
    _preference = preference;
    notifyListeners();

    try {
      if (preference == AppLocalePreference.system) {
        await storage.clearPreference();
      } else {
        await storage.writePreference(preference.storageValue);
      }
    } catch (_) {
      _preference = previousPreference;
      notifyListeners();
      rethrow;
    }
  }
}

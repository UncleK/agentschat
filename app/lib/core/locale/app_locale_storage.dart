import 'package:shared_preferences/shared_preferences.dart';

abstract class AppLocaleStorage {
  Future<String?> readPreference();

  Future<void> writePreference(String value);

  Future<void> clearPreference();
}

class SharedPreferencesAppLocaleStorage implements AppLocaleStorage {
  const SharedPreferencesAppLocaleStorage();

  static const _localePreferenceKey = 'app_locale.preference';

  Future<SharedPreferences> get _prefs async => SharedPreferences.getInstance();

  @override
  Future<void> clearPreference() async {
    final prefs = await _prefs;
    await prefs.remove(_localePreferenceKey);
  }

  @override
  Future<String?> readPreference() async {
    final prefs = await _prefs;
    final value = prefs.getString(_localePreferenceKey);
    if (value == null || value.isEmpty) {
      return null;
    }
    return value;
  }

  @override
  Future<void> writePreference(String value) async {
    final prefs = await _prefs;
    await prefs.setString(_localePreferenceKey, value);
  }
}

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Local key for the Appearance setting. Default is system.
const String themeModePreferenceKey = 'elevo_theme_mode';

ThemeMode themeModeFromStorage(String? raw) {
  switch (raw) {
    case 'light':
      return ThemeMode.light;
    case 'dark':
      return ThemeMode.dark;
    default:
      return ThemeMode.system;
  }
}

String themeModeStorageValue(ThemeMode mode) {
  switch (mode) {
    case ThemeMode.light:
      return 'light';
    case ThemeMode.dark:
      return 'dark';
    case ThemeMode.system:
      return 'system';
  }
}

/// App-wide light / dark / system choice, stored on the device.
class ThemeModeController extends ChangeNotifier {
  ThemeMode _mode;

  ThemeModeController({ThemeMode initial = ThemeMode.system}) : _mode = initial;

  ThemeMode get mode => _mode;

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final next = themeModeFromStorage(prefs.getString(themeModePreferenceKey));
    if (next == _mode) return;
    _mode = next;
    notifyListeners();
  }

  Future<void> setMode(ThemeMode mode) async {
    if (_mode == mode) return;
    _mode = mode;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(themeModePreferenceKey, themeModeStorageValue(mode));
  }
}

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:shared_preferences/shared_preferences.dart';

final themeControllerProvider =
    StateNotifierProvider<ThemeController, ThemeMode>((ref) {
  return ThemeController();
});

class ThemeController extends StateNotifier<ThemeMode> {
  ThemeController() : super(ThemeMode.system) {
    _loadPersistedMode();
  }

  static const _themeModeKey = 'app_theme_mode';

  Future<void> _loadPersistedMode() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final stored = prefs.getString(_themeModeKey);
      if (stored == null) return;
      final mode = ThemeMode.values.firstWhere(
        (value) => value.name == stored,
        orElse: () => ThemeMode.system,
      );
      state = mode;
    } on MissingPluginException {
      // Ignore missing plugin errors when running on platforms without SharedPreferences.
    } on PlatformException {
      // Ignore platform errors; the theme will remain at the default.
    }
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    if (state == mode) return;
    state = mode;

    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_themeModeKey, mode.name);
    } on MissingPluginException {
      // Ignore missing plugin errors when running on platforms without SharedPreferences.
    } on PlatformException {
      // Ignore persistence failures; the in-memory state has already been updated.
    }
  }
}

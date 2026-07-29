import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'localization/app_localization_service.dart';

const _themePrefsKey = 'app_theme_mode';

ThemeMode _parseThemeMode(String? value) {
  switch (value) {
    case 'dark':
      return ThemeMode.dark;
    case 'light':
      return ThemeMode.light;
    default:
      return ThemeMode.light;
  }
}

String _serializeThemeMode(ThemeMode mode) {
  return mode == ThemeMode.dark ? 'dark' : 'light';
}

class ThemeModeNotifier extends StateNotifier<ThemeMode> {
  ThemeModeNotifier(this._prefs)
      : super(_parseThemeMode(_prefs.getString(_themePrefsKey)));

  final SharedPreferences _prefs;

  Future<void> setThemeMode(ThemeMode mode) async {
    if (state == mode) return;
    state = mode;
    await _prefs.setString(_themePrefsKey, _serializeThemeMode(mode));
  }

  Future<void> toggle() async {
    final nextMode = state == ThemeMode.dark ? ThemeMode.light : ThemeMode.dark;
    await setThemeMode(nextMode);
  }
}

final themeModeProvider =
    StateNotifierProvider<ThemeModeNotifier, ThemeMode>((ref) {
  final prefs = ref.watch(sharedPreferencesProvider);
  return ThemeModeNotifier(prefs);
});

class AppTheme {
  static const Color _blue = Color(0xFF007AFF);
  static const Color _green = Color(0xFF34C759);
  static const Color _orange = Color(0xFFFF9500);

  static const Color _lightBackground = Color(0xFFF2F2F7);
  static const Color _lightSurface = Colors.white;
  static const Color _lightSurfaceVariant = Color(0xFFF1F1F5);
  static const Color _lightOutline = Color(0xFFE1E1E6);

  static const Color _darkBackground = Color(0xFF0D0E11);
  static const Color _darkSurface = Color(0xFF1C1C1E);
  static const Color _darkSurfaceVariant = Color(0xFF2C2C2E);
  static const Color _darkOutline = Color(0xFF3A3A3C);

  static ThemeData light() {
    final scheme = const ColorScheme.light(
      primary: _blue,
      secondary: _green,
      tertiary: _orange,
      surface: _lightSurface,
      surfaceContainerHighest: _lightSurfaceVariant,
      outline: _lightOutline,
      onPrimary: Colors.white,
      onSecondary: Colors.white,
      onTertiary: Colors.white,
      onSurface: Color(0xFF1C1C1E),
      onSurfaceVariant: Color(0xFF3A3A3C),
      error: Color(0xFFFF3B30),
      onError: Colors.white,
    );

    return ThemeData(
      brightness: Brightness.light,
      colorScheme: scheme,
      scaffoldBackgroundColor: _lightBackground,
      fontFamily: 'Roboto',
      shadowColor: Colors.black.withOpacity(0.14),
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.transparent,
        foregroundColor: Color(0xFF1C1C1E),
        elevation: 0,
        systemOverlayStyle: SystemUiOverlayStyle.dark,
      ),
      iconTheme: IconThemeData(
        color: scheme.onSurface.withOpacity(0.7),
        size: 24,
      ),
      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        backgroundColor: _blue,
        foregroundColor: Colors.white,
      ),
      dividerColor: _lightOutline,
      bottomAppBarTheme: const BottomAppBarThemeData(
        color: _lightSurface,
        elevation: 8,
      ),
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
          TargetPlatform.android: CupertinoPageTransitionsBuilder(),
        },
      ),
    );
  }

  static ThemeData dark() {
    final scheme = const ColorScheme.dark(
      primary: _blue,
      secondary: _green,
      tertiary: _orange,
      surface: _darkSurface,
      surfaceContainerHighest: _darkSurfaceVariant,
      outline: _darkOutline,
      onPrimary: Colors.white,
      onSecondary: Colors.white,
      onTertiary: Colors.white,
      onSurface: Colors.white,
      onSurfaceVariant: Colors.white70,
      error: Color(0xFFFF453A),
      onError: Colors.white,
    );

    return ThemeData(
      brightness: Brightness.dark,
      colorScheme: scheme,
      scaffoldBackgroundColor: _darkBackground,
      fontFamily: 'Roboto',
      shadowColor: Colors.black.withOpacity(0.4),
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.white,
        elevation: 0,
        systemOverlayStyle: SystemUiOverlayStyle.light,
      ),
      iconTheme: IconThemeData(
        color: scheme.onSurface.withOpacity(0.7),
        size: 24,
      ),
      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        backgroundColor: _blue,
        foregroundColor: Colors.white,
      ),
      dividerColor: _darkOutline,
      bottomAppBarTheme: const BottomAppBarThemeData(
        color: _darkSurface,
        elevation: 8,
      ),
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
          TargetPlatform.android: CupertinoPageTransitionsBuilder(),
        },
      ),
    );
  }
}

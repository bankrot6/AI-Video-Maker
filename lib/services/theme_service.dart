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
  static const Color _accent = Color(0xFF0077CC);
  static const Color _accentSecondary = Color(0xFFF5A623);
  static const Color _green = Color(0xFF34C759);

  static const Color _lightBackground = Color(0xFFF4F7FC);
  static const Color _lightSurface = Color(0xFFFFFFFF);
  static const Color _lightTextPrimary = Color(0xFF1A2333);
  static const Color _lightTextSecondary = Color(0xFF5A6B7C);
  static const Color _lightSurfaceVariant = Color(0xFFE8EEF6);
  static const Color _lightOutline = Color(0xFFD0DAE8);

  static const Color _darkBackground = Color(0xFF0F1520);
  static const Color _darkSurface = Color(0xFF1A2333);
  static const Color _darkTextPrimary = Color(0xFFF4F7FC);
  static const Color _darkTextSecondary = Color(0xFF8A9BB0);
  static const Color _darkSurfaceVariant = Color(0xFF243044);
  static const Color _darkOutline = Color(0xFF2E4058);

  static ThemeData light() {
    final scheme = const ColorScheme.light(
      primary: _accent,
      secondary: _green,
      tertiary: _accentSecondary,
      surface: _lightSurface,
      surfaceContainerHighest: _lightSurfaceVariant,
      outline: _lightOutline,
      onPrimary: Colors.white,
      onSecondary: Colors.white,
      onTertiary: _lightTextPrimary,
      onSurface: _lightTextPrimary,
      onSurfaceVariant: _lightTextSecondary,
      error: Color(0xFFFF3B30),
      onError: Colors.white,
    );

    return ThemeData(
      brightness: Brightness.light,
      colorScheme: scheme,
      scaffoldBackgroundColor: _lightBackground,
      canvasColor: _lightBackground,
      fontFamily: 'Roboto',
      shadowColor: Colors.black.withOpacity(0.14),
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.transparent,
        foregroundColor: _lightTextPrimary,
        elevation: 0,
        systemOverlayStyle: SystemUiOverlayStyle.dark,
      ),
      iconTheme: IconThemeData(
        color: _lightTextSecondary,
        size: 24,
      ),
      cardTheme: const CardThemeData(
        color: _lightSurface,
        surfaceTintColor: Colors.transparent,
      ),
      dialogTheme: const DialogThemeData(
        backgroundColor: _lightSurface,
        surfaceTintColor: Colors.transparent,
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: _lightSurface,
        surfaceTintColor: Colors.transparent,
        modalBackgroundColor: _lightSurface,
      ),
      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        backgroundColor: _accent,
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
      primary: _accent,
      secondary: _green,
      tertiary: _accentSecondary,
      surface: _darkSurface,
      surfaceContainerHighest: _darkSurfaceVariant,
      outline: _darkOutline,
      onPrimary: Colors.white,
      onSecondary: Colors.white,
      onTertiary: _darkTextPrimary,
      onSurface: _darkTextPrimary,
      onSurfaceVariant: _darkTextSecondary,
      error: Color(0xFFFF453A),
      onError: Colors.white,
    );

    return ThemeData(
      brightness: Brightness.dark,
      colorScheme: scheme,
      scaffoldBackgroundColor: _darkBackground,
      canvasColor: _darkBackground,
      fontFamily: 'Roboto',
      shadowColor: Colors.black.withOpacity(0.4),
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.transparent,
        foregroundColor: _darkTextPrimary,
        elevation: 0,
        systemOverlayStyle: SystemUiOverlayStyle.light,
      ),
      iconTheme: IconThemeData(
        color: _darkTextSecondary,
        size: 24,
      ),
      cardTheme: const CardThemeData(
        color: _darkSurface,
        surfaceTintColor: Colors.transparent,
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: _darkSurfaceVariant,
        surfaceTintColor: Colors.transparent,
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: _darkSurfaceVariant,
        surfaceTintColor: Colors.transparent,
        modalBackgroundColor: _darkSurfaceVariant,
      ),
      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        backgroundColor: _accent,
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

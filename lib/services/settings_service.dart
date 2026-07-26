// lib/services/settings_service.dart
//
// Réglages globaux de l'application : mode d'affichage préféré, taille des
// vignettes en vue grille, police utilisée par l'explorateur, thème clair/
// sombre/système. Persistés via flutter_secure_storage, et exposés via un
// ValueNotifier pour que l'UI se mette à jour immédiatement sans redémarrage.
//
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

enum AppThemeMode { system, light, dark }
enum DefaultViewMode { list, grid }

class AppSettings {
  final DefaultViewMode defaultViewMode;
  final int gridColumns;       // nombre de colonnes en vue grille (3 à 8)
  final String fontFamily;     // nom Google Fonts, ou 'Système' pour la police par défaut
  final AppThemeMode themeMode;

  const AppSettings({
    this.defaultViewMode = DefaultViewMode.list,
    this.gridColumns = 6,
    this.fontFamily = 'Système',
    this.themeMode = AppThemeMode.system,
  });

  AppSettings copyWith({
    DefaultViewMode? defaultViewMode,
    int? gridColumns,
    String? fontFamily,
    AppThemeMode? themeMode,
  }) =>
      AppSettings(
        defaultViewMode: defaultViewMode ?? this.defaultViewMode,
        gridColumns: gridColumns ?? this.gridColumns,
        fontFamily: fontFamily ?? this.fontFamily,
        themeMode: themeMode ?? this.themeMode,
      );

  ThemeMode get flutterThemeMode => switch (themeMode) {
        AppThemeMode.system => ThemeMode.system,
        AppThemeMode.light  => ThemeMode.light,
        AppThemeMode.dark   => ThemeMode.dark,
      };
}

/// Liste de polices proposées dans les réglages (curatée, pas exhaustive).
const List<String> kAvailableFonts = [
  'Système', 'Roboto', 'Inter', 'Poppins', 'Nunito', 'Lato',
  'Open Sans', 'Source Sans 3', 'Work Sans', 'JetBrains Mono',
];

class SettingsService {
  static const _storage = FlutterSecureStorage();
  static const _kViewMode = 'settings_view_mode';
  static const _kGridCols = 'settings_grid_columns';
  static const _kFont     = 'settings_font_family';
  static const _kTheme    = 'settings_theme_mode';

  /// Notifier global — écouté par MaterialApp pour appliquer thème/police
  /// immédiatement, et par les explorateurs pour la vue/grille par défaut.
  static final ValueNotifier<AppSettings> notifier = ValueNotifier(const AppSettings());

  static Future<void> load() async {
    final viewModeStr = await _storage.read(key: _kViewMode);
    final gridColsStr = await _storage.read(key: _kGridCols);
    final font        = await _storage.read(key: _kFont);
    final validFont    = (font != null && kAvailableFonts.contains(font)) ? font : 'Système';
    final themeStr    = await _storage.read(key: _kTheme);

    notifier.value = AppSettings(
      defaultViewMode: viewModeStr == 'grid' ? DefaultViewMode.grid : DefaultViewMode.list,
      gridColumns: int.tryParse(gridColsStr ?? '') ?? 6,
      fontFamily: validFont,
      themeMode: switch (themeStr) {
        'light' => AppThemeMode.light,
        'dark'  => AppThemeMode.dark,
        _       => AppThemeMode.system,
      },
    );
  }

  static Future<void> setDefaultViewMode(DefaultViewMode mode) async {
    await _storage.write(key: _kViewMode, value: mode == DefaultViewMode.grid ? 'grid' : 'list');
    notifier.value = notifier.value.copyWith(defaultViewMode: mode);
  }

  static Future<void> setGridColumns(int columns) async {
    await _storage.write(key: _kGridCols, value: columns.toString());
    notifier.value = notifier.value.copyWith(gridColumns: columns);
  }

  static Future<void> setFontFamily(String font) async {
    await _storage.write(key: _kFont, value: font);
    notifier.value = notifier.value.copyWith(fontFamily: font);
  }

  static Future<void> setThemeMode(AppThemeMode mode) async {
    await _storage.write(key: _kTheme,
        value: switch (mode) { AppThemeMode.light => 'light', AppThemeMode.dark => 'dark', _ => 'system' });
    notifier.value = notifier.value.copyWith(themeMode: mode);
  }
}

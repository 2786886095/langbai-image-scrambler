import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum AppLanguage { simplified, traditional }

enum AppThemePreference { system, light, dark }

class AppSettings extends ChangeNotifier {
  AppSettings._({
    required this._preferences,
    required this._language,
    required this._theme,
    required this._askExportEveryTime,
    required this._checkUpdates,
    this.defaultExportPath,
    this.defaultExportTreeUri,
    this.defaultExportLabel,
  });

  static const _languageKey = 'language';
  static const _themeKey = 'theme';
  static const _askExportKey = 'ask_export_every_time';
  static const _checkUpdatesKey = 'check_updates';
  static const _defaultExportPathKey = 'default_export_path';
  static const _defaultExportTreeKey = 'default_export_tree_uri';
  static const _defaultExportLabelKey = 'default_export_label';

  final SharedPreferences _preferences;
  AppLanguage _language;
  AppThemePreference _theme;
  bool _askExportEveryTime;
  bool _checkUpdates;
  String? defaultExportPath;
  String? defaultExportTreeUri;
  String? defaultExportLabel;

  AppLanguage get language => _language;
  AppThemePreference get theme => _theme;
  bool get askExportEveryTime => _askExportEveryTime;
  bool get checkUpdates => _checkUpdates;

  static Future<AppSettings> load() async {
    final preferences = await SharedPreferences.getInstance();
    final savedLanguage = preferences.getString(_languageKey);
    final platformLocale = WidgetsBinding.instance.platformDispatcher.locale;
    final usesTraditional = const {
      'TW',
      'HK',
      'MO',
    }.contains(platformLocale.countryCode?.toUpperCase());
    final language =
        savedLanguage == AppLanguage.traditional.name ||
            (savedLanguage == null && usesTraditional)
        ? AppLanguage.traditional
        : AppLanguage.simplified;
    final themeName = preferences.getString(_themeKey);
    final theme = AppThemePreference.values.firstWhere(
      (value) => value.name == themeName,
      orElse: () => AppThemePreference.dark,
    );
    return AppSettings._(
      preferences: preferences,
      language: language,
      theme: theme,
      askExportEveryTime: preferences.getBool(_askExportKey) ?? true,
      checkUpdates: preferences.getBool(_checkUpdatesKey) ?? true,
      defaultExportPath: preferences.getString(_defaultExportPathKey),
      defaultExportTreeUri: preferences.getString(_defaultExportTreeKey),
      defaultExportLabel: preferences.getString(_defaultExportLabelKey),
    );
  }

  Future<void> setLanguage(AppLanguage value) async {
    if (_language == value) return;
    _language = value;
    await _preferences.setString(_languageKey, value.name);
    notifyListeners();
  }

  Future<void> setTheme(AppThemePreference value) async {
    if (_theme == value) return;
    _theme = value;
    await _preferences.setString(_themeKey, value.name);
    notifyListeners();
  }

  Future<void> setAskExportEveryTime(bool value) async {
    if (_askExportEveryTime == value) return;
    _askExportEveryTime = value;
    await _preferences.setBool(_askExportKey, value);
    notifyListeners();
  }

  Future<void> setCheckUpdates(bool value) async {
    if (_checkUpdates == value) return;
    _checkUpdates = value;
    await _preferences.setBool(_checkUpdatesKey, value);
    notifyListeners();
  }

  Future<void> setDefaultExport({
    String? path,
    String? treeUri,
    required String label,
  }) async {
    defaultExportPath = path;
    defaultExportTreeUri = treeUri;
    defaultExportLabel = label;
    if (path == null) {
      await _preferences.remove(_defaultExportPathKey);
    } else {
      await _preferences.setString(_defaultExportPathKey, path);
    }
    if (treeUri == null) {
      await _preferences.remove(_defaultExportTreeKey);
    } else {
      await _preferences.setString(_defaultExportTreeKey, treeUri);
    }
    await _preferences.setString(_defaultExportLabelKey, label);
    notifyListeners();
  }
}

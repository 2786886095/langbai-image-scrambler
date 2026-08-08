import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'models.dart';

enum AppLanguage { simplified, traditional }

enum AppThemePreference { system, light, dark }

class AppSettings extends ChangeNotifier {
  AppSettings._({
    required this._preferences,
    required this._language,
    required this._theme,
    required this._askExportEveryTime,
    required this._checkUpdates,
    required this._historyRetentionDays,
    required this._processingConcurrency,
    required this._lastWorkspaceType,
    required this._lastProcessMode,
    required this._lastAlgorithm,
    required this._passwordProtectionEnabled,
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
  static const _historyRetentionKey = 'history_retention_days';
  static const _processingConcurrencyKey = 'processing_concurrency';
  static const _lastWorkspaceKey = 'last_workspace_type';
  static const _lastProcessModeKey = 'last_process_mode';
  static const _lastAlgorithmKey = 'last_algorithm';
  static const _passwordProtectionKey = 'password_protection_enabled';

  final SharedPreferences _preferences;
  AppLanguage _language;
  AppThemePreference _theme;
  bool _askExportEveryTime;
  bool _checkUpdates;
  int _historyRetentionDays;
  int _processingConcurrency;
  WorkspaceType _lastWorkspaceType;
  ProcessMode _lastProcessMode;
  ScrambleAlgorithm _lastAlgorithm;
  bool _passwordProtectionEnabled;
  String? defaultExportPath;
  String? defaultExportTreeUri;
  String? defaultExportLabel;

  AppLanguage get language => _language;
  AppThemePreference get theme => _theme;
  bool get askExportEveryTime => _askExportEveryTime;
  bool get checkUpdates => _checkUpdates;
  int get historyRetentionDays => _historyRetentionDays;
  int get processingConcurrency => _processingConcurrency;
  int get effectiveProcessingConcurrency => _processingConcurrency == 0
      ? math.min(4, math.max(1, Platform.numberOfProcessors ~/ 2))
      : _processingConcurrency;
  WorkspaceType get lastWorkspaceType => _lastWorkspaceType;
  ProcessMode get lastProcessMode => _lastProcessMode;
  ScrambleAlgorithm get lastAlgorithm => _lastAlgorithm;
  bool get passwordProtectionEnabled => _passwordProtectionEnabled;

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
      historyRetentionDays: _validatedRetention(
        preferences.getInt(_historyRetentionKey),
      ),
      processingConcurrency: _validatedConcurrency(
        preferences.getInt(_processingConcurrencyKey),
      ),
      lastWorkspaceType: WorkspaceType.values.firstWhere(
        (item) => item.name == preferences.getString(_lastWorkspaceKey),
        orElse: () => WorkspaceType.image,
      ),
      lastProcessMode: ProcessMode.values.firstWhere(
        (item) => item.name == preferences.getString(_lastProcessModeKey),
        orElse: () => ProcessMode.scramble,
      ),
      lastAlgorithm: ScrambleAlgorithm.values.firstWhere(
        (item) => item.id == preferences.getString(_lastAlgorithmKey),
        orElse: () => ScrambleAlgorithm.composite,
      ),
      passwordProtectionEnabled:
          preferences.getBool(_passwordProtectionKey) ?? false,
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

  Future<void> setHistoryRetentionDays(int value) async {
    final validated = _validatedRetention(value);
    if (_historyRetentionDays == validated) return;
    _historyRetentionDays = validated;
    await _preferences.setInt(_historyRetentionKey, validated);
    notifyListeners();
  }

  Future<void> setProcessingConcurrency(int value) async {
    final validated = _validatedConcurrency(value);
    if (_processingConcurrency == validated) return;
    _processingConcurrency = validated;
    await _preferences.setInt(_processingConcurrencyKey, validated);
    notifyListeners();
  }

  Future<void> setProcessingDefaults({
    required WorkspaceType workspaceType,
    required ProcessMode mode,
    required ScrambleAlgorithm algorithm,
    required bool passwordProtectionEnabled,
  }) async {
    _lastWorkspaceType = workspaceType;
    _lastProcessMode = mode;
    _lastAlgorithm = algorithm;
    _passwordProtectionEnabled = passwordProtectionEnabled;
    await Future.wait([
      _preferences.setString(_lastWorkspaceKey, workspaceType.name),
      _preferences.setString(_lastProcessModeKey, mode.name),
      _preferences.setString(_lastAlgorithmKey, algorithm.id),
      _preferences.setBool(_passwordProtectionKey, passwordProtectionEnabled),
    ]);
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

  static int _validatedRetention(int? value) =>
      const {0, 1, 7, 30, 90}.contains(value) ? value! : 7;

  static int _validatedConcurrency(int? value) =>
      const {0, 1, 2, 4, 8}.contains(value) ? value! : 0;
}

import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'models.dart';

enum AppLanguage { simplified, traditional }

enum AppThemePreference { system, light, dark }

class WorkspaceSettingsProfile {
  const WorkspaceSettingsProfile({
    required this.mode,
    required this.algorithm,
    required this.scrambleAlgorithm,
    required this.passwordProtectionEnabled,
    required this.compressionEnabled,
    required this.compressionFormat,
    required this.compressionGrouping,
    required this.selectedArchivePasswordProfileId,
  });

  final ProcessMode mode;
  final ScrambleAlgorithm algorithm;
  final ScrambleAlgorithm scrambleAlgorithm;
  final bool passwordProtectionEnabled;
  final bool compressionEnabled;
  final CompressionArchiveFormat compressionFormat;
  final CompressionGrouping compressionGrouping;
  final String? selectedArchivePasswordProfileId;

  WorkspaceSettingsProfile copyWith({
    ProcessMode? mode,
    ScrambleAlgorithm? algorithm,
    ScrambleAlgorithm? scrambleAlgorithm,
    bool? passwordProtectionEnabled,
    bool? compressionEnabled,
    CompressionArchiveFormat? compressionFormat,
    CompressionGrouping? compressionGrouping,
    Object? selectedArchivePasswordProfileId = _unchanged,
  }) => WorkspaceSettingsProfile(
    mode: mode ?? this.mode,
    algorithm: algorithm ?? this.algorithm,
    scrambleAlgorithm: scrambleAlgorithm ?? this.scrambleAlgorithm,
    passwordProtectionEnabled:
        passwordProtectionEnabled ?? this.passwordProtectionEnabled,
    compressionEnabled: compressionEnabled ?? this.compressionEnabled,
    compressionFormat: compressionFormat ?? this.compressionFormat,
    compressionGrouping: compressionGrouping ?? this.compressionGrouping,
    selectedArchivePasswordProfileId:
        identical(selectedArchivePasswordProfileId, _unchanged)
        ? this.selectedArchivePasswordProfileId
        : selectedArchivePasswordProfileId as String?,
  );

  static const _unchanged = Object();
}

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
    required this._workspaceProfiles,
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

  // Legacy keys are kept as a one-time migration source and as downgrade data.
  static const _lastProcessModeKey = 'last_process_mode';
  static const _lastAlgorithmKey = 'last_algorithm';
  static const _passwordProtectionKey = 'password_protection_enabled';
  static const _compressionEnabledKey = 'compression_enabled';
  static const _compressionFormatKey = 'compression_format';
  static const _compressionGroupingKey = 'compression_grouping';
  static const _selectedArchivePasswordProfileKey =
      'selected_archive_password_profile';

  static const _modeSuffix = 'mode';
  static const _algorithmSuffix = 'algorithm';
  static const _scrambleAlgorithmSuffix = 'scramble_algorithm';
  static const _passwordProtectionSuffix = 'password_protection_enabled';
  static const _compressionEnabledSuffix = 'compression_enabled';
  static const _compressionFormatSuffix = 'compression_format';
  static const _compressionGroupingSuffix = 'compression_grouping';
  static const _archivePasswordProfileSuffix = 'archive_password_profile';

  final SharedPreferences _preferences;
  final Map<WorkspaceType, WorkspaceSettingsProfile> _workspaceProfiles;
  AppLanguage _language;
  AppThemePreference _theme;
  bool _askExportEveryTime;
  bool _checkUpdates;
  int _historyRetentionDays;
  int _processingConcurrency;
  WorkspaceType _lastWorkspaceType;
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
  ProcessMode get lastProcessMode => activeWorkspaceProfile.mode;
  ScrambleAlgorithm get lastAlgorithm => activeWorkspaceProfile.algorithm;
  bool get passwordProtectionEnabled =>
      activeWorkspaceProfile.passwordProtectionEnabled;
  bool get compressionEnabled => activeWorkspaceProfile.compressionEnabled;
  CompressionArchiveFormat get compressionFormat =>
      activeWorkspaceProfile.compressionFormat;
  CompressionGrouping get compressionGrouping =>
      activeWorkspaceProfile.compressionGrouping;
  String? get selectedArchivePasswordProfileId =>
      activeWorkspaceProfile.selectedArchivePasswordProfileId;
  WorkspaceSettingsProfile get activeWorkspaceProfile =>
      profileFor(_lastWorkspaceType);

  WorkspaceSettingsProfile profileFor(WorkspaceType workspaceType) =>
      _workspaceProfiles[_normalizedWorkspace(workspaceType)] ??
      _defaultProfile(_normalizedWorkspace(workspaceType));

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
    final lastWorkspace = WorkspaceType.values.firstWhere(
      (item) =>
          item != WorkspaceType.mixed &&
          item.name == preferences.getString(_lastWorkspaceKey),
      orElse: () => WorkspaceType.image,
    );
    final profiles = <WorkspaceType, WorkspaceSettingsProfile>{
      for (final workspace in const [WorkspaceType.image, WorkspaceType.text])
        workspace: _loadWorkspaceProfile(
          preferences,
          workspace,
          migrateLegacy: workspace == lastWorkspace,
        ),
    };
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
      lastWorkspaceType: lastWorkspace,
      workspaceProfiles: profiles,
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
    required ScrambleAlgorithm scrambleAlgorithm,
    required bool passwordProtectionEnabled,
  }) async {
    if (workspaceType == WorkspaceType.mixed) return;
    final profile = profileFor(workspaceType).copyWith(
      mode: mode,
      algorithm: algorithm,
      scrambleAlgorithm: scrambleAlgorithm,
      passwordProtectionEnabled: passwordProtectionEnabled,
    );
    _workspaceProfiles[workspaceType] = profile;
    _lastWorkspaceType = workspaceType;
    await Future.wait([
      _preferences.setString(_lastWorkspaceKey, workspaceType.name),
      _preferences.setString(
        _workspaceKey(workspaceType, _modeSuffix),
        mode.name,
      ),
      _preferences.setString(
        _workspaceKey(workspaceType, _algorithmSuffix),
        algorithm.id,
      ),
      _preferences.setString(
        _workspaceKey(workspaceType, _scrambleAlgorithmSuffix),
        scrambleAlgorithm.id,
      ),
      _preferences.setBool(
        _workspaceKey(workspaceType, _passwordProtectionSuffix),
        passwordProtectionEnabled,
      ),
      _preferences.setString(_lastProcessModeKey, mode.name),
      _preferences.setString(_lastAlgorithmKey, algorithm.id),
      _preferences.setBool(_passwordProtectionKey, passwordProtectionEnabled),
    ]);
  }

  Future<void> setCompressionEnabled(
    bool value, {
    WorkspaceType? workspaceType,
  }) async {
    final workspace = _normalizedWorkspace(workspaceType ?? _lastWorkspaceType);
    final current = profileFor(workspace);
    if (current.compressionEnabled == value) return;
    _workspaceProfiles[workspace] = current.copyWith(compressionEnabled: value);
    await Future.wait([
      _preferences.setBool(
        _workspaceKey(workspace, _compressionEnabledSuffix),
        value,
      ),
      if (workspace == _lastWorkspaceType)
        _preferences.setBool(_compressionEnabledKey, value),
    ]);
    notifyListeners();
  }

  Future<void> setCompressionFormat(
    CompressionArchiveFormat value, {
    WorkspaceType? workspaceType,
  }) async {
    final workspace = _normalizedWorkspace(workspaceType ?? _lastWorkspaceType);
    final current = profileFor(workspace);
    if (current.compressionFormat == value) return;
    _workspaceProfiles[workspace] = current.copyWith(compressionFormat: value);
    await Future.wait([
      _preferences.setString(
        _workspaceKey(workspace, _compressionFormatSuffix),
        value.name,
      ),
      if (workspace == _lastWorkspaceType)
        _preferences.setString(_compressionFormatKey, value.name),
    ]);
    notifyListeners();
  }

  Future<void> setCompressionGrouping(
    CompressionGrouping value, {
    WorkspaceType? workspaceType,
  }) async {
    final workspace = _normalizedWorkspace(workspaceType ?? _lastWorkspaceType);
    final current = profileFor(workspace);
    if (current.compressionGrouping == value) return;
    _workspaceProfiles[workspace] = current.copyWith(
      compressionGrouping: value,
    );
    await Future.wait([
      _preferences.setString(
        _workspaceKey(workspace, _compressionGroupingSuffix),
        value.name,
      ),
      if (workspace == _lastWorkspaceType)
        _preferences.setString(_compressionGroupingKey, value.name),
    ]);
    notifyListeners();
  }

  Future<void> setSelectedArchivePasswordProfile(
    String? id, {
    WorkspaceType? workspaceType,
  }) async {
    final workspace = _normalizedWorkspace(workspaceType ?? _lastWorkspaceType);
    final current = profileFor(workspace);
    if (current.selectedArchivePasswordProfileId == id) return;
    _workspaceProfiles[workspace] = current.copyWith(
      selectedArchivePasswordProfileId: id,
    );
    final key = _workspaceKey(workspace, _archivePasswordProfileSuffix);
    if (id == null) {
      await _preferences.remove(key);
      if (workspace == _lastWorkspaceType) {
        await _preferences.remove(_selectedArchivePasswordProfileKey);
      }
    } else {
      await _preferences.setString(key, id);
      if (workspace == _lastWorkspaceType) {
        await _preferences.setString(_selectedArchivePasswordProfileKey, id);
      }
    }
    notifyListeners();
  }

  Future<void> clearArchivePasswordProfileReferences(String id) async {
    var changed = false;
    for (final workspace in const [WorkspaceType.image, WorkspaceType.text]) {
      final current = profileFor(workspace);
      if (current.selectedArchivePasswordProfileId != id) continue;
      changed = true;
      _workspaceProfiles[workspace] = current.copyWith(
        selectedArchivePasswordProfileId: null,
      );
      await _preferences.remove(
        _workspaceKey(workspace, _archivePasswordProfileSuffix),
      );
    }
    if (changed) {
      await _preferences.remove(_selectedArchivePasswordProfileKey);
      notifyListeners();
    }
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

  static WorkspaceSettingsProfile _loadWorkspaceProfile(
    SharedPreferences preferences,
    WorkspaceType workspace, {
    required bool migrateLegacy,
  }) {
    final defaults = _defaultProfile(workspace);
    String? migratedString(String suffix, String legacyKey) =>
        preferences.getString(_workspaceKey(workspace, suffix)) ??
        (migrateLegacy ? preferences.getString(legacyKey) : null);
    bool? migratedBool(String suffix, String legacyKey) =>
        preferences.getBool(_workspaceKey(workspace, suffix)) ??
        (migrateLegacy ? preferences.getBool(legacyKey) : null);

    final algorithm = ScrambleAlgorithm.values.firstWhere(
      (item) => item.id == migratedString(_algorithmSuffix, _lastAlgorithmKey),
      orElse: () => defaults.algorithm,
    );
    final savedScrambleAlgorithm = preferences.getString(
      _workspaceKey(workspace, _scrambleAlgorithmSuffix),
    );
    final scrambleAlgorithm = ScrambleAlgorithm.values.firstWhere(
      (item) => !item.isAutomatic && item.id == savedScrambleAlgorithm,
      orElse: () =>
          algorithm.isAutomatic ? defaults.scrambleAlgorithm : algorithm,
    );

    return WorkspaceSettingsProfile(
      mode: ProcessMode.values.firstWhere(
        (item) => item.name == migratedString(_modeSuffix, _lastProcessModeKey),
        orElse: () => defaults.mode,
      ),
      algorithm: algorithm,
      scrambleAlgorithm: scrambleAlgorithm,
      passwordProtectionEnabled:
          migratedBool(_passwordProtectionSuffix, _passwordProtectionKey) ??
          defaults.passwordProtectionEnabled,
      compressionEnabled:
          migratedBool(_compressionEnabledSuffix, _compressionEnabledKey) ??
          defaults.compressionEnabled,
      compressionFormat: CompressionArchiveFormat.values.firstWhere(
        (item) =>
            item.name ==
            migratedString(_compressionFormatSuffix, _compressionFormatKey),
        orElse: () => defaults.compressionFormat,
      ),
      compressionGrouping: CompressionGrouping.values.firstWhere(
        (item) =>
            item.name ==
            migratedString(_compressionGroupingSuffix, _compressionGroupingKey),
        orElse: () => defaults.compressionGrouping,
      ),
      selectedArchivePasswordProfileId:
          preferences.getString(
            _workspaceKey(workspace, _archivePasswordProfileSuffix),
          ) ??
          (migrateLegacy
              ? preferences.getString(_selectedArchivePasswordProfileKey)
              : null),
    );
  }

  static WorkspaceSettingsProfile _defaultProfile(WorkspaceType workspace) =>
      const WorkspaceSettingsProfile(
        mode: ProcessMode.scramble,
        algorithm: ScrambleAlgorithm.composite,
        scrambleAlgorithm: ScrambleAlgorithm.composite,
        passwordProtectionEnabled: false,
        compressionEnabled: false,
        compressionFormat: CompressionArchiveFormat.zip,
        compressionGrouping: CompressionGrouping.perFolder,
        selectedArchivePasswordProfileId: null,
      );

  static WorkspaceType _normalizedWorkspace(WorkspaceType workspace) =>
      workspace == WorkspaceType.mixed ? WorkspaceType.image : workspace;

  static String _workspaceKey(WorkspaceType workspace, String suffix) =>
      'workspace_${_normalizedWorkspace(workspace).name}_$suffix';

  static int _validatedRetention(int? value) =>
      const {0, 1, 7, 30, 90}.contains(value) ? value! : 7;

  static int _validatedConcurrency(int? value) =>
      const {0, 1, 2, 4, 8}.contains(value) ? value! : 0;
}

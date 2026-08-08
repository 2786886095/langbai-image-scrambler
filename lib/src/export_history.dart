import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'models.dart';

class ExportArtifact {
  const ExportArtifact({
    required this.location,
    required this.displayName,
    required this.sha256,
    required this.sizeBytes,
  });

  final String location;
  final String displayName;
  final String sha256;
  final int sizeBytes;

  Map<String, Object> toJson() => {
    'location': location,
    'displayName': displayName,
    'sha256': sha256,
    'sizeBytes': sizeBytes,
  };

  factory ExportArtifact.fromJson(Map<String, dynamic> json) => ExportArtifact(
    location: json['location'] as String? ?? '',
    displayName: json['displayName'] as String? ?? '',
    sha256: json['sha256'] as String? ?? '',
    sizeBytes: (json['sizeBytes'] as num?)?.toInt() ?? 0,
  );
}

class ExportHistoryEntry {
  const ExportHistoryEntry({
    required this.id,
    required this.createdAt,
    required this.workspaceType,
    required this.mode,
    required this.targetLabel,
    required this.artifacts,
    required this.createdDirectories,
    this.undoneAt,
    this.deletedCount = 0,
    this.modifiedSkippedCount = 0,
    this.missingCount = 0,
    this.failedCount = 0,
  });

  final String id;
  final DateTime createdAt;
  final WorkspaceType workspaceType;
  final ProcessMode mode;
  final String targetLabel;
  final List<ExportArtifact> artifacts;
  final List<String> createdDirectories;
  final DateTime? undoneAt;
  final int deletedCount;
  final int modifiedSkippedCount;
  final int missingCount;
  final int failedCount;

  bool get canUndo => undoneAt == null && artifacts.isNotEmpty;

  ExportHistoryEntry withUndoResult(UndoResult result, DateTime time) =>
      ExportHistoryEntry(
        id: id,
        createdAt: createdAt,
        workspaceType: workspaceType,
        mode: mode,
        targetLabel: targetLabel,
        artifacts: artifacts,
        createdDirectories: createdDirectories,
        undoneAt: time,
        deletedCount: result.deleted,
        modifiedSkippedCount: result.modified,
        missingCount: result.missing,
        failedCount: result.failed,
      );

  Map<String, Object?> toJson() => {
    'id': id,
    'createdAt': createdAt.toIso8601String(),
    'workspaceType': workspaceType.name,
    'mode': mode.name,
    'targetLabel': targetLabel,
    'artifacts': artifacts.map((item) => item.toJson()).toList(),
    'createdDirectories': createdDirectories,
    'undoneAt': undoneAt?.toIso8601String(),
    'deletedCount': deletedCount,
    'modifiedSkippedCount': modifiedSkippedCount,
    'missingCount': missingCount,
    'failedCount': failedCount,
  };

  factory ExportHistoryEntry.fromJson(Map<String, dynamic> json) {
    final workspaceName = json['workspaceType'] as String?;
    final modeName = json['mode'] as String?;
    return ExportHistoryEntry(
      id: json['id'] as String? ?? '',
      createdAt:
          DateTime.tryParse(json['createdAt'] as String? ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0),
      workspaceType: WorkspaceType.values.firstWhere(
        (item) => item.name == workspaceName,
        orElse: () => WorkspaceType.image,
      ),
      mode: ProcessMode.values.firstWhere(
        (item) => item.name == modeName,
        orElse: () => ProcessMode.scramble,
      ),
      targetLabel: json['targetLabel'] as String? ?? '',
      artifacts: (json['artifacts'] as List<dynamic>? ?? const [])
          .whereType<Map>()
          .map(
            (item) => ExportArtifact.fromJson(Map<String, dynamic>.from(item)),
          )
          .toList(growable: false),
      createdDirectories:
          (json['createdDirectories'] as List<dynamic>? ?? const [])
              .whereType<String>()
              .toList(growable: false),
      undoneAt: DateTime.tryParse(json['undoneAt'] as String? ?? ''),
      deletedCount: (json['deletedCount'] as num?)?.toInt() ?? 0,
      modifiedSkippedCount:
          (json['modifiedSkippedCount'] as num?)?.toInt() ?? 0,
      missingCount: (json['missingCount'] as num?)?.toInt() ?? 0,
      failedCount: (json['failedCount'] as num?)?.toInt() ?? 0,
    );
  }
}

class UndoResult {
  const UndoResult({
    this.deleted = 0,
    this.modified = 0,
    this.missing = 0,
    this.failed = 0,
  });

  final int deleted;
  final int modified;
  final int missing;
  final int failed;
}

class ExportHistoryStore {
  ExportHistoryStore._({this._preferences, DateTime Function()? now})
    : _now = now ?? DateTime.now;

  static const _storageKey = 'export_history_v1';

  final SharedPreferences? _preferences;
  final DateTime Function() _now;
  final List<ExportHistoryEntry> _entries = [];

  List<ExportHistoryEntry> get entries => List.unmodifiable(_entries);

  static ExportHistoryStore memory({DateTime Function()? now}) =>
      ExportHistoryStore._(now: now);

  static Future<ExportHistoryStore> load({
    required int retentionDays,
    DateTime Function()? now,
  }) async {
    final preferences = await SharedPreferences.getInstance();
    final store = ExportHistoryStore._(preferences: preferences, now: now);
    final encoded = preferences.getString(_storageKey);
    if (encoded != null && encoded.isNotEmpty) {
      try {
        final list = jsonDecode(encoded) as List<dynamic>;
        store._entries.addAll(
          list.whereType<Map>().map(
            (item) =>
                ExportHistoryEntry.fromJson(Map<String, dynamic>.from(item)),
          ),
        );
      } catch (_) {
        await preferences.remove(_storageKey);
      }
    }
    await store.cleanup(retentionDays);
    return store;
  }

  Future<void> add(ExportHistoryEntry entry) async {
    _entries.insert(0, entry);
    await _persist();
  }

  Future<void> markUndone(String id, UndoResult result) async {
    final index = _entries.indexWhere((entry) => entry.id == id);
    if (index < 0) return;
    _entries[index] = _entries[index].withUndoResult(result, _now());
    await _persist();
  }

  Future<int> cleanup(int retentionDays) async {
    if (retentionDays == 0) return 0;
    final cutoff = _now().subtract(Duration(days: retentionDays));
    final before = _entries.length;
    _entries.removeWhere((entry) => entry.createdAt.isBefore(cutoff));
    final removed = before - _entries.length;
    if (removed > 0) await _persist();
    return removed;
  }

  Future<void> _persist() async {
    final preferences = _preferences;
    if (preferences == null) return;
    await preferences.setString(
      _storageKey,
      jsonEncode(_entries.map((entry) => entry.toJson()).toList()),
    );
  }
}

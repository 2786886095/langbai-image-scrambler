import 'dart:async';

import 'package:cross_file/cross_file.dart';
import 'package:flutter/foundation.dart';

import 'app_settings.dart';
import 'archive_service.dart';
import 'export_history.dart';
import 'file_service.dart';
import 'image_processor.dart';
import 'models.dart';
import 'password_vault.dart';
import 'text_processor.dart';
import 'update_service.dart';

class AppController extends ChangeNotifier {
  AppController(
    this._settings, {
    FileService? fileService,
    ImageProcessor? imageProcessor,
    TextProcessor? textProcessor,
    UpdateService? updateService,
    ExportHistoryStore? historyStore,
    ArchiveService? archiveService,
    this._passwordVault,
  }) : _fileService = fileService ?? FileService(),
       _imageProcessor = imageProcessor ?? ImageProcessor(),
       _textProcessor = textProcessor ?? const TextProcessor(),
       _updateService = updateService ?? UpdateService(),
       _historyStore = historyStore ?? ExportHistoryStore.memory(),
       _archiveService = archiveService ?? ArchiveService() {
    workspaceType = _settings.lastWorkspaceType;
    _applyWorkspaceProfile(_settings.profileFor(workspaceType));
    password = _passwordVault?.imageProcessingPassword ?? '';
    manualSeed = _passwordVault?.imageManualSeed ?? '';
    unawaited(_fileService.initializeSharedImports(_enqueueSharedImport));
  }

  final AppSettings _settings;
  final FileService _fileService;
  final ImageProcessor _imageProcessor;
  final TextProcessor _textProcessor;
  final UpdateService _updateService;
  final ExportHistoryStore _historyStore;
  final ArchiveService _archiveService;

  AppSettings get settings => _settings;
  final PasswordVault? _passwordVault;

  late ProcessMode mode;
  late WorkspaceType workspaceType;
  late ScrambleAlgorithm algorithm;
  late ScrambleAlgorithm _scrambleAlgorithm;
  late bool _scramblePasswordEnabled;
  ImportBatch? batch;
  bool passwordEnabled = false;
  String password = '';
  String manualSeed = '';
  bool isProcessing = false;
  bool stopRequested = false;
  double progress = 0;
  String statusKey = 'ready';
  String? detailMessage;
  UpdateInfo? availableUpdate;
  bool checkingUpdate = false;
  bool installingUpdate = false;
  UpdateProgress? updateProgress;
  String? updateError;
  String? undoingHistoryId;
  String? openingLocationId;
  String? lastExportHistoryId;
  bool detailMessageIsError = false;
  final List<SharedImportRequest> _pendingSharedImports = [];
  final List<PreparedArchive> _pendingPreparedArchives = [];
  ExportTarget? _pendingArchiveTarget;

  List<ImageTask> get tasks => batch?.tasks ?? const [];
  int get completedCount =>
      tasks.where((task) => task.status == TaskStatus.completed).length;
  int get failedCount =>
      tasks.where((task) => task.status == TaskStatus.failed).length;
  bool get hasFailed => failedCount > 0;
  bool get hasPendingArchiveExport => _pendingPreparedArchives.isNotEmpty;
  bool get canStart => tasks.isNotEmpty && !isProcessing;
  bool get canInstallUpdate =>
      availableUpdate != null &&
      !installingUpdate &&
      !isProcessing &&
      !hasPendingArchiveExport;
  FileService get fileService => _fileService;
  List<ExportHistoryEntry> get exportHistory => _historyStore.entries;
  ExportHistoryEntry? get lastExportEntry {
    final id = lastExportHistoryId;
    if (id == null) return null;
    for (final entry in exportHistory) {
      if (entry.id == id) return entry;
    }
    return null;
  }

  bool get canOpenLastRestoreOutput =>
      mode == ProcessMode.restore &&
      !isProcessing &&
      completedCount > 0 &&
      lastExportEntry?.locationToReveal != null;
  int get effectiveProcessingConcurrency =>
      _settings.effectiveProcessingConcurrency;
  SharedImportRequest? get pendingSharedImport =>
      _pendingSharedImports.isEmpty ? null : _pendingSharedImports.first;
  bool get hasMixedBatch => batch?.isMixed ?? false;
  WorkspaceSettingsProfile get _workspaceProfile =>
      _settings.profileFor(workspaceType);
  bool get compressionEnabled => _workspaceProfile.compressionEnabled;
  CompressionArchiveFormat get compressionFormat =>
      _workspaceProfile.compressionFormat;
  CompressionGrouping get compressionGrouping =>
      _workspaceProfile.compressionGrouping;
  List<PasswordProfile> get archivePasswordProfiles =>
      _passwordVault?.profiles ?? const [];
  PasswordProfile? get selectedArchivePasswordProfile =>
      _passwordVault?.find(_workspaceProfile.selectedArchivePasswordProfileId);
  bool get canUseCompression => mode == ProcessMode.scramble;

  void setMode(ProcessMode value) {
    if (isProcessing || mode == value) return;
    _discardPendingArchiveExport();
    if (mode == ProcessMode.scramble) {
      if (!algorithm.isAutomatic) _scrambleAlgorithm = algorithm;
      _scramblePasswordEnabled = passwordEnabled;
    }
    mode = value;
    algorithm = value == ProcessMode.restore
        ? ScrambleAlgorithm.auto
        : _scrambleAlgorithm;
    passwordEnabled =
        value == ProcessMode.scramble &&
        _scramblePasswordEnabled &&
        !algorithm.isCompatibility;
    lastExportHistoryId = null;
    _resetTaskStates();
    _persistProcessingDefaults();
    notifyListeners();
  }

  void setWorkspaceType(WorkspaceType value) {
    if (isProcessing ||
        value == WorkspaceType.mixed ||
        workspaceType == value) {
      return;
    }
    _discardPendingArchiveExport();
    final temporaryRoots = batch?.temporaryRoots ?? const <String>[];
    workspaceType = value;
    _applyWorkspaceProfile(_settings.profileFor(value));
    batch = null;
    progress = 0;
    statusKey = 'ready';
    detailMessage = null;
    detailMessageIsError = false;
    lastExportHistoryId = null;
    unawaited(_fileService.cleanupTemporaryRoots(temporaryRoots));
    _persistProcessingDefaults();
    notifyListeners();
  }

  void setAlgorithm(ScrambleAlgorithm value) {
    if (isProcessing || algorithm == value) return;
    _discardPendingArchiveExport();
    algorithm = value;
    if (mode == ProcessMode.scramble && !value.isAutomatic) {
      _scrambleAlgorithm = value;
      if (value.isCompatibility) _scramblePasswordEnabled = false;
      passwordEnabled = !value.isCompatibility && _scramblePasswordEnabled;
    }
    _persistProcessingDefaults();
    notifyListeners();
  }

  void setPasswordEnabled(bool value) {
    if (algorithm.isCompatibility || isProcessing) return;
    _discardPendingArchiveExport();
    passwordEnabled = value;
    _scramblePasswordEnabled = value;
    _persistProcessingDefaults();
    notifyListeners();
  }

  void setPassword(String value) {
    final discardedPendingExport = hasPendingArchiveExport;
    _discardPendingArchiveExport();
    password = value;
    final passwordVault = _passwordVault;
    if (passwordVault != null) {
      unawaited(passwordVault.setImageProcessingPassword(value));
    }
    if (discardedPendingExport) notifyListeners();
  }

  void setManualSeed(String value) {
    final discardedPendingExport = hasPendingArchiveExport;
    _discardPendingArchiveExport();
    manualSeed = value;
    final passwordVault = _passwordVault;
    if (passwordVault != null) {
      unawaited(passwordVault.setImageManualSeed(value));
    }
    if (discardedPendingExport) notifyListeners();
  }

  Future<void> setCompressionEnabled(bool value) async {
    if (isProcessing) return;
    _discardPendingArchiveExport();
    await _settings.setCompressionEnabled(value, workspaceType: workspaceType);
    notifyListeners();
  }

  Future<void> setCompressionFormat(CompressionArchiveFormat value) async {
    if (isProcessing) return;
    _discardPendingArchiveExport();
    await _settings.setCompressionFormat(value, workspaceType: workspaceType);
    notifyListeners();
  }

  Future<void> setCompressionGrouping(CompressionGrouping value) async {
    if (isProcessing) return;
    _discardPendingArchiveExport();
    await _settings.setCompressionGrouping(value, workspaceType: workspaceType);
    notifyListeners();
  }

  Future<void> setArchivePasswordProfile(String? id) async {
    if (isProcessing) return;
    _discardPendingArchiveExport();
    await _settings.setSelectedArchivePasswordProfile(
      id,
      workspaceType: workspaceType,
    );
    notifyListeners();
  }

  Future<PasswordProfile> addArchivePasswordProfile({
    required String name,
    required String password,
  }) async {
    final profile = await _passwordVault!.add(name: name, password: password);
    await setArchivePasswordProfile(profile.id);
    return profile;
  }

  Future<void> updateArchivePasswordProfile(
    String id, {
    required String name,
    required String password,
  }) async {
    await _passwordVault!.update(id, name: name, password: password);
    notifyListeners();
  }

  Future<void> deleteArchivePasswordProfile(String id) async {
    await _passwordVault!.delete(id);
    await _settings.clearArchivePasswordProfileReferences(id);
    notifyListeners();
  }

  Future<void> pickFiles() async {
    await _runImport(() => _fileService.pickFiles(workspaceType));
  }

  Future<void> pickImages() => pickFiles();

  Future<void> pickFolder() async {
    await _runImport(
      () => _fileService.pickFolder(workspaceType: workspaceType),
    );
  }

  Future<void> pickArchives() async {
    if (isProcessing) return;
    try {
      final request = await _fileService.pickArchives();
      if (request != null) _enqueueSharedImport(request);
    } catch (error) {
      detailMessage = _errorText(error);
      detailMessageIsError = true;
      notifyListeners();
    }
  }

  void dismissSharedImport(SharedImportRequest request) {
    _pendingSharedImports.removeWhere((item) => item.id == request.id);
    notifyListeners();
  }

  Future<void> acceptSharedImport(
    SharedImportRequest request, {
    required ProcessMode selectedMode,
    Map<String, String> archivePasswords = const {},
  }) async {
    if (isProcessing) return;
    final imported = await _fileService.importShared(
      request,
      archivePasswords: archivePasswords,
    );
    if (imported.tasks.isEmpty) {
      await _fileService.cleanupTemporaryRoots(imported.temporaryRoots);
      throw SharedImportException(
        imported.skippedCount > 0 ? '没有可处理的图片或 TXT' : '导入内容为空',
      );
    }
    batch = _mergeBatches(batch, imported);
    workspaceType = batch!.containsImages
        ? WorkspaceType.image
        : WorkspaceType.text;
    final profile = _settings.profileFor(workspaceType);
    _scrambleAlgorithm = profile.scrambleAlgorithm;
    _scramblePasswordEnabled = profile.passwordProtectionEnabled;
    mode = selectedMode;
    algorithm = selectedMode == ProcessMode.restore
        ? ScrambleAlgorithm.auto
        : _scrambleAlgorithm;
    passwordEnabled =
        selectedMode == ProcessMode.scramble &&
        workspaceType == WorkspaceType.image &&
        _scramblePasswordEnabled &&
        !algorithm.isCompatibility;
    _resetTaskStates();
    progress = 0;
    statusKey = 'ready';
    detailMessage = imported.skippedCount > 0
        ? '已导入 ${imported.tasks.length} 个文件，跳过 ${imported.skippedCount} 个其他文件'
        : '已通过分享导入 ${imported.tasks.length} 个文件';
    detailMessageIsError = false;
    lastExportHistoryId = null;
    _pendingSharedImports.removeWhere((item) => item.id == request.id);
    _persistProcessingDefaults();
    notifyListeners();
  }

  void _enqueueSharedImport(SharedImportRequest request) {
    if (_pendingSharedImports.any((item) => item.id == request.id)) return;
    _pendingSharedImports.add(request);
    notifyListeners();
  }

  Future<void> importDropped(List<XFile> files) async {
    await _runImport(
      () => _fileService.importDropped(files, workspaceType: workspaceType),
    );
  }

  Future<void> _runImport(Future<ImportBatch?> Function() action) async {
    if (isProcessing) return;
    detailMessage = null;
    detailMessageIsError = false;
    try {
      final imported = await action();
      if (imported == null) return;
      _discardPendingArchiveExport();
      batch = _mergeBatches(batch, imported);
      progress = 0;
      lastExportHistoryId = null;
      statusKey = batch!.tasks.isEmpty
          ? (workspaceType == WorkspaceType.text
                ? 'textFolderEmpty'
                : 'folderEmpty')
          : 'ready';
    } catch (error) {
      detailMessage = _errorText(error);
      detailMessageIsError = true;
    }
    notifyListeners();
  }

  void clear() {
    if (isProcessing) return;
    _discardPendingArchiveExport();
    final temporaryRoots = batch?.temporaryRoots ?? const <String>[];
    batch = null;
    progress = 0;
    statusKey = 'ready';
    detailMessage = null;
    detailMessageIsError = false;
    lastExportHistoryId = null;
    unawaited(_fileService.cleanupTemporaryRoots(temporaryRoots));
    notifyListeners();
  }

  void retryFailed() {
    if (isProcessing || batch == null) return;
    final retry = tasks
        .where((task) => task.status == TaskStatus.failed)
        .map((task) => task.copyForRetry())
        .toList();
    if (retry.isEmpty) return;
    _discardPendingArchiveExport();
    batch = ImportBatch(
      tasks: retry,
      isFolder: batch!.isFolder,
      rootName: batch!.rootName,
      workspaceType: batch!.workspaceType,
      temporaryRoots: batch!.temporaryRoots,
      skippedCount: batch!.skippedCount,
    );
    progress = 0;
    statusKey = 'ready';
    detailMessage = null;
    detailMessageIsError = false;
    lastExportHistoryId = null;
    notifyListeners();
  }

  void requestStop() {
    stopRequested = true;
    notifyListeners();
  }

  Future<void> setHistoryRetentionDays(int value) async {
    await _settings.setHistoryRetentionDays(value);
    await _historyStore.cleanup(value);
    notifyListeners();
  }

  Future<void> setProcessingConcurrency(int value) async {
    await _settings.setProcessingConcurrency(value);
    notifyListeners();
  }

  Future<void> cleanupExportHistory() async {
    final removed = await _historyStore.cleanup(_settings.historyRetentionDays);
    if (removed > 0) notifyListeners();
  }

  Future<void> recordExternalExport({
    required ExportHistoryKind kind,
    required ProcessMode mode,
    required String location,
    required String displayName,
    required String sha256,
    required int sizeBytes,
  }) async {
    final entry = ExportHistoryEntry(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      createdAt: DateTime.now(),
      workspaceType: WorkspaceType.image,
      mode: mode,
      targetLabel: location,
      artifacts: [
        ExportArtifact(
          location: location,
          displayName: displayName,
          sha256: sha256,
          sizeBytes: sizeBytes,
        ),
      ],
      createdDirectories: const [],
      revealLocation: location,
      kind: kind,
    );
    await _historyStore.add(entry);
    lastExportHistoryId = entry.id;
    await _historyStore.cleanup(_settings.historyRetentionDays);
    notifyListeners();
  }

  Future<UndoResult> undoExport(ExportHistoryEntry entry) async {
    if (!entry.canUndo || undoingHistoryId != null || isProcessing) {
      return const UndoResult();
    }
    undoingHistoryId = entry.id;
    notifyListeners();
    try {
      final result = await _fileService.undoExport(entry);
      await _historyStore.markUndone(entry.id, result);
      return result;
    } finally {
      undoingHistoryId = null;
      notifyListeners();
    }
  }

  Future<bool> openExportLocation(ExportHistoryEntry entry) async {
    if (openingLocationId != null) return false;
    openingLocationId = 'history:${entry.id}';
    notifyListeners();
    try {
      await _fileService.openExportLocation(entry);
      return true;
    } catch (error) {
      detailMessage = _errorText(error);
      detailMessageIsError = true;
      return false;
    } finally {
      openingLocationId = null;
      notifyListeners();
    }
  }

  Future<bool> openTaskOutput(ImageTask task) async {
    final location = task.outputLocation;
    if (location == null || location.isEmpty || openingLocationId != null) {
      return false;
    }
    openingLocationId = 'task:${task.id}';
    notifyListeners();
    try {
      await _fileService.openOutputLocation(location, isDirectory: false);
      return true;
    } catch (error) {
      detailMessage = _errorText(error);
      detailMessageIsError = true;
      return false;
    } finally {
      openingLocationId = null;
      notifyListeners();
    }
  }

  Future<bool> openLastRestoreOutput() async {
    final entry = lastExportEntry;
    return entry == null ? false : openExportLocation(entry);
  }

  Future<void> process() async {
    if (hasPendingArchiveExport) {
      await continuePendingArchiveExport();
      return;
    }
    if (!canStart || batch == null) {
      statusKey = 'selectFirst';
      notifyListeners();
      return;
    }
    if (batch!.containsImages &&
        mode == ProcessMode.scramble &&
        passwordEnabled &&
        password.trim().isEmpty) {
      statusKey = 'invalidPassword';
      notifyListeners();
      return;
    }
    final parsedSeed = manualSeed.trim().isEmpty
        ? null
        : int.tryParse(manualSeed.trim());
    if (batch!.containsImages &&
        mode == ProcessMode.restore &&
        algorithm.needsSeed &&
        parsedSeed == null) {
      statusKey = 'invalidSeed';
      notifyListeners();
      return;
    }

    if (compressionEnabled && canUseCompression) {
      lastExportHistoryId = null;
      final plannedFileNames = _archiveService.plannedFileNames(
        tasks: tasks,
        grouping: compressionGrouping,
        format: compressionFormat,
      );
      final target = await _fileService.chooseArchiveExportTarget(
        fileNames: plannedFileNames,
        settings: _settings,
      );
      if (target == null) {
        statusKey = 'exportCancelled';
        notifyListeners();
        return;
      }
      await _processCompressed(parsedSeed, target);
      return;
    }

    final target = await _fileService.chooseExportTarget(
      batch: batch!,
      mode: mode,
      settings: _settings,
    );
    if (target == null) {
      statusKey = 'exportCancelled';
      notifyListeners();
      return;
    }

    isProcessing = true;
    lastExportHistoryId = null;
    stopRequested = false;
    detailMessage = null;
    detailMessageIsError = false;
    statusKey = 'processing';
    _resetTaskStates();
    notifyListeners();

    final outputs = <SaveOutputResult>[];
    var nextIndex = 0;
    var finishedCount = 0;

    Future<void> worker() async {
      while (true) {
        if (stopRequested || nextIndex >= tasks.length) return;
        final index = nextIndex++;
        final task = tasks[index];
        task.status = TaskStatus.processing;
        notifyListeners();
        try {
          final input = await _fileService.readTask(task);
          late final Uint8List outputBytes;
          if (task.workspaceType == WorkspaceType.image) {
            final result = await _processOne(input, task, parsedSeed);
            task.detectedAlgorithmId = result.algorithm.id;
            outputBytes = Uint8List.fromList(result.bytes);
          } else {
            outputBytes = mode == ProcessMode.scramble
                ? await _textProcessor.encode(input)
                : await _textProcessor.restore(input);
            task.detectedAlgorithmId = 'base64';
          }
          final saved = await _fileService.saveOutput(
            bytes: outputBytes,
            task: task,
            mode: mode,
            target: target,
            workspaceType: task.workspaceType,
          );
          outputs.add(saved);
          task.outputLocation = saved.location;
          task.status = TaskStatus.completed;
        } catch (error) {
          task.status = TaskStatus.failed;
          task.error = _errorText(error);
        }
        finishedCount++;
        progress = finishedCount / tasks.length;
        notifyListeners();
      }
    }

    final workerCount = effectiveProcessingConcurrency.clamp(1, tasks.length);
    await Future.wait(List.generate(workerCount, (_) => worker()));

    if (outputs.isNotEmpty) {
      final createdDirectories = <String>{
        ...target.createdDirectories,
        for (final output in outputs) ...output.createdDirectories,
      }.toList(growable: false);
      final historyEntry = ExportHistoryEntry(
        id: DateTime.now().microsecondsSinceEpoch.toString(),
        createdAt: DateTime.now(),
        workspaceType: batch!.workspaceType,
        mode: mode,
        targetLabel: target.displayLabel.isNotEmpty
            ? target.displayLabel
            : outputs.first.displayName,
        artifacts: outputs
            .map(
              (output) => ExportArtifact(
                location: output.location,
                displayName: output.displayName,
                sha256: output.sha256Digest,
                sizeBytes: output.sizeBytes,
              ),
            )
            .toList(growable: false),
        createdDirectories: createdDirectories,
        revealLocation: _revealLocation(target, outputs),
        revealIsDirectory: _revealIsDirectory(target),
      );
      await _historyStore.add(historyEntry);
      lastExportHistoryId = historyEntry.id;
      await _historyStore.cleanup(_settings.historyRetentionDays);
    }

    isProcessing = false;
    statusKey = failedCount == 0 ? 'allCompleted' : 'partialCompleted';
    notifyListeners();
  }

  Future<void> _processCompressed(int? parsedSeed, ExportTarget target) async {
    isProcessing = true;
    stopRequested = false;
    detailMessage = null;
    detailMessageIsError = false;
    statusKey = 'processing';
    _resetTaskStates();
    notifyListeners();

    final stagedPaths = <String, String>{};
    final prepared = <PreparedArchive>[];
    final remaining = <PreparedArchive>[];
    final outputs = <SaveOutputResult>[];
    var historyRecorded = false;
    var keepPrepared = false;
    var nextIndex = 0;
    var finishedCount = 0;
    try {
      Future<void> worker() async {
        while (true) {
          if (stopRequested || nextIndex >= tasks.length) return;
          final task = tasks[nextIndex++];
          task.status = TaskStatus.processing;
          notifyListeners();
          try {
            final input = await _fileService.readTask(task);
            late final Uint8List outputBytes;
            late final String suffix;
            if (task.workspaceType == WorkspaceType.image) {
              final result = await _processOne(input, task, parsedSeed);
              task.detectedAlgorithmId = result.algorithm.id;
              outputBytes = Uint8List.fromList(result.bytes);
              suffix = '.png';
            } else {
              outputBytes = await _textProcessor.encode(input);
              task.detectedAlgorithmId = 'base64';
              suffix = '.txt';
            }
            stagedPaths[task.id] = await _fileService.stageOutputBytes(
              outputBytes,
              suffix: suffix,
            );
            task.status = TaskStatus.completed;
          } catch (error) {
            task.status = TaskStatus.failed;
            task.error = _errorText(error);
          }
          finishedCount++;
          progress = (finishedCount / tasks.length) * 0.82;
          notifyListeners();
        }
      }

      final workerCount = effectiveProcessingConcurrency.clamp(1, tasks.length);
      await Future.wait(List.generate(workerCount, (_) => worker()));
      if (stopRequested || stagedPaths.isEmpty) {
        statusKey = 'partialCompleted';
        return;
      }

      statusKey = 'creatingArchives';
      progress = 0.86;
      notifyListeners();
      final groups = _archiveService.plan(
        tasks: tasks,
        stagedPaths: stagedPaths,
        grouping: compressionGrouping,
      );
      prepared.addAll(
        await _archiveService.create(
          groups: groups,
          format: compressionFormat,
          password: selectedArchivePasswordProfile?.password,
        ),
      );
      progress = 0.92;
      remaining
        ..clear()
        ..addAll(prepared);
      for (final archive in List<PreparedArchive>.of(remaining)) {
        outputs.add(
          await _fileService.savePreparedArchive(
            sourcePath: archive.path,
            fileName: archive.fileName,
            target: target,
          ),
        );
        remaining.remove(archive);
      }
      progress = 1;
      await _recordHistory(outputs, target);
      historyRecorded = true;
      for (final task in tasks.where(
        (item) => item.status == TaskStatus.completed,
      )) {
        task.outputLocation = target.displayLabel;
      }
      statusKey = failedCount == 0 ? 'allCompleted' : 'partialCompleted';
    } catch (error) {
      final cancelled = error is ExportCancelledException;
      detailMessage = cancelled ? null : _errorText(error);
      detailMessageIsError = !cancelled;
      if (remaining.isNotEmpty) {
        _pendingPreparedArchives
          ..clear()
          ..addAll(remaining);
        _pendingArchiveTarget = target;
        keepPrepared = true;
        statusKey = cancelled ? 'exportPending' : 'exportPendingFailed';
      } else {
        statusKey = cancelled ? 'exportCancelled' : 'partialCompleted';
        if (!cancelled && outputs.isEmpty) {
          for (final task in tasks.where(
            (item) => item.status == TaskStatus.completed,
          )) {
            task.status = TaskStatus.failed;
            task.error = detailMessage;
          }
        }
      }
      if (!historyRecorded && outputs.isNotEmpty) {
        try {
          await _recordHistory(outputs, target);
        } catch (_) {}
      }
    } finally {
      await _fileService.cleanupStagedFiles(stagedPaths.values);
      final disposable = keepPrepared
          ? prepared
                .where((item) => !_pendingPreparedArchives.contains(item))
                .toList(growable: false)
          : prepared;
      await _archiveService.cleanup(disposable);
      if (outputs.isEmpty && !keepPrepared) {
        await _fileService.cleanupUnusedExportTarget(target);
      }
      isProcessing = false;
      notifyListeners();
    }
  }

  Future<void> continuePendingArchiveExport() async {
    if (isProcessing || _pendingPreparedArchives.isEmpty) return;
    final target = _pendingArchiveTarget;
    if (target == null) return;
    isProcessing = true;
    stopRequested = false;
    detailMessage = null;
    detailMessageIsError = false;
    statusKey = 'exportingCached';
    progress = 0.92;
    notifyListeners();

    final pending = List<PreparedArchive>.of(_pendingPreparedArchives);
    final exported = <PreparedArchive>[];
    final outputs = <SaveOutputResult>[];
    try {
      for (var index = 0; index < pending.length; index++) {
        final archive = pending[index];
        outputs.add(
          await _fileService.savePreparedArchive(
            sourcePath: archive.path,
            fileName: archive.fileName,
            target: target,
          ),
        );
        exported.add(archive);
        _pendingPreparedArchives.remove(archive);
        progress = 0.92 + (0.08 * exported.length / pending.length);
        notifyListeners();
      }
      await _recordHistory(outputs, target);
      for (final task in tasks.where(
        (item) => item.status == TaskStatus.completed,
      )) {
        task.outputLocation = target.displayLabel;
      }
      _pendingArchiveTarget = null;
      progress = 1;
      statusKey = failedCount == 0 ? 'allCompleted' : 'partialCompleted';
    } catch (error) {
      final cancelled = error is ExportCancelledException;
      detailMessage = cancelled ? null : _errorText(error);
      detailMessageIsError = !cancelled;
      statusKey = cancelled ? 'exportPending' : 'exportPendingFailed';
      if (outputs.isNotEmpty) {
        try {
          await _recordHistory(outputs, target);
        } catch (_) {}
      }
    } finally {
      await _archiveService.cleanup(exported);
      isProcessing = false;
      notifyListeners();
    }
  }

  void _discardPendingArchiveExport() {
    if (_pendingPreparedArchives.isEmpty && _pendingArchiveTarget == null) {
      return;
    }
    final archives = List<PreparedArchive>.of(_pendingPreparedArchives);
    final target = _pendingArchiveTarget;
    _pendingPreparedArchives.clear();
    _pendingArchiveTarget = null;
    progress = 0;
    statusKey = 'ready';
    detailMessage = null;
    detailMessageIsError = false;
    _resetTaskStates();
    if (archives.isNotEmpty) unawaited(_archiveService.cleanup(archives));
    if (target != null) {
      unawaited(_fileService.cleanupUnusedExportTarget(target));
    }
  }

  Future<void> _recordHistory(
    List<SaveOutputResult> outputs,
    ExportTarget target,
  ) async {
    if (outputs.isEmpty) return;
    final createdDirectories = <String>{
      ...target.createdDirectories,
      for (final output in outputs) ...output.createdDirectories,
    }.toList(growable: false);
    final historyEntry = ExportHistoryEntry(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      createdAt: DateTime.now(),
      workspaceType: batch!.workspaceType,
      mode: mode,
      targetLabel: target.displayLabel.isNotEmpty
          ? target.displayLabel
          : outputs.first.displayName,
      artifacts: outputs
          .map(
            (output) => ExportArtifact(
              location: output.location,
              displayName: output.displayName,
              sha256: output.sha256Digest,
              sizeBytes: output.sizeBytes,
            ),
          )
          .toList(growable: false),
      createdDirectories: createdDirectories,
      revealLocation: _revealLocation(target, outputs),
      revealIsDirectory: _revealIsDirectory(target),
    );
    await _historyStore.add(historyEntry);
    lastExportHistoryId = historyEntry.id;
    await _historyStore.cleanup(_settings.historyRetentionDays);
  }

  Future<ProcessedImage> _processOne(
    Uint8List bytes,
    ImageTask task,
    int? parsedSeed,
  ) {
    if (mode == ProcessMode.scramble) {
      return _imageProcessor.scramble(
        inputBytes: bytes,
        sourceName: task.originalName,
        algorithm: algorithm,
        password: passwordEnabled ? password : null,
      );
    }
    return _imageProcessor.restore(
      inputBytes: bytes,
      requestedAlgorithm: algorithm,
      password: password.trim().isEmpty ? null : password,
      manualSeed: parsedSeed,
    );
  }

  String? _revealLocation(ExportTarget target, List<SaveOutputResult> outputs) {
    if (target.singleFile) {
      return outputs.isEmpty ? null : outputs.first.location;
    }
    if (target.createdDirectories.length == 1) {
      return target.createdDirectories.first;
    }
    if (target.isAndroidTree) return target.treeUri;
    return target.path ?? (outputs.isEmpty ? null : outputs.first.location);
  }

  bool _revealIsDirectory(ExportTarget target) => !target.singleFile;

  ImportBatch _mergeBatches(ImportBatch? current, ImportBatch imported) {
    if (current == null) return imported;
    final tasks = [...current.tasks, ...imported.tasks];
    final containsImages = tasks.any(
      (task) => task.workspaceType == WorkspaceType.image,
    );
    final containsText = tasks.any(
      (task) => task.workspaceType == WorkspaceType.text,
    );
    final combinedWorkspace = containsImages && containsText
        ? WorkspaceType.mixed
        : containsText
        ? WorkspaceType.text
        : WorkspaceType.image;
    return ImportBatch(
      tasks: tasks,
      isFolder: current.isFolder || imported.isFolder,
      rootName: current.rootName.isNotEmpty
          ? current.rootName
          : imported.rootName,
      workspaceType: combinedWorkspace,
      temporaryRoots: [...current.temporaryRoots, ...imported.temporaryRoots],
      skippedCount: current.skippedCount + imported.skippedCount,
    );
  }

  Future<bool> checkForUpdates() async {
    if (checkingUpdate) return availableUpdate != null;
    checkingUpdate = true;
    detailMessage = null;
    notifyListeners();
    try {
      availableUpdate = await _updateService.check();
      if (availableUpdate == null) statusKey = 'noUpdate';
    } catch (_) {
      statusKey = 'updateCheckFailed';
    } finally {
      checkingUpdate = false;
      notifyListeners();
    }
    return availableUpdate != null;
  }

  Future<void> installUpdate() async {
    final update = availableUpdate;
    if (update == null || !canInstallUpdate) return;
    installingUpdate = true;
    updateProgress = const UpdateProgress(stage: UpdateStage.downloading);
    updateError = null;
    notifyListeners();
    try {
      await _updateService.downloadAndInstall(
        update,
        onProgress: (value) {
          updateProgress = value;
          notifyListeners();
        },
      );
      statusKey = 'updateInstallerOpened';
    } catch (error) {
      updateError = error is UpdateException
          ? error.message
          : error.toString().replaceFirst('Exception: ', '');
      statusKey = 'updateInstallFailed';
    } finally {
      installingUpdate = false;
      notifyListeners();
    }
  }

  Future<void> openProjectPage() async {
    try {
      await _updateService.openProjectPage();
    } catch (error) {
      detailMessage = error is UpdateException
          ? error.message
          : error.toString().replaceFirst('Exception: ', '');
      detailMessageIsError = true;
      notifyListeners();
    }
  }

  void dismissUpdate() {
    if (installingUpdate) return;
    availableUpdate = null;
    updateProgress = null;
    updateError = null;
    notifyListeners();
  }

  void _resetTaskStates() {
    for (final task in tasks) {
      task.status = TaskStatus.queued;
      task.outputLocation = null;
      task.error = null;
      task.detectedAlgorithmId = null;
    }
  }

  void _persistProcessingDefaults() {
    unawaited(
      _settings.setProcessingDefaults(
        workspaceType: workspaceType,
        mode: mode,
        algorithm: algorithm,
        scrambleAlgorithm: _scrambleAlgorithm,
        passwordProtectionEnabled: _scramblePasswordEnabled,
      ),
    );
  }

  void _applyWorkspaceProfile(WorkspaceSettingsProfile profile) {
    mode = profile.mode;
    _scrambleAlgorithm = profile.scrambleAlgorithm.isAutomatic
        ? ScrambleAlgorithm.composite
        : profile.scrambleAlgorithm;
    _scramblePasswordEnabled = profile.passwordProtectionEnabled;
    algorithm = mode == ProcessMode.restore
        ? ScrambleAlgorithm.auto
        : _scrambleAlgorithm;
    passwordEnabled =
        _scramblePasswordEnabled &&
        workspaceType == WorkspaceType.image &&
        mode == ProcessMode.scramble &&
        !algorithm.isCompatibility;
  }

  String _errorText(Object error) {
    if (error is ImageProcessingException) return error.message;
    if (error is FileServiceException) return error.message;
    if (error is TextProcessingException) return error.message;
    if (error is ArchiveCreationException) return error.message;
    return error.toString().replaceFirst('Exception: ', '');
  }

  @override
  void dispose() {
    _discardPendingArchiveExport();
    super.dispose();
  }
}

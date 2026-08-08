import 'dart:async';

import 'package:cross_file/cross_file.dart';
import 'package:flutter/foundation.dart';

import 'app_settings.dart';
import 'export_history.dart';
import 'file_service.dart';
import 'image_processor.dart';
import 'models.dart';
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
  }) : _fileService = fileService ?? FileService(),
       _imageProcessor = imageProcessor ?? ImageProcessor(),
       _textProcessor = textProcessor ?? const TextProcessor(),
       _updateService = updateService ?? UpdateService(),
       _historyStore = historyStore ?? ExportHistoryStore.memory() {
    workspaceType = _settings.lastWorkspaceType;
    mode = _settings.lastProcessMode;
    algorithm = _settings.lastAlgorithm;
    if (mode == ProcessMode.scramble && algorithm.isAutomatic) {
      algorithm = ScrambleAlgorithm.composite;
    }
    passwordEnabled =
        _settings.passwordProtectionEnabled &&
        workspaceType == WorkspaceType.image &&
        mode == ProcessMode.scramble &&
        !algorithm.isCompatibility;
  }

  final AppSettings _settings;
  final FileService _fileService;
  final ImageProcessor _imageProcessor;
  final TextProcessor _textProcessor;
  final UpdateService _updateService;
  final ExportHistoryStore _historyStore;

  late ProcessMode mode;
  late WorkspaceType workspaceType;
  late ScrambleAlgorithm algorithm;
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
  String? undoingHistoryId;

  List<ImageTask> get tasks => batch?.tasks ?? const [];
  int get completedCount =>
      tasks.where((task) => task.status == TaskStatus.completed).length;
  int get failedCount =>
      tasks.where((task) => task.status == TaskStatus.failed).length;
  bool get hasFailed => failedCount > 0;
  bool get canStart => tasks.isNotEmpty && !isProcessing;
  FileService get fileService => _fileService;
  List<ExportHistoryEntry> get exportHistory => _historyStore.entries;
  int get effectiveProcessingConcurrency =>
      _settings.effectiveProcessingConcurrency;

  void setMode(ProcessMode value) {
    if (isProcessing || mode == value) return;
    mode = value;
    algorithm = value == ProcessMode.restore
        ? ScrambleAlgorithm.auto
        : ScrambleAlgorithm.composite;
    passwordEnabled = false;
    password = '';
    manualSeed = '';
    _resetTaskStates();
    _persistProcessingDefaults();
    notifyListeners();
  }

  void setWorkspaceType(WorkspaceType value) {
    if (isProcessing || workspaceType == value) return;
    workspaceType = value;
    mode = ProcessMode.scramble;
    algorithm = ScrambleAlgorithm.composite;
    passwordEnabled = false;
    password = '';
    manualSeed = '';
    batch = null;
    progress = 0;
    statusKey = 'ready';
    detailMessage = null;
    _persistProcessingDefaults();
    notifyListeners();
  }

  void setAlgorithm(ScrambleAlgorithm value) {
    if (isProcessing || algorithm == value) return;
    algorithm = value;
    if (value.isCompatibility) passwordEnabled = false;
    _persistProcessingDefaults();
    notifyListeners();
  }

  void setPasswordEnabled(bool value) {
    if (algorithm.isCompatibility || isProcessing) return;
    passwordEnabled = value;
    if (!value) password = '';
    _persistProcessingDefaults();
    notifyListeners();
  }

  void setPassword(String value) => password = value;
  void setManualSeed(String value) => manualSeed = value;

  Future<void> pickFiles() async {
    await _runImport(() => _fileService.pickFiles(workspaceType));
  }

  Future<void> pickImages() => pickFiles();

  Future<void> pickFolder() async {
    await _runImport(
      () => _fileService.pickFolder(workspaceType: workspaceType),
    );
  }

  Future<void> importDropped(List<XFile> files) async {
    await _runImport(
      () => _fileService.importDropped(files, workspaceType: workspaceType),
    );
  }

  Future<void> _runImport(Future<ImportBatch?> Function() action) async {
    if (isProcessing) return;
    detailMessage = null;
    try {
      final imported = await action();
      if (imported == null) return;
      if (batch == null || batch!.workspaceType != imported.workspaceType) {
        batch = imported;
      } else {
        batch = ImportBatch(
          tasks: [...batch!.tasks, ...imported.tasks],
          isFolder: batch!.isFolder || imported.isFolder,
          rootName: batch!.rootName.isNotEmpty
              ? batch!.rootName
              : imported.rootName,
          workspaceType: imported.workspaceType,
        );
      }
      progress = 0;
      statusKey = batch!.tasks.isEmpty
          ? (workspaceType == WorkspaceType.text
                ? 'textFolderEmpty'
                : 'folderEmpty')
          : 'ready';
    } catch (error) {
      detailMessage = _errorText(error);
    }
    notifyListeners();
  }

  void clear() {
    if (isProcessing) return;
    batch = null;
    progress = 0;
    statusKey = 'ready';
    detailMessage = null;
    notifyListeners();
  }

  void retryFailed() {
    if (isProcessing || batch == null) return;
    final retry = tasks
        .where((task) => task.status == TaskStatus.failed)
        .map((task) => task.copyForRetry())
        .toList();
    if (retry.isEmpty) return;
    batch = ImportBatch(
      tasks: retry,
      isFolder: batch!.isFolder,
      rootName: batch!.rootName,
      workspaceType: batch!.workspaceType,
    );
    progress = 0;
    statusKey = 'ready';
    detailMessage = null;
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

  Future<void> process() async {
    if (!canStart || batch == null) {
      statusKey = 'selectFirst';
      notifyListeners();
      return;
    }
    if (workspaceType == WorkspaceType.image &&
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
    if (workspaceType == WorkspaceType.image &&
        mode == ProcessMode.restore &&
        algorithm.needsSeed &&
        parsedSeed == null) {
      statusKey = 'invalidSeed';
      notifyListeners();
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
    stopRequested = false;
    detailMessage = null;
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
          if (workspaceType == WorkspaceType.image) {
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
            workspaceType: workspaceType,
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
      await _historyStore.add(
        ExportHistoryEntry(
          id: DateTime.now().microsecondsSinceEpoch.toString(),
          createdAt: DateTime.now(),
          workspaceType: workspaceType,
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
        ),
      );
      await _historyStore.cleanup(_settings.historyRetentionDays);
    }

    isProcessing = false;
    statusKey = failedCount == 0 ? 'allCompleted' : 'partialCompleted';
    notifyListeners();
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

  Future<void> openUpdate() async {
    final update = availableUpdate;
    if (update != null) await _updateService.open(update);
  }

  void dismissUpdate() {
    availableUpdate = null;
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
        passwordProtectionEnabled: passwordEnabled,
      ),
    );
  }

  String _errorText(Object error) {
    if (error is ImageProcessingException) return error.message;
    if (error is FileServiceException) return error.message;
    if (error is TextProcessingException) return error.message;
    return error.toString().replaceFirst('Exception: ', '');
  }
}

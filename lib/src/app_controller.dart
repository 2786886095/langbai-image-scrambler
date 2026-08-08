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
    unawaited(_fileService.initializeSharedImports(_enqueueSharedImport));
  }

  final AppSettings _settings;
  final FileService _fileService;
  final ImageProcessor _imageProcessor;
  final TextProcessor _textProcessor;
  final UpdateService _updateService;
  final ExportHistoryStore _historyStore;
  final ArchiveService _archiveService;
  final PasswordVault? _passwordVault;

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
  bool detailMessageIsError = false;
  final List<SharedImportRequest> _pendingSharedImports = [];

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
  SharedImportRequest? get pendingSharedImport =>
      _pendingSharedImports.isEmpty ? null : _pendingSharedImports.first;
  bool get hasMixedBatch => batch?.isMixed ?? false;
  bool get compressionEnabled => _settings.compressionEnabled;
  CompressionArchiveFormat get compressionFormat => _settings.compressionFormat;
  CompressionGrouping get compressionGrouping => _settings.compressionGrouping;
  List<PasswordProfile> get archivePasswordProfiles =>
      _passwordVault?.profiles ?? const [];
  PasswordProfile? get selectedArchivePasswordProfile =>
      _passwordVault?.find(_settings.selectedArchivePasswordProfileId);
  bool get canUseCompression =>
      mode == ProcessMode.scramble &&
      batch?.containsText != true &&
      workspaceType == WorkspaceType.image;

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
    if (isProcessing ||
        value == WorkspaceType.mixed ||
        workspaceType == value) {
      return;
    }
    final temporaryRoots = batch?.temporaryRoots ?? const <String>[];
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
    detailMessageIsError = false;
    unawaited(_fileService.cleanupTemporaryRoots(temporaryRoots));
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

  Future<void> setCompressionEnabled(bool value) async {
    if (isProcessing) return;
    await _settings.setCompressionEnabled(value);
    notifyListeners();
  }

  Future<void> setCompressionFormat(CompressionArchiveFormat value) async {
    if (isProcessing) return;
    await _settings.setCompressionFormat(value);
    notifyListeners();
  }

  Future<void> setCompressionGrouping(CompressionGrouping value) async {
    if (isProcessing) return;
    await _settings.setCompressionGrouping(value);
    notifyListeners();
  }

  Future<void> setArchivePasswordProfile(String? id) async {
    if (isProcessing) return;
    await _settings.setSelectedArchivePasswordProfile(id);
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
    if (_settings.selectedArchivePasswordProfileId == id) {
      await _settings.setSelectedArchivePasswordProfile(null);
    }
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
    mode = selectedMode;
    algorithm = selectedMode == ProcessMode.restore
        ? ScrambleAlgorithm.auto
        : ScrambleAlgorithm.composite;
    passwordEnabled = false;
    password = '';
    manualSeed = '';
    batch = _mergeBatches(batch, imported);
    workspaceType = batch!.containsImages
        ? WorkspaceType.image
        : WorkspaceType.text;
    _resetTaskStates();
    progress = 0;
    statusKey = 'ready';
    detailMessage = imported.skippedCount > 0
        ? '已导入 ${imported.tasks.length} 个文件，跳过 ${imported.skippedCount} 个其他文件'
        : '已通过分享导入 ${imported.tasks.length} 个文件';
    detailMessageIsError = false;
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
      batch = _mergeBatches(batch, imported);
      progress = 0;
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
    final temporaryRoots = batch?.temporaryRoots ?? const <String>[];
    batch = null;
    progress = 0;
    statusKey = 'ready';
    detailMessage = null;
    detailMessageIsError = false;
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
      await _processCompressed(parsedSeed);
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
      await _historyStore.add(
        ExportHistoryEntry(
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
        ),
      );
      await _historyStore.cleanup(_settings.historyRetentionDays);
    }

    isProcessing = false;
    statusKey = failedCount == 0 ? 'allCompleted' : 'partialCompleted';
    notifyListeners();
  }

  Future<void> _processCompressed(int? parsedSeed) async {
    isProcessing = true;
    stopRequested = false;
    detailMessage = null;
    detailMessageIsError = false;
    statusKey = 'processing';
    _resetTaskStates();
    notifyListeners();

    final stagedPaths = <String, String>{};
    final prepared = <PreparedArchive>[];
    final outputs = <SaveOutputResult>[];
    ExportTarget? target;
    var historyRecorded = false;
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
            final result = await _processOne(input, task, parsedSeed);
            task.detectedAlgorithmId = result.algorithm.id;
            stagedPaths[task.id] = await _fileService.stageOutputBytes(
              Uint8List.fromList(result.bytes),
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
      target = await _fileService.chooseArchiveExportTarget(
        fileNames: prepared.map((item) => item.fileName).toList(),
        settings: _settings,
      );
      if (target == null) {
        statusKey = 'exportCancelled';
        return;
      }
      for (final archive in prepared) {
        outputs.add(
          await _fileService.savePreparedArchive(
            sourcePath: archive.path,
            fileName: archive.fileName,
            target: target,
          ),
        );
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
      statusKey = cancelled ? 'exportCancelled' : 'partialCompleted';
      if (!historyRecorded && outputs.isNotEmpty && target != null) {
        try {
          await _recordHistory(outputs, target);
        } catch (_) {}
      }
      if (!cancelled) {
        for (final task in tasks.where(
          (item) => item.status == TaskStatus.completed,
        )) {
          task.status = TaskStatus.failed;
          task.error = detailMessage;
        }
      }
    } finally {
      await _fileService.cleanupStagedFiles(stagedPaths.values);
      await _archiveService.cleanup(prepared);
      isProcessing = false;
      notifyListeners();
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
    await _historyStore.add(
      ExportHistoryEntry(
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
      ),
    );
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
    if (error is ArchiveCreationException) return error.message;
    return error.toString().replaceFirst('Exception: ', '');
  }
}

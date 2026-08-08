import 'package:cross_file/cross_file.dart';
import 'package:flutter/foundation.dart';

import 'app_settings.dart';
import 'file_service.dart';
import 'image_processor.dart';
import 'models.dart';
import 'update_service.dart';

class AppController extends ChangeNotifier {
  AppController(
    this._settings, {
    FileService? fileService,
    ImageProcessor? imageProcessor,
    UpdateService? updateService,
  }) : _fileService = fileService ?? FileService(),
       _imageProcessor = imageProcessor ?? ImageProcessor(),
       _updateService = updateService ?? UpdateService();

  final AppSettings _settings;
  final FileService _fileService;
  final ImageProcessor _imageProcessor;
  final UpdateService _updateService;

  ProcessMode mode = ProcessMode.scramble;
  ScrambleAlgorithm algorithm = ScrambleAlgorithm.composite;
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

  List<ImageTask> get tasks => batch?.tasks ?? const [];
  int get completedCount =>
      tasks.where((task) => task.status == TaskStatus.completed).length;
  int get failedCount =>
      tasks.where((task) => task.status == TaskStatus.failed).length;
  bool get hasFailed => failedCount > 0;
  bool get canStart => tasks.isNotEmpty && !isProcessing;
  FileService get fileService => _fileService;

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
    notifyListeners();
  }

  void setAlgorithm(ScrambleAlgorithm value) {
    if (isProcessing || algorithm == value) return;
    algorithm = value;
    if (value.isCompatibility) passwordEnabled = false;
    notifyListeners();
  }

  void setPasswordEnabled(bool value) {
    if (algorithm.isCompatibility || isProcessing) return;
    passwordEnabled = value;
    if (!value) password = '';
    notifyListeners();
  }

  void setPassword(String value) => password = value;
  void setManualSeed(String value) => manualSeed = value;

  Future<void> pickImages() async {
    await _runImport(_fileService.pickImages);
  }

  Future<void> pickFolder() async {
    await _runImport(_fileService.pickFolder);
  }

  Future<void> importDropped(List<XFile> files) async {
    await _runImport(() => _fileService.importDropped(files));
  }

  Future<void> _runImport(Future<ImportBatch?> Function() action) async {
    if (isProcessing) return;
    detailMessage = null;
    try {
      final imported = await action();
      if (imported == null) return;
      batch = imported;
      progress = 0;
      statusKey = imported.tasks.isEmpty ? 'folderEmpty' : 'ready';
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

  Future<void> process() async {
    if (!canStart || batch == null) {
      statusKey = 'selectFirst';
      notifyListeners();
      return;
    }
    if (mode == ProcessMode.scramble &&
        passwordEnabled &&
        password.trim().isEmpty) {
      statusKey = 'invalidPassword';
      notifyListeners();
      return;
    }
    final parsedSeed = manualSeed.trim().isEmpty
        ? null
        : int.tryParse(manualSeed.trim());
    if (mode == ProcessMode.restore &&
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

    for (var index = 0; index < tasks.length; index++) {
      if (stopRequested) break;
      final task = tasks[index];
      task.status = TaskStatus.processing;
      notifyListeners();
      try {
        final input = await _fileService.readTask(task);
        final result = await _processOne(input, task, parsedSeed);
        task.detectedAlgorithmId = result.algorithm.id;
        task.outputLocation = await _fileService.saveOutput(
          bytes: Uint8List.fromList(result.bytes),
          task: task,
          mode: mode,
          target: target,
        );
        task.status = TaskStatus.completed;
      } catch (error) {
        task.status = TaskStatus.failed;
        task.error = _errorText(error);
      }
      progress = (index + 1) / tasks.length;
      notifyListeners();
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

  String _errorText(Object error) {
    if (error is ImageProcessingException) return error.message;
    if (error is FileServiceException) return error.message;
    return error.toString().replaceFirst('Exception: ', '');
  }
}

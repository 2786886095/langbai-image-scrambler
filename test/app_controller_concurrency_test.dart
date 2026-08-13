import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:langbai_image_scrambler/src/app_controller.dart';
import 'package:langbai_image_scrambler/src/app_settings.dart';
import 'package:langbai_image_scrambler/src/archive_service.dart';
import 'package:langbai_image_scrambler/src/export_history.dart';
import 'package:langbai_image_scrambler/src/file_service.dart';
import 'package:langbai_image_scrambler/src/image_processor.dart';
import 'package:langbai_image_scrambler/src/models.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('four-worker setting processes image batches concurrently', () async {
    SharedPreferences.setMockInitialValues({
      'check_updates': false,
      'processing_concurrency': 4,
    });
    final settings = await AppSettings.load();
    final processor = _ConcurrentImageProcessor();
    final history = ExportHistoryStore.memory();
    final controller = AppController(
      settings,
      fileService: _MemoryFileService(),
      imageProcessor: processor,
      historyStore: history,
    );
    controller.batch = ImportBatch(
      tasks: List.generate(
        8,
        (index) => ImageTask(
          id: '$index',
          originalName: '$index.png',
          relativeDirectory: '',
          sourceRootName: '',
        ),
      ),
      isFolder: false,
      rootName: '',
    );

    await controller.process();

    expect(processor.maxActive, 4);
    expect(controller.completedCount, 8);
    expect(controller.progress, 1);
    expect(history.entries, hasLength(1));
    expect(history.entries.single.artifacts, hasLength(8));
  });

  test('automatic concurrency stays between one and four', () async {
    SharedPreferences.setMockInitialValues({'check_updates': false});
    final settings = await AppSettings.load();
    expect(settings.processingConcurrency, 0);
    expect(settings.effectiveProcessingConcurrency, inInclusiveRange(1, 4));
  });

  test(
    'restore completion and history open the recorded output location',
    () async {
      SharedPreferences.setMockInitialValues({'check_updates': false});
      final settings = await AppSettings.load();
      final files = _MemoryFileService();
      final history = ExportHistoryStore.memory();
      final controller = AppController(
        settings,
        fileService: files,
        imageProcessor: _ConcurrentImageProcessor(),
        historyStore: history,
      );
      controller.setMode(ProcessMode.restore);
      controller.batch = ImportBatch(
        tasks: [
          ImageTask(
            id: '1',
            originalName: '混淆图.png',
            relativeDirectory: '',
            sourceRootName: '图包',
          ),
        ],
        isFolder: true,
        rootName: '图包',
      );

      await controller.process();

      expect(controller.canOpenLastRestoreOutput, isTrue);
      expect(history.entries.single.locationToReveal, 'memory');
      expect(history.entries.single.locationIsDirectory, isTrue);
      expect(await controller.openLastRestoreOutput(), isTrue);
      expect(files.openedLocations.single, ('memory', true));
      expect(await controller.openTaskOutput(controller.tasks.single), isTrue);
      expect(files.openedLocations.last, ('memory/1.png', false));
    },
  );

  test(
    'compression mode exports archives only and cleans staged PNG files',
    () async {
      SharedPreferences.setMockInitialValues({
        'check_updates': false,
        'workspace_image_compression_enabled': true,
      });
      final settings = await AppSettings.load();
      final files = _ArchiveOnlyFileService();
      final archives = _MemoryArchiveService();
      final history = ExportHistoryStore.memory();
      final controller = AppController(
        settings,
        fileService: files,
        imageProcessor: _ConcurrentImageProcessor(),
        archiveService: archives,
        historyStore: history,
      );
      controller.batch = ImportBatch(
        tasks: [
          ImageTask(
            id: '1',
            originalName: '原图.jpg',
            relativeDirectory: '',
            sourceRootName: '',
          ),
        ],
        isFolder: false,
        rootName: '',
      );

      await controller.process();

      expect(files.rawOutputCalls, 0);
      expect(files.savedArchives, ['原图.zip']);
      expect(files.cleanedStagePaths, ['memory-stage-1.png']);
      expect(archives.cleaned, isTrue);
      expect(history.entries.single.artifacts.single.displayName, '原图.zip');
    },
  );

  test(
    'TXT compression Base64-encodes and exports only the original-name archive',
    () async {
      SharedPreferences.setMockInitialValues({
        'check_updates': false,
        'workspace_text_compression_enabled': true,
      });
      final settings = await AppSettings.load();
      final files = _ArchiveOnlyFileService();
      final archives = _MemoryArchiveService();
      final history = ExportHistoryStore.memory();
      final controller = AppController(
        settings,
        fileService: files,
        archiveService: archives,
        historyStore: history,
      );
      controller.setWorkspaceType(WorkspaceType.text);
      controller.batch = ImportBatch(
        tasks: [
          ImageTask(
            id: '1',
            originalName: '正文.txt',
            relativeDirectory: '',
            sourceRootName: '',
            workspaceType: WorkspaceType.text,
          ),
        ],
        isFolder: false,
        rootName: '',
        workspaceType: WorkspaceType.text,
      );

      await controller.process();

      expect(controller.canUseCompression, isTrue);
      expect(files.rawOutputCalls, 0);
      expect(files.stagedSuffixes, ['.txt']);
      expect(files.savedArchives, ['正文.zip']);
      expect(files.cleanedStagePaths, ['memory-stage-65.txt']);
      expect(history.entries.single.artifacts.single.displayName, '正文.zip');
    },
  );

  test(
    'compression export target is selected before image processing',
    () async {
      SharedPreferences.setMockInitialValues({
        'check_updates': false,
        'compression_enabled': true,
      });
      final settings = await AppSettings.load();
      final processor = _ConcurrentImageProcessor();
      final files = _CancelledArchiveTargetFileService();
      final archives = _MemoryArchiveService();
      final controller = AppController(
        settings,
        fileService: files,
        imageProcessor: processor,
        archiveService: archives,
      );
      controller.batch = ImportBatch(
        tasks: [
          ImageTask(
            id: '1',
            originalName: '原图.jpg',
            relativeDirectory: '',
            sourceRootName: '',
          ),
        ],
        isFolder: false,
        rootName: '',
      );

      await controller.process();

      expect(files.chooseCalls, 1);
      expect(processor.calls, 0);
      expect(archives.createCalls, 0);
      expect(controller.statusKey, 'exportCancelled');
    },
  );

  test(
    'cancelled archive save is cached and retry does not regenerate',
    () async {
      SharedPreferences.setMockInitialValues({
        'check_updates': false,
        'compression_enabled': true,
      });
      final settings = await AppSettings.load();
      final processor = _ConcurrentImageProcessor();
      final files = _RetryArchiveFileService();
      final archives = _MemoryArchiveService();
      final history = ExportHistoryStore.memory();
      final controller = AppController(
        settings,
        fileService: files,
        imageProcessor: processor,
        archiveService: archives,
        historyStore: history,
      );
      controller.batch = ImportBatch(
        tasks: [
          ImageTask(
            id: '1',
            originalName: '原图.jpg',
            relativeDirectory: '',
            sourceRootName: '',
          ),
        ],
        isFolder: false,
        rootName: '',
      );

      await controller.process();

      expect(controller.hasPendingArchiveExport, isTrue);
      expect(controller.statusKey, 'exportPending');
      expect(processor.calls, 1);
      expect(archives.createCalls, 1);
      expect(history.entries, isEmpty);

      await controller.process();

      expect(controller.hasPendingArchiveExport, isFalse);
      expect(controller.statusKey, 'allCompleted');
      expect(processor.calls, 1);
      expect(archives.createCalls, 1);
      expect(files.saveAttempts, 2);
      expect(history.entries, hasLength(1));
      expect(archives.cleanedFileNames, contains('原图.zip'));
    },
  );
}

class _ConcurrentImageProcessor extends ImageProcessor {
  int active = 0;
  int maxActive = 0;
  int calls = 0;

  @override
  Future<ProcessedImage> scramble({
    required Uint8List inputBytes,
    required String sourceName,
    required ScrambleAlgorithm algorithm,
    String? password,
  }) async {
    calls++;
    active++;
    if (active > maxActive) maxActive = active;
    await Future<void>.delayed(const Duration(milliseconds: 35));
    active--;
    return ProcessedImage(
      bytes: inputBytes,
      algorithm: algorithm,
      verified: true,
    );
  }

  @override
  Future<ProcessedImage> restore({
    required Uint8List inputBytes,
    required ScrambleAlgorithm requestedAlgorithm,
    String? password,
    int? manualSeed,
  }) async => ProcessedImage(
    bytes: inputBytes,
    algorithm: ScrambleAlgorithm.composite,
    verified: true,
  );
}

class _MemoryFileService extends FileService {
  final List<(String, bool)> openedLocations = [];

  @override
  Future<Uint8List> readTask(ImageTask task) async =>
      Uint8List.fromList([int.parse(task.id)]);

  @override
  Future<ExportTarget?> chooseExportTarget({
    required ImportBatch batch,
    required ProcessMode mode,
    required AppSettings settings,
  }) async => const ExportTarget(
    path: 'memory',
    rootFolderName: 'batch',
    singleFile: false,
    displayLabel: 'memory/batch',
  );

  @override
  Future<SaveOutputResult> saveOutput({
    required Uint8List bytes,
    required ImageTask task,
    required ProcessMode mode,
    required ExportTarget target,
    WorkspaceType workspaceType = WorkspaceType.image,
  }) async => SaveOutputResult(
    location: 'memory/${task.id}.png',
    displayName: '${task.id}.png',
    sha256Digest: task.id.padLeft(64, '0'),
    sizeBytes: bytes.length,
  );

  @override
  Future<void> openOutputLocation(
    String location, {
    required bool isDirectory,
    String? fallbackLocation,
  }) async {
    openedLocations.add((location, isDirectory));
  }
}

class _ArchiveOnlyFileService extends FileService {
  int rawOutputCalls = 0;
  final List<String> savedArchives = [];
  final List<String> cleanedStagePaths = [];
  final List<String> stagedSuffixes = [];

  @override
  Future<Uint8List> readTask(ImageTask task) async => Uint8List.fromList([1]);

  @override
  Future<String> stageOutputBytes(
    Uint8List bytes, {
    String suffix = '.png',
  }) async {
    stagedSuffixes.add(suffix);
    return 'memory-stage-${bytes.first}$suffix';
  }

  @override
  Future<void> cleanupStagedFiles(Iterable<String> paths) async {
    cleanedStagePaths.addAll(paths);
  }

  @override
  Future<ExportTarget?> chooseArchiveExportTarget({
    required List<String> fileNames,
    required AppSettings settings,
  }) async => const ExportTarget(
    path: 'memory',
    rootFolderName: '',
    singleFile: true,
    displayLabel: 'memory/archive.zip',
  );

  @override
  Future<SaveOutputResult> savePreparedArchive({
    required String sourcePath,
    required String fileName,
    required ExportTarget target,
  }) async {
    savedArchives.add(fileName);
    return SaveOutputResult(
      location: 'memory/$fileName',
      displayName: fileName,
      sha256Digest: List.filled(64, '0').join(),
      sizeBytes: 3,
    );
  }

  @override
  Future<SaveOutputResult> saveOutput({
    required Uint8List bytes,
    required ImageTask task,
    required ProcessMode mode,
    required ExportTarget target,
    WorkspaceType workspaceType = WorkspaceType.image,
  }) async {
    rawOutputCalls++;
    throw StateError('raw output must not be saved');
  }
}

class _CancelledArchiveTargetFileService extends _ArchiveOnlyFileService {
  int chooseCalls = 0;

  @override
  Future<ExportTarget?> chooseArchiveExportTarget({
    required List<String> fileNames,
    required AppSettings settings,
  }) async {
    chooseCalls++;
    return null;
  }
}

class _RetryArchiveFileService extends _ArchiveOnlyFileService {
  int saveAttempts = 0;

  @override
  Future<SaveOutputResult> savePreparedArchive({
    required String sourcePath,
    required String fileName,
    required ExportTarget target,
  }) async {
    saveAttempts++;
    if (saveAttempts == 1) throw const ExportCancelledException();
    return super.savePreparedArchive(
      sourcePath: sourcePath,
      fileName: fileName,
      target: target,
    );
  }
}

class _MemoryArchiveService extends ArchiveService {
  bool cleaned = false;
  int createCalls = 0;
  final List<String> cleanedFileNames = [];

  @override
  Future<List<PreparedArchive>> create({
    required List<ArchiveGroupPlan> groups,
    required CompressionArchiveFormat format,
    String? password,
  }) async {
    createCalls++;
    return [
      PreparedArchive(
        path: 'memory/archive.zip',
        fileName: '${groups.single.baseName}.zip',
      ),
    ];
  }

  @override
  Future<void> cleanup(List<PreparedArchive> archives) async {
    if (archives.isNotEmpty) cleaned = true;
    cleanedFileNames.addAll(archives.map((item) => item.fileName));
  }
}

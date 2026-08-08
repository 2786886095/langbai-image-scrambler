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
        'compression_enabled': true,
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
}

class _ConcurrentImageProcessor extends ImageProcessor {
  int active = 0;
  int maxActive = 0;

  @override
  Future<ProcessedImage> scramble({
    required Uint8List inputBytes,
    required String sourceName,
    required ScrambleAlgorithm algorithm,
    String? password,
  }) async {
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
  }) async {
    openedLocations.add((location, isDirectory));
  }
}

class _ArchiveOnlyFileService extends FileService {
  int rawOutputCalls = 0;
  final List<String> savedArchives = [];
  final List<String> cleanedStagePaths = [];

  @override
  Future<Uint8List> readTask(ImageTask task) async => Uint8List.fromList([1]);

  @override
  Future<String> stageOutputBytes(
    Uint8List bytes, {
    String suffix = '.png',
  }) async => 'memory-stage-${bytes.first}.png';

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

class _MemoryArchiveService extends ArchiveService {
  bool cleaned = false;

  @override
  Future<List<PreparedArchive>> create({
    required List<ArchiveGroupPlan> groups,
    required CompressionArchiveFormat format,
    String? password,
  }) async => [
    PreparedArchive(
      path: 'memory/archive.zip',
      fileName: '${groups.single.baseName}.zip',
    ),
  ];

  @override
  Future<void> cleanup(List<PreparedArchive> archives) async {
    cleaned = true;
  }
}

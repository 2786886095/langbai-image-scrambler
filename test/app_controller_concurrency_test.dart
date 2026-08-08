import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:langbai_image_scrambler/src/app_controller.dart';
import 'package:langbai_image_scrambler/src/app_settings.dart';
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
}

class _MemoryFileService extends FileService {
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
}

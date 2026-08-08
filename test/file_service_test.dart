import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:cross_file/cross_file.dart';
import 'package:langbai_image_scrambler/src/app_settings.dart';
import 'package:langbai_image_scrambler/src/export_history.dart';
import 'package:langbai_image_scrambler/src/file_service.dart';
import 'package:langbai_image_scrambler/src/models.dart';
import 'package:path/path.dart' as path;
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('folder import and export preserve root and nested structure', () async {
    final temporary = await Directory.systemTemp.createTemp(
      'langbai-file-test-',
    );
    addTearDown(() async {
      if (await temporary.exists()) await temporary.delete(recursive: true);
    });
    final source = Directory(path.join(temporary.path, '原始画集'));
    final nested = Directory(path.join(source.path, '第一章', '场景A'));
    await nested.create(recursive: true);
    await File(path.join(source.path, '封面.JPG')).writeAsBytes([1, 2, 3]);
    await File(path.join(nested.path, '画面.PNG')).writeAsBytes([4, 5, 6]);
    await File(path.join(nested.path, '说明.txt')).writeAsString('ignored');

    final service = FileService();
    final batch = await service.importFolderPath(source.path);
    expect(batch.isFolder, isTrue);
    expect(batch.rootName, '原始画集');
    expect(batch.tasks, hasLength(2));
    final nestedTask = batch.tasks.singleWhere(
      (task) => task.originalName == '画面.PNG',
    );
    expect(nestedTask.relativeDirectory, path.join('第一章', '场景A'));

    final exportBase = Directory(path.join(temporary.path, 'export'));
    final saved = await service.saveOutput(
      bytes: Uint8List.fromList([137, 80, 78, 71]),
      task: nestedTask,
      mode: ProcessMode.scramble,
      target: ExportTarget(
        path: exportBase.path,
        rootFolderName: batch.rootName,
        singleFile: false,
      ),
    );
    expect(
      saved.location,
      path.join(exportBase.path, '原始画集', '第一章', '场景A', '画面.png'),
    );
    expect(await File(saved.location).readAsBytes(), [137, 80, 78, 71]);
  });

  test('single restore output removes a trailing scramble suffix', () {
    final task = ImageTask(
      id: '1',
      originalName: '示例_混淆.png',
      relativeDirectory: '',
      sourceRootName: '',
      inputPath: 'unused',
    );
    expect(FileService().outputFileName(task, ProcessMode.restore), '示例.png');
  });

  test('image output keeps the original base name and always uses PNG', () {
    final task = ImageTask(
      id: '1',
      originalName: '封面.JPG',
      relativeDirectory: '',
      sourceRootName: '',
      inputPath: 'unused',
    );
    expect(FileService().outputFileName(task, ProcessMode.scramble), '封面.png');
  });

  test('same-name files use full-width incrementing suffixes', () async {
    final temporary = await Directory.systemTemp.createTemp(
      'langbai-collision-test-',
    );
    addTearDown(() async {
      if (await temporary.exists()) await temporary.delete(recursive: true);
    });
    final original = path.join(temporary.path, '封面.png');
    await File(original).writeAsBytes([0]);
    final task = ImageTask(
      id: '1',
      originalName: '封面.png',
      relativeDirectory: '',
      sourceRootName: '',
      inputPath: 'unused',
    );
    final service = FileService();
    final first = await service.saveOutput(
      bytes: Uint8List.fromList([1]),
      task: task,
      mode: ProcessMode.scramble,
      target: ExportTarget(
        path: original,
        rootFolderName: '',
        singleFile: true,
      ),
    );
    final second = await service.saveOutput(
      bytes: Uint8List.fromList([2]),
      task: task,
      mode: ProcessMode.scramble,
      target: ExportTarget(
        path: original,
        rootFolderName: '',
        singleFile: true,
      ),
    );
    expect(first.location, path.join(temporary.path, '封面（1）.png'));
    expect(second.location, path.join(temporary.path, '封面（2）.png'));
  });

  test('concurrent same-name saves never overwrite each other', () async {
    final temporary = await Directory.systemTemp.createTemp(
      'langbai-concurrent-save-test-',
    );
    addTearDown(() async {
      if (await temporary.exists()) await temporary.delete(recursive: true);
    });
    final targetPath = path.join(temporary.path, '同名.png');
    final service = FileService();
    final results = await Future.wait(
      List.generate(
        8,
        (index) => service.saveOutput(
          bytes: Uint8List.fromList([index]),
          task: ImageTask(
            id: '$index',
            originalName: '同名.png',
            relativeDirectory: '',
            sourceRootName: '',
          ),
          mode: ProcessMode.scramble,
          target: ExportTarget(
            path: targetPath,
            rootFolderName: '',
            singleFile: true,
          ),
        ),
      ),
    );
    expect(results.map((item) => item.location).toSet(), hasLength(8));
    expect(results.every((item) => File(item.location).existsSync()), isTrue);
  });

  test(
    'multiple dropped folders are imported as separate collapsed roots',
    () async {
      final temporary = await Directory.systemTemp.createTemp(
        'langbai-multi-folder-test-',
      );
      addTearDown(() async {
        if (await temporary.exists()) await temporary.delete(recursive: true);
      });
      final first = Directory(path.join(temporary.path, '画集A'));
      final second = Directory(path.join(temporary.path, '画集B'));
      await first.create();
      await second.create();
      await File(path.join(first.path, '1.png')).writeAsBytes([1]);
      await File(path.join(second.path, '2.jpg')).writeAsBytes([2]);

      final batch = await FileService().importDropped([
        XFile(first.path),
        XFile(second.path),
      ]);
      expect(batch, isNotNull);
      expect(batch!.isFolder, isTrue);
      expect(batch.tasks, hasLength(2));
      expect(batch.tasks.map((task) => task.sourceRootName).toSet(), {
        '画集A',
        '画集B',
      });
      expect(
        batch.tasks.map((task) => task.sourceRootId).toSet(),
        hasLength(2),
      );
    },
  );

  test('same-name folder roots increment independently', () async {
    SharedPreferences.setMockInitialValues({
      'ask_export_every_time': false,
      'check_updates': false,
    });
    final settings = await AppSettings.load();
    final temporary = await Directory.systemTemp.createTemp(
      'langbai-folder-collision-test-',
    );
    addTearDown(() async {
      if (await temporary.exists()) await temporary.delete(recursive: true);
    });
    await settings.setDefaultExport(
      path: temporary.path,
      label: temporary.path,
    );
    await Directory(path.join(temporary.path, '画集')).create();
    final tasks = [
      ImageTask(
        id: 'a',
        originalName: '1.png',
        relativeDirectory: '',
        sourceRootName: '画集',
        sourceRootId: 'root-a',
      ),
      ImageTask(
        id: 'b',
        originalName: '2.png',
        relativeDirectory: '',
        sourceRootName: '画集',
        sourceRootId: 'root-b',
      ),
    ];
    final target = await FileService().chooseExportTarget(
      batch: ImportBatch(tasks: tasks, isFolder: true, rootName: '画集'),
      mode: ProcessMode.scramble,
      settings: settings,
    );
    expect(target, isNotNull);
    expect(path.basename(target!.taskRootPaths['a']!), '画集（1）');
    expect(path.basename(target.taskRootPaths['b']!), '画集（2）');
  });

  test('undo deletes unchanged exports and skips modified files', () async {
    final temporary = await Directory.systemTemp.createTemp(
      'langbai-undo-test-',
    );
    addTearDown(() async {
      if (await temporary.exists()) await temporary.delete(recursive: true);
    });
    final service = FileService();
    Future<SaveOutputResult> save(String name, List<int> bytes) =>
        service.saveOutput(
          bytes: Uint8List.fromList(bytes),
          task: ImageTask(
            id: name,
            originalName: name,
            relativeDirectory: '',
            sourceRootName: '',
          ),
          mode: ProcessMode.scramble,
          target: ExportTarget(
            path: path.join(temporary.path, name),
            rootFolderName: '',
            singleFile: true,
          ),
        );
    final unchanged = await save('未修改.png', [1, 2, 3]);
    final changed = await save('已修改.png', [4, 5, 6]);
    await File(changed.location).writeAsBytes([9, 9, 9]);
    final result = await service.undoExport(
      ExportHistoryEntry(
        id: 'history',
        createdAt: DateTime.now(),
        workspaceType: WorkspaceType.image,
        mode: ProcessMode.scramble,
        targetLabel: temporary.path,
        artifacts: [
          for (final item in [unchanged, changed])
            ExportArtifact(
              location: item.location,
              displayName: item.displayName,
              sha256: item.sha256Digest,
              sizeBytes: item.sizeBytes,
            ),
        ],
        createdDirectories: const [],
      ),
    );
    expect(result.deleted, 1);
    expect(result.modified, 1);
    expect(await File(unchanged.location).exists(), isFalse);
    expect(await File(changed.location).exists(), isTrue);
  });

  test(
    'TXT folder keeps its original root name and nested structure',
    () async {
      final temporary = await Directory.systemTemp.createTemp(
        'langbai-text-file-test-',
      );
      addTearDown(() async {
        if (await temporary.exists()) await temporary.delete(recursive: true);
      });
      final source = Directory(path.join(temporary.path, '小说合集'));
      final nested = Directory(path.join(source.path, '长篇'));
      await nested.create(recursive: true);
      await File(path.join(source.path, '短篇.txt')).writeAsString('短篇');
      await File(path.join(nested.path, '第一部.TXT')).writeAsString('第一部');
      await File(path.join(nested.path, '封面.png')).writeAsBytes([1, 2, 3]);

      final service = FileService();
      final batch = await service.importFolderPath(
        source.path,
        workspaceType: WorkspaceType.text,
      );
      expect(batch.workspaceType, WorkspaceType.text);
      expect(batch.rootName, '小说合集');
      expect(batch.tasks, hasLength(2));
      final nestedTask = batch.tasks.singleWhere(
        (task) => task.originalName == '第一部.TXT',
      );
      expect(nestedTask.relativeDirectory, '长篇');

      final exportBase = Directory(path.join(temporary.path, 'export'));
      final saved = await service.saveOutput(
        bytes: Uint8List.fromList(asciiBytes('encoded')),
        task: nestedTask,
        mode: ProcessMode.scramble,
        target: ExportTarget(
          path: exportBase.path,
          rootFolderName: batch.rootName,
          singleFile: false,
        ),
        workspaceType: WorkspaceType.text,
      );
      expect(
        saved.location,
        path.join(exportBase.path, '小说合集', '长篇', '第一部_混淆.txt'),
      );
      expect(await File(saved.location).readAsString(), 'encoded');
    },
  );
}

List<int> asciiBytes(String value) => value.codeUnits;

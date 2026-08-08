import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:langbai_image_scrambler/src/file_service.dart';
import 'package:langbai_image_scrambler/src/models.dart';
import 'package:path/path.dart' as path;

void main() {
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
    final location = await service.saveOutput(
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
      location,
      path.join(exportBase.path, '原始画集', '第一章', '场景A', '画面_混淆.png'),
    );
    expect(await File(location).readAsBytes(), [137, 80, 78, 71]);
  });

  test('single restore output removes a trailing scramble suffix', () {
    final task = ImageTask(
      id: '1',
      originalName: '示例_混淆.png',
      relativeDirectory: '',
      sourceRootName: '',
      inputPath: 'unused',
    );
    expect(
      FileService().outputFileName(task, ProcessMode.restore),
      '示例_还原.png',
    );
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
      final location = await service.saveOutput(
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
      expect(location, path.join(exportBase.path, '小说合集', '长篇', '第一部_混淆.txt'));
      expect(await File(location).readAsString(), 'encoded');
    },
  );
}

List<int> asciiBytes(String value) => value.codeUnits;

import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:langbai_image_scrambler/src/archive_service.dart';
import 'package:langbai_image_scrambler/src/models.dart';
import 'package:path/path.dart' as path;

void main() {
  test('per-folder plan preserves tree and ZIP AES needs password', () async {
    final root = await Directory.systemTemp.createTemp('langbai-archive-test-');
    addTearDown(() async {
      if (await root.exists()) await root.delete(recursive: true);
    });
    final first = File(path.join(root.path, 'first.png'))
      ..writeAsBytesSync([1, 2, 3]);
    final second = File(path.join(root.path, 'second.png'))
      ..writeAsBytesSync([4, 5, 6]);
    final tasks = [
      ImageTask(
        id: '1',
        originalName: '图一.jpg',
        relativeDirectory: '章节一',
        sourceRootName: '小说插图',
        sourceRootId: 'root-a',
      ),
      ImageTask(
        id: '2',
        originalName: '图二.webp',
        relativeDirectory: '章节二',
        sourceRootName: '小说插图',
        sourceRootId: 'root-a',
      ),
    ];
    final service = ArchiveService(
      temporaryRoot: Directory(path.join(root.path, 'out')),
    );
    final groups = service.plan(
      tasks: tasks,
      stagedPaths: {'1': first.path, '2': second.path},
      grouping: CompressionGrouping.perFolder,
    );
    expect(groups, hasLength(1));
    expect(groups.single.baseName, '小说插图');
    expect(groups.single.entries.map((item) => item.archivePath), [
      '章节一/图一.png',
      '章节二/图二.png',
    ]);

    final output = (await service.create(
      groups: groups,
      format: CompressionArchiveFormat.zip,
      password: 'secret',
    )).single;
    final zipBytes = File(output.path).readAsBytesSync();
    expect(_readUint16(zipBytes, 6) & 0x0800, 0x0800);
    final centralOffset = _indexOfSignature(zipBytes, const [
      0x50,
      0x4b,
      0x01,
      0x02,
    ]);
    expect(centralOffset, greaterThan(0));
    expect(_readUint16(zipBytes, centralOffset + 8) & 0x0800, 0x0800);
    expect(() {
      final archive = ZipDecoder().decodeBytes(zipBytes, password: 'wrong');
      archive.first.readBytes();
    }, throwsA(anything));
    final archive = ZipDecoder().decodeBytes(zipBytes, password: 'secret');
    expect(archive.map((item) => item.name), ['章节一/图一.png', '章节二/图二.png']);
    expect(archive.first.readBytes(), first.readAsBytesSync());
  });

  test('Windows bundled 7zr creates encrypted header archive', () async {
    if (!Platform.isWindows) return;
    final root = await Directory.systemTemp.createTemp('langbai-7z-test-');
    addTearDown(() async {
      if (await root.exists()) await root.delete(recursive: true);
    });
    final input = File(path.join(root.path, 'image.png'))
      ..writeAsBytesSync([9, 8, 7]);
    final service = ArchiveService(
      temporaryRoot: Directory(path.join(root.path, 'out')),
      windows7zrPath: path.join(
        Directory.current.path,
        'assets',
        'bin',
        'windows',
        '7zr.exe',
      ),
    );
    final output = (await service.create(
      groups: [
        ArchiveGroupPlan(
          baseName: '一组',
          entries: [
            ArchiveEntryInput(sourcePath: input.path, archivePath: '目录/图片.png'),
          ],
        ),
      ],
      format: CompressionArchiveFormat.sevenZip,
      password: 'secret',
    )).single;
    final listing = await Process.run(
      path.join(Directory.current.path, 'assets', 'bin', 'windows', '7zr.exe'),
      ['l', output.path, '-psecret'],
    );
    expect(listing.exitCode, 0, reason: '${listing.stdout}\n${listing.stderr}');
    expect(listing.stdout.toString(), contains('目录\\图片.png'));
    final wrong = await Process.run(
      path.join(Directory.current.path, 'assets', 'bin', 'windows', '7zr.exe'),
      ['l', output.path, '-pwrong'],
    );
    expect(wrong.exitCode, isNot(0));
  });
}

int _readUint16(List<int> bytes, int offset) =>
    bytes[offset] | (bytes[offset + 1] << 8);

int _indexOfSignature(List<int> bytes, List<int> signature) {
  for (var offset = 0; offset <= bytes.length - signature.length; offset++) {
    var matches = true;
    for (var index = 0; index < signature.length; index++) {
      if (bytes[offset + index] != signature[index]) {
        matches = false;
        break;
      }
    }
    if (matches) return offset;
  }
  return -1;
}

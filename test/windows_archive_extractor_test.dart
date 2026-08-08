import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:langbai_image_scrambler/src/windows_archive_extractor.dart';
import 'package:path/path.dart' as path;

void main() {
  test('Windows extractor restores legacy GBK ZIP names', () async {
    if (!Platform.isWindows) return;
    final root = await Directory.systemTemp.createTemp(
      'langbai-windows-archive-test-',
    );
    addTearDown(() async {
      if (await root.exists()) await root.delete(recursive: true);
    });
    final archivePath = path.join(root.path, 'legacy-gbk.zip');
    const script = r'''
Add-Type -AssemblyName System.IO.Compression
$stream = [IO.File]::Open($env:LANGBAI_ZIP_PATH, [IO.FileMode]::Create)
$archive = New-Object IO.Compression.ZipArchive(
  $stream,
  [IO.Compression.ZipArchiveMode]::Create,
  $false,
  [Text.Encoding]::GetEncoding(936)
)
$entry = $archive.CreateEntry('本章/小说（1）.txt')
$output = $entry.Open()
$bytes = [Text.Encoding]::UTF8.GetBytes('正文')
$output.Write($bytes, 0, $bytes.Length)
$output.Dispose()
$archive.Dispose()
$stream.Dispose()
''';
    final created = await Process.run(
      'powershell.exe',
      ['-NoProfile', '-NonInteractive', '-Command', script],
      environment: {'LANGBAI_ZIP_PATH': archivePath},
      runInShell: false,
    );
    expect(created.exitCode, 0, reason: '${created.stderr}');

    final extractor = WindowsArchiveExtractor(
      executablePath: path.join(
        Directory.current.path,
        'assets',
        'bin',
        'windows',
        '7z.exe',
      ),
    );
    final result = await extractor.extract(
      sourcePath: archivePath,
      displayName: '旧版中文.zip',
    );
    addTearDown(() async {
      final temporary = Directory(result['temporaryRoot'] as String);
      if (await temporary.exists()) await temporary.delete(recursive: true);
    });
    final items = (result['items'] as List<dynamic>)
        .cast<Map<String, dynamic>>();

    expect(items, hasLength(1));
    expect(items.single['name'], '小说（1）.txt');
    expect(items.single['relativeDirectory'], '本章');
    expect(items.single['relativePath'], '本章/小说（1）.txt');
    expect(await File(items.single['path'] as String).readAsString(), '正文');
  });

  test(
    'Windows extractor reads password protected 7Z and RAR fixtures',
    () async {
      if (!Platform.isWindows) return;
      final executable = path.join(
        Directory.current.path,
        'assets',
        'bin',
        'windows',
        '7z.exe',
      );
      final configured = WindowsArchiveExtractor(executablePath: executable);

      final sevenZip = await configured.extract(
        sourcePath: path.join(
          Directory.current.path,
          'android',
          'app',
          'src',
          'test',
          'resources',
          'archives',
          'encrypted-mixed.7z',
        ),
        displayName: '混合内容.7z',
        password: 'langbai-test',
      );
      addTearDown(() async {
        final temporary = Directory(sevenZip['temporaryRoot'] as String);
        if (await temporary.exists()) await temporary.delete(recursive: true);
      });
      final sevenZipItems = (sevenZip['items'] as List<dynamic>)
          .cast<Map<String, dynamic>>();
      expect(sevenZipItems.map((item) => item['relativePath']).toSet(), {
        'chapter-1/image.png',
        'chapter-1/novel.txt',
      });

      final rar = await configured.extract(
        sourcePath: path.join(
          Directory.current.path,
          'android',
          'app',
          'src',
          'test',
          'resources',
          'archives',
          'rar5-password-junrar.rar',
        ),
        displayName: '小说.rar',
        password: 'junrar',
      );
      addTearDown(() async {
        final temporary = Directory(rar['temporaryRoot'] as String);
        if (await temporary.exists()) await temporary.delete(recursive: true);
      });
      final rarItems = (rar['items'] as List<dynamic>)
          .cast<Map<String, dynamic>>();
      expect(rarItems.single['name'], 'file1.txt');
    },
  );
}

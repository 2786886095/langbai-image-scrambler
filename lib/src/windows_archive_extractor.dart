import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as path;

import 'models.dart';

class WindowsArchiveExtractor {
  const WindowsArchiveExtractor({this.executablePath});

  static const _maxEntryCount = 20000;
  static const _maxEntryBytes = 1024 * 1024 * 1024;
  static const _maxTotalBytes = 4 * 1024 * 1024 * 1024;

  final String? executablePath;

  Future<Map<String, dynamic>> extract({
    required String sourcePath,
    required String displayName,
    String? password,
  }) async {
    final source = File(sourcePath);
    if (!await source.exists()) {
      throw const WindowsArchiveException('archive_read_failed', '压缩包不存在');
    }
    final extension = path.extension(displayName).toLowerCase();
    if (!const {'.zip', '.7z', '.rar'}.contains(extension)) {
      throw const WindowsArchiveException(
        'archive_unsupported',
        '仅支持 ZIP、7Z、RAR 压缩包',
      );
    }

    final executable = executablePath ?? _bundled7zPath();
    if (!await File(executable).exists()) {
      throw const WindowsArchiveException(
        'archive_read_failed',
        'Windows 压缩包组件缺失',
      );
    }
    await _validateArchive(executable, source.path, password);

    final sessionRoot = await Directory.systemTemp.createTemp(
      'langbai-archive-',
    );
    final rawRoot = Directory(path.join(sessionRoot.path, '.raw'));
    final rootName = _safeSegment(
      basenameWithoutExtension(displayName),
      fallback: '压缩包',
    );
    final outputRoot = Directory(path.join(sessionRoot.path, rootName));
    await rawRoot.create(recursive: true);
    await outputRoot.create(recursive: true);
    try {
      final result = await Process.run(executable, [
        'x',
        source.path,
        '-o${rawRoot.path}',
        '-y',
        '-aoa',
        '-snl-',
        '-snh-',
        if (password != null && password.isNotEmpty) '-p$password',
      ], runInShell: false);
      if (result.exitCode != 0) {
        throw _processError(result, password);
      }

      final items = <Map<String, dynamic>>[];
      var skippedCount = 0;
      var totalBytes = 0;
      await for (final entity in rawRoot.list(
        recursive: true,
        followLinks: false,
      )) {
        if (entity is! File) continue;
        final relative = path.relative(entity.path, from: rawRoot.path);
        final normalized = path.posix.joinAll(path.split(relative));
        final name = path.posix.basename(normalized);
        final isText = isSupportedTextName(name);
        if (!isText && !isSupportedImageName(name)) {
          skippedCount++;
          continue;
        }
        final size = await entity.length();
        if (size > _maxEntryBytes || totalBytes + size > _maxTotalBytes) {
          throw const WindowsArchiveException('archive_limit', '压缩包解压内容超过安全上限');
        }
        totalBytes += size;
        final segments = path.posix
            .split(normalized)
            .map((value) => _safeSegment(value, fallback: '_'))
            .toList(growable: false);
        final destination = File(path.joinAll([outputRoot.path, ...segments]));
        final safeRoot = outputRoot.absolute.path;
        final safeDestination = destination.absolute.path;
        if (!path.isWithin(safeRoot, safeDestination)) {
          throw const WindowsArchiveException(
            'archive_unsafe_path',
            '压缩包包含越界路径',
          );
        }
        await destination.parent.create(recursive: true);
        final uniqueDestination = await _uniqueFile(destination);
        await entity.copy(uniqueDestination.path);
        final relativePath = path
            .relative(uniqueDestination.path, from: outputRoot.path)
            .replaceAll('\\', '/');
        final directoryName = path.dirname(relativePath).replaceAll('\\', '/');
        final relativeDirectory = directoryName == '.' ? '' : directoryName;
        items.add({
          'path': uniqueDestination.path,
          'name': path.basename(uniqueDestination.path),
          'relativeDirectory': relativeDirectory,
          'relativePath': relativePath,
          'size': size,
          'kind': isText ? 'text' : 'image',
        });
      }
      await rawRoot.delete(recursive: true);
      return {
        'rootName': rootName,
        'temporaryRoot': sessionRoot.path,
        'skippedCount': skippedCount,
        'items': items,
      };
    } catch (_) {
      if (await sessionRoot.exists()) await sessionRoot.delete(recursive: true);
      rethrow;
    }
  }

  Future<void> _validateArchive(
    String executable,
    String sourcePath,
    String? password,
  ) async {
    final result = await Process.run(executable, [
      'l',
      '-slt',
      sourcePath,
      if (password != null && password.isNotEmpty) '-p$password',
    ], runInShell: false);
    if (result.exitCode != 0) throw _processError(result, password);
    final output = _decodeConsole(result.stdout);
    var entryCount = 0;
    var totalBytes = 0;
    for (final line in const LineSplitter().convert(output)) {
      if (!line.startsWith('Size = ')) continue;
      final size = int.tryParse(line.substring(7).trim());
      if (size == null) continue;
      entryCount++;
      if (entryCount > _maxEntryCount) {
        throw const WindowsArchiveException(
          'archive_limit',
          '压缩包文件数量超过 20000 个',
        );
      }
      if (size > _maxEntryBytes || totalBytes + size > _maxTotalBytes) {
        throw const WindowsArchiveException('archive_limit', '压缩包解压内容超过安全上限');
      }
      totalBytes += size;
    }
  }

  WindowsArchiveException _processError(
    ProcessResult result,
    String? password,
  ) {
    final detail =
        '${_decodeConsole(result.stderr)}\n'
        '${_decodeConsole(result.stdout)}';
    final passwordFailure =
        detail.contains('Wrong password') ||
        detail.contains('password is incorrect') ||
        detail.contains('Data Error in encrypted file') ||
        (password != null && detail.contains('Headers Error'));
    if (passwordFailure) {
      return const WindowsArchiveException(
        'archive_password',
        '密码为空或不正确，请重新输入',
      );
    }
    return WindowsArchiveException(
      'archive_extract_failed',
      '压缩包解压失败（${result.exitCode}）',
    );
  }

  String _decodeConsole(Object? value) {
    if (value is List<int>) return systemEncoding.decode(value);
    return value?.toString() ?? '';
  }

  String _safeSegment(String value, {required String fallback}) {
    final cleaned = value
        .replaceAll(RegExp(r'[<>:"/\\|?*\x00-\x1f]'), '_')
        .trim();
    if (cleaned.isEmpty || cleaned == '.' || cleaned == '..') return fallback;
    return cleaned;
  }

  Future<File> _uniqueFile(File desired) async {
    if (!await desired.exists()) return desired;
    final extension = path.extension(desired.path);
    final base = path.basenameWithoutExtension(desired.path);
    var index = 1;
    while (true) {
      final candidate = File(
        path.join(desired.parent.path, '$base（$index）$extension'),
      );
      if (!await candidate.exists()) return candidate;
      index++;
    }
  }

  String _bundled7zPath() => path.join(
    path.dirname(Platform.resolvedExecutable),
    'data',
    'flutter_assets',
    'assets',
    'bin',
    'windows',
    '7z.exe',
  );
}

class WindowsArchiveException implements Exception {
  const WindowsArchiveException(this.code, this.message);

  final String code;
  final String message;

  @override
  String toString() => message;
}

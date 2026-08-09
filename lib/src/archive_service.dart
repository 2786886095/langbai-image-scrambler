import 'dart:convert';
import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as path;

import 'models.dart';

class ArchiveEntryInput {
  const ArchiveEntryInput({
    required this.sourcePath,
    required this.archivePath,
  });

  final String sourcePath;
  final String archivePath;
}

class ArchiveGroupPlan {
  const ArchiveGroupPlan({required this.baseName, required this.entries});

  final String baseName;
  final List<ArchiveEntryInput> entries;
}

class PreparedArchive {
  const PreparedArchive({required this.path, required this.fileName});

  final String path;
  final String fileName;
}

class ArchiveService {
  ArchiveService({
    MethodChannel? channel,
    this.windows7zrPath,
    this._temporaryRoot,
  }) : _channel =
           channel ?? const MethodChannel('com.langbai.imagescrambler/saf');

  final MethodChannel _channel;
  final String? windows7zrPath;
  final Directory? _temporaryRoot;

  List<String> plannedFileNames({
    required List<ImageTask> tasks,
    required CompressionGrouping grouping,
    required CompressionArchiveFormat format,
    DateTime? now,
  }) {
    final placeholderPaths = <String, String>{
      for (final task in tasks) task.id: task.id,
    };
    return plan(
      tasks: tasks,
      stagedPaths: placeholderPaths,
      grouping: grouping,
      now: now,
    ).map((group) => '${group.baseName}.${format.extension}').toList();
  }

  List<ArchiveGroupPlan> plan({
    required List<ImageTask> tasks,
    required Map<String, String> stagedPaths,
    required CompressionGrouping grouping,
    DateTime? now,
  }) {
    final processedTasks = tasks
        .where((task) => stagedPaths.containsKey(task.id))
        .toList(growable: false);
    if (processedTasks.isEmpty) return const [];

    switch (grouping) {
      case CompressionGrouping.perFile:
        return processedTasks
            .map(
              (task) => ArchiveGroupPlan(
                baseName: sanitizeFileName(
                  basenameWithoutExtension(task.originalName),
                ),
                entries: [
                  ArchiveEntryInput(
                    sourcePath: stagedPaths[task.id]!,
                    archivePath: _safeArchiveSegment(_processedFileName(task)),
                  ),
                ],
              ),
            )
            .toList(growable: false);
      case CompressionGrouping.perFolder:
        final grouped = <String, List<ImageTask>>{};
        for (final task in processedTasks) {
          final key = task.sourceRootId.isNotEmpty
              ? 'root:${task.sourceRootId}'
              : 'file:${task.id}';
          grouped.putIfAbsent(key, () => []).add(task);
        }
        return grouped.values
            .map((groupTasks) {
              final first = groupTasks.first;
              final baseName = first.sourceRootName.trim().isNotEmpty
                  ? first.sourceRootName
                  : basenameWithoutExtension(first.originalName);
              return ArchiveGroupPlan(
                baseName: sanitizeFileName(baseName),
                entries: _entriesFor(
                  groupTasks,
                  stagedPaths,
                  includeRoot: false,
                ),
              );
            })
            .toList(growable: false);
      case CompressionGrouping.combined:
        final instant = now ?? DateTime.now();
        final stamp =
            '${instant.year.toString().padLeft(4, '0')}'
            '${instant.month.toString().padLeft(2, '0')}'
            '${instant.day.toString().padLeft(2, '0')}_'
            '${instant.hour.toString().padLeft(2, '0')}'
            '${instant.minute.toString().padLeft(2, '0')}'
            '${instant.second.toString().padLeft(2, '0')}';
        return [
          ArchiveGroupPlan(
            baseName: 'Langbai_$stamp',
            entries: _entriesFor(
              processedTasks,
              stagedPaths,
              includeRoot: true,
            ),
          ),
        ];
    }
  }

  Future<List<PreparedArchive>> create({
    required List<ArchiveGroupPlan> groups,
    required CompressionArchiveFormat format,
    String? password,
  }) async {
    if (groups.isEmpty) return const [];
    final ownsRoot = _temporaryRoot == null;
    final root =
        _temporaryRoot ??
        await Directory.systemTemp.createTemp('langbai-archive-output-');
    if (!await root.exists()) await root.create(recursive: true);
    final outputs = <PreparedArchive>[];
    try {
      for (var index = 0; index < groups.length; index++) {
        final group = groups[index];
        final uniqueBase = await _uniqueLocalBase(root, group.baseName);
        final fileName = '$uniqueBase.${format.extension}';
        final output = path.join(root.path, fileName);
        if (format == CompressionArchiveFormat.zip) {
          await _createZip(output, group.entries, password);
        } else {
          await _create7z(output, group.entries, password, index);
        }
        final file = File(output);
        if (!await file.exists() || await file.length() == 0) {
          throw ArchiveCreationException('压缩包生成失败：$fileName');
        }
        outputs.add(PreparedArchive(path: output, fileName: fileName));
      }
      return outputs;
    } catch (_) {
      for (final file in root.listSync().whereType<File>()) {
        try {
          file.deleteSync();
        } catch (_) {}
      }
      if (ownsRoot) {
        try {
          if (root.existsSync()) root.deleteSync(recursive: true);
        } catch (_) {}
      }
      rethrow;
    }
  }

  Future<void> cleanup(List<PreparedArchive> archives) async {
    final parents = <String>{};
    for (final archive in archives) {
      final file = File(archive.path);
      parents.add(file.parent.path);
      try {
        if (await file.exists()) await file.delete();
      } catch (_) {}
    }
    for (final parent in parents) {
      try {
        final directory = Directory(parent);
        if (await directory.exists() && (await directory.list().isEmpty)) {
          await directory.delete();
        }
      } catch (_) {}
    }
  }

  List<ArchiveEntryInput> _entriesFor(
    List<ImageTask> tasks,
    Map<String, String> stagedPaths, {
    required bool includeRoot,
  }) {
    final used = <String>{};
    final output = <ArchiveEntryInput>[];
    for (final task in tasks) {
      final segments = <String>[
        if (includeRoot && task.sourceRootName.trim().isNotEmpty)
          task.sourceRootName,
        if (task.relativeDirectory.trim().isNotEmpty)
          ...task.relativeDirectory.split(RegExp(r'[/\\]+')),
        _processedFileName(task),
      ].map(_safeArchiveSegment).where((item) => item.isNotEmpty).toList();
      var candidate = segments.join('/');
      var suffix = 1;
      while (!used.add(candidate.toLowerCase())) {
        final extension = path.posix.extension(candidate);
        final base = candidate.substring(
          0,
          candidate.length - extension.length,
        );
        candidate = '$base（$suffix）$extension';
        suffix++;
      }
      output.add(
        ArchiveEntryInput(
          sourcePath: stagedPaths[task.id]!,
          archivePath: candidate,
        ),
      );
    }
    return output;
  }

  String _safeArchiveSegment(String value) {
    final clean = value
        .replaceAll(RegExp(r'[<>:"/\\|?*\x00-\x1f]'), '_')
        .trim();
    if (clean == '.' || clean == '..') return '_';
    return clean;
  }

  String _processedFileName(ImageTask task) =>
      task.workspaceType == WorkspaceType.text
      ? sanitizeFileName(task.originalName)
      : '${sanitizeFileName(basenameWithoutExtension(task.originalName))}.png';

  Future<String> _uniqueLocalBase(Directory root, String desired) async {
    final safe = _safeArchiveSegment(desired).isEmpty
        ? 'Langbai'
        : _safeArchiveSegment(desired);
    var candidate = safe;
    var index = 1;
    while (await File(path.join(root.path, '$candidate.zip')).exists() ||
        await File(path.join(root.path, '$candidate.7z')).exists()) {
      candidate = '$safe（$index）';
      index++;
    }
    return candidate;
  }

  Future<void> _createZip(
    String output,
    List<ArchiveEntryInput> entries,
    String? password,
  ) async {
    final hasPassword = password != null && password.trim().isNotEmpty;
    final encoder = ZipFileEncoder(password: hasPassword ? password : null);
    encoder.create(output, level: ZipFileEncoder.store);
    try {
      for (final entry in entries) {
        await encoder.addFile(
          File(entry.sourcePath),
          entry.archivePath,
          ZipFileEncoder.store,
        );
      }
    } finally {
      await encoder.close();
    }
  }

  Future<void> _create7z(
    String output,
    List<ArchiveEntryInput> entries,
    String? password,
    int groupIndex,
  ) async {
    if (Platform.isAndroid) {
      await _channel.invokeMethod<void>('createArchive', {
        'outputPath': output,
        'format': '7z',
        'password': password ?? '',
        'entries': entries
            .map(
              (entry) => {
                'sourcePath': entry.sourcePath,
                'archivePath': entry.archivePath,
              },
            )
            .toList(growable: false),
      });
      return;
    }

    final root = Directory(
      path.join(path.dirname(output), '.stage-$groupIndex'),
    );
    await root.create(recursive: true);
    try {
      for (final entry in entries) {
        final target = File(
          path.joinAll([root.path, ...entry.archivePath.split('/')]),
        );
        await target.parent.create(recursive: true);
        await File(entry.sourcePath).copy(target.path);
      }
      final executable = windows7zrPath ?? _bundled7zrPath();
      final args = <String>[
        'a',
        '-t7z',
        output,
        '.',
        '-y',
        '-mx=1',
        if (password != null && password.isNotEmpty) ...['-mhe=on', '-p'],
      ];
      final process = await Process.start(
        executable,
        args,
        workingDirectory: root.path,
        runInShell: false,
      );
      final stdoutFuture = process.stdout
          .transform(const Utf8Decoder(allowMalformed: true))
          .join();
      final stderrFuture = process.stderr
          .transform(const Utf8Decoder(allowMalformed: true))
          .join();
      if (password != null && password.isNotEmpty) {
        process.stdin.writeln(password);
      }
      await process.stdin.close();
      final exitCode = await process.exitCode;
      final stdoutText = await stdoutFuture;
      final stderrText = await stderrFuture;
      if (exitCode != 0) {
        throw ArchiveCreationException(
          '7Z 生成失败（$exitCode）：${stderrText.trim().isNotEmpty ? stderrText.trim() : stdoutText.trim()}',
        );
      }
    } finally {
      if (await root.exists()) await root.delete(recursive: true);
    }
  }

  String _bundled7zrPath() => path.join(
    path.dirname(Platform.resolvedExecutable),
    'data',
    'flutter_assets',
    'assets',
    'bin',
    'windows',
    '7zr.exe',
  );
}

class ArchiveCreationException implements Exception {
  const ArchiveCreationException(this.message);
  final String message;
  @override
  String toString() => message;
}

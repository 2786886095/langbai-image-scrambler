import 'dart:async';
import 'dart:io';
import 'package:cross_file/cross_file.dart';
import 'package:crypto/crypto.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as path;

import 'app_settings.dart';
import 'export_history.dart';
import 'models.dart';

class FileService {
  static const _channel = MethodChannel('com.langbai.imagescrambler/saf');
  static const _imageExtensions = [
    'png',
    'jpg',
    'jpeg',
    'webp',
    'bmp',
    'tif',
    'tiff',
  ];
  Future<void> _saveTail = Future<void>.value();

  Future<ImportBatch?> pickFiles(WorkspaceType workspaceType) async {
    final textMode = workspaceType == WorkspaceType.text;
    final result = await FilePicker.platform.pickFiles(
      allowMultiple: true,
      type: FileType.custom,
      allowedExtensions: textMode ? const ['txt'] : _imageExtensions,
      dialogTitle: textMode ? '选择小说 TXT' : '选择图片',
      withData: false,
      withReadStream: false,
    );
    if (result == null || result.files.isEmpty) return null;
    final stamp = DateTime.now().microsecondsSinceEpoch;
    final tasks = <ImageTask>[];
    for (var index = 0; index < result.files.length; index++) {
      final file = result.files[index];
      if (file.path == null) continue;
      tasks.add(
        ImageTask(
          id: '$stamp-$index',
          originalName: file.name,
          relativeDirectory: '',
          sourceRootName: '',
          inputPath: file.path,
          sizeBytes: file.size,
        ),
      );
    }
    if (tasks.isEmpty) return null;
    return ImportBatch(
      tasks: tasks,
      isFolder: false,
      rootName: '',
      workspaceType: workspaceType,
    );
  }

  Future<ImportBatch?> pickImages() => pickFiles(WorkspaceType.image);

  Future<ImportBatch?> pickFolder({
    WorkspaceType workspaceType = WorkspaceType.image,
  }) async {
    if (Platform.isAndroid) return _pickAndroidFolder(workspaceType);
    final selected = await FilePicker.platform.getDirectoryPath(
      dialogTitle: workspaceType == WorkspaceType.text
          ? '选择小说 TXT 文件夹'
          : '选择图片文件夹',
    );
    if (selected == null) return null;
    return importFolderPath(selected, workspaceType: workspaceType);
  }

  Future<ImportBatch> importFolderPath(
    String folderPath, {
    WorkspaceType workspaceType = WorkspaceType.image,
  }) async {
    final directory = Directory(folderPath);
    if (!await directory.exists()) {
      throw const FileServiceException('文件夹不存在');
    }
    final rootName = path.basename(directory.path);
    final tasks = <ImageTask>[];
    var index = 0;
    await for (final entity in directory.list(
      recursive: true,
      followLinks: false,
    )) {
      if (entity is! File || !_isSupported(entity.path, workspaceType)) {
        continue;
      }
      final relative = path.relative(
        path.dirname(entity.path),
        from: directory.path,
      );
      tasks.add(
        ImageTask(
          id: '${DateTime.now().microsecondsSinceEpoch}-${index++}',
          originalName: path.basename(entity.path),
          relativeDirectory: relative == '.' ? '' : relative,
          sourceRootName: rootName,
          sourceRootId: directory.absolute.path,
          inputPath: entity.path,
          sizeBytes: await entity.length(),
        ),
      );
    }
    tasks.sort((left, right) {
      final a = path.join(left.relativeDirectory, left.originalName);
      final b = path.join(right.relativeDirectory, right.originalName);
      return a.toLowerCase().compareTo(b.toLowerCase());
    });
    return ImportBatch(
      tasks: tasks,
      isFolder: true,
      rootName: rootName,
      workspaceType: workspaceType,
    );
  }

  Future<ImportBatch?> importDropped(
    List<XFile> dropped, {
    WorkspaceType workspaceType = WorkspaceType.image,
  }) async {
    if (dropped.isEmpty) return null;
    final tasks = <ImageTask>[];
    var containsFolder = false;
    var firstRootName = '';
    var index = 0;
    for (final item in dropped) {
      final directory = Directory(item.path);
      if (await directory.exists()) {
        final imported = await importFolderPath(
          directory.path,
          workspaceType: workspaceType,
        );
        containsFolder = true;
        if (firstRootName.isEmpty) firstRootName = imported.rootName;
        tasks.addAll(imported.tasks);
        continue;
      }
      final file = File(item.path);
      if (!await file.exists() || !_isSupported(item.path, workspaceType)) {
        continue;
      }
      tasks.add(
        ImageTask(
          id: '${DateTime.now().microsecondsSinceEpoch}-${index++}',
          originalName: path.basename(item.path),
          relativeDirectory: '',
          sourceRootName: '',
          inputPath: item.path,
          sizeBytes: await file.length(),
        ),
      );
    }
    return tasks.isEmpty
        ? null
        : ImportBatch(
            tasks: tasks,
            isFolder: containsFolder,
            rootName: firstRootName,
            workspaceType: workspaceType,
          );
  }

  Future<Uint8List> readTask(ImageTask task) async {
    if (task.inputPath != null) {
      return File(task.inputPath!).readAsBytes();
    }
    if (task.sourceUri != null && Platform.isAndroid) {
      final cachePath = await _channel.invokeMethod<String>('copyUriToCache', {
        'uri': task.sourceUri,
        'name': task.originalName,
      });
      if (cachePath == null) {
        throw const FileServiceException('读取 Android 图片失败');
      }
      return File(cachePath).readAsBytes();
    }
    throw const FileServiceException('图片来源不可读取');
  }

  Future<ExportTarget?> chooseExportTarget({
    required ImportBatch batch,
    required ProcessMode mode,
    required AppSettings settings,
  }) async {
    final single = batch.tasks.length == 1 && !batch.isFolder;
    final rootFolderName = batch.isFolder
        ? sanitizeFileName(batch.rootName)
        : _batchFolderName(mode, batch.workspaceType);

    final suggestedName = outputFileName(
      batch.tasks.first,
      mode,
      workspaceType: batch.workspaceType,
    );
    if (Platform.isAndroid) {
      if (single && settings.askExportEveryTime) {
        return ExportTarget(
          rootFolderName: '',
          singleFile: true,
          displayLabel: suggestedName,
        );
      }
      String? treeUri;
      if (!settings.askExportEveryTime) {
        treeUri = settings.defaultExportTreeUri;
      }
      if (treeUri == null) {
        final tree = await _pickTree();
        if (tree == null) return null;
        treeUri = tree.uri;
        if (!settings.askExportEveryTime) {
          await settings.setDefaultExport(treeUri: tree.uri, label: tree.name);
        }
      }
      if (!single) {
        final taskRoots = <String, String>{};
        final createdDirectories = <String>[];
        final groups = _outputGroups(batch, rootFolderName);
        for (final group in groups) {
          final reserved = await _channel.invokeMapMethod<String, dynamic>(
            'createUniqueDirectory',
            {'treeUri': treeUri, 'desiredName': group.name},
          );
          if (reserved == null) {
            throw const FileServiceException('建立唯一导出文件夹失败');
          }
          final actualName = reserved['name'] as String? ?? group.name;
          final directoryUri = reserved['uri'] as String?;
          for (final task in group.tasks) {
            taskRoots[task.id] = actualName;
          }
          if (directoryUri != null) createdDirectories.add(directoryUri);
        }
        return ExportTarget(
          treeUri: treeUri,
          rootFolderName: '',
          singleFile: false,
          displayLabel: groups.length == 1
              ? '${taskRoots.values.first}/'
              : '${groups.length} 个文件夹',
          createdDirectories: createdDirectories,
          taskRootFolderNames: taskRoots,
        );
      }
      return ExportTarget(
        treeUri: treeUri,
        rootFolderName: '',
        singleFile: true,
        displayLabel: suggestedName,
      );
    }

    if (single) {
      if (!settings.askExportEveryTime && settings.defaultExportPath != null) {
        final uniquePath = await _uniqueFilePath(
          path.join(settings.defaultExportPath!, suggestedName),
        );
        return ExportTarget(
          path: uniquePath,
          rootFolderName: '',
          singleFile: true,
          displayLabel: uniquePath,
        );
      }
      var selected = await FilePicker.platform.saveFile(
        dialogTitle: batch.workspaceType == WorkspaceType.text
            ? '导出 TXT'
            : '导出图片',
        fileName: suggestedName,
        type: FileType.custom,
        allowedExtensions: batch.workspaceType == WorkspaceType.text
            ? const ['txt']
            : const ['png'],
      );
      if (selected == null) return null;
      final extension = batch.workspaceType == WorkspaceType.text
          ? '.txt'
          : '.png';
      if (!selected.toLowerCase().endsWith(extension)) selected += extension;
      final uniquePath = await _uniqueFilePath(selected);
      return ExportTarget(
        path: uniquePath,
        rootFolderName: '',
        singleFile: true,
        displayLabel: uniquePath,
      );
    }

    var selectedDirectory = settings.askExportEveryTime
        ? null
        : settings.defaultExportPath;
    selectedDirectory ??= await FilePicker.platform.getDirectoryPath(
      dialogTitle: '选择导出位置',
    );
    if (selectedDirectory == null) return null;
    final taskRoots = <String, String>{};
    final createdDirectories = <String>[];
    final groups = _outputGroups(batch, rootFolderName);
    for (final group in groups) {
      final reserved = await _createUniqueDirectory(
        path.join(selectedDirectory, group.name),
      );
      createdDirectories.add(reserved.path);
      for (final task in group.tasks) {
        taskRoots[task.id] = reserved.path;
      }
    }
    return ExportTarget(
      path: selectedDirectory,
      rootFolderName: '',
      singleFile: false,
      displayLabel: groups.length == 1
          ? taskRoots.values.first
          : '$selectedDirectory · ${groups.length} 个文件夹',
      createdDirectories: createdDirectories,
      taskRootPaths: taskRoots,
    );
  }

  Future<SaveOutputResult> saveOutput({
    required Uint8List bytes,
    required ImageTask task,
    required ProcessMode mode,
    required ExportTarget target,
    WorkspaceType workspaceType = WorkspaceType.image,
  }) => _enqueueSave(
    () => _saveOutputUnlocked(
      bytes: bytes,
      task: task,
      mode: mode,
      target: target,
      workspaceType: workspaceType,
    ),
  );

  Future<SaveOutputResult> _saveOutputUnlocked({
    required Uint8List bytes,
    required ImageTask task,
    required ProcessMode mode,
    required ExportTarget target,
    required WorkspaceType workspaceType,
  }) async {
    final fileName = outputFileName(task, mode, workspaceType: workspaceType);
    final mimeType = workspaceType == WorkspaceType.text
        ? 'text/plain'
        : 'image/png';
    if (!Platform.isAndroid) {
      final taskRoot = target.taskRootPaths[task.id];
      final desiredOutputPath = target.singleFile
          ? target.path!
          : path.joinAll([
              taskRoot ?? target.path!,
              if (taskRoot == null) target.rootFolderName,
              task.relativeDirectory,
              fileName,
            ]);
      final outputPath = await _uniqueFilePath(desiredOutputPath);
      final file = File(outputPath);
      final createdDirectories = await _createMissingDirectories(file.parent);
      await file.writeAsBytes(bytes, flush: true);
      return SaveOutputResult(
        location: file.path,
        displayName: path.basename(file.path),
        sha256Digest: sha256.convert(bytes).toString(),
        sizeBytes: bytes.length,
        createdDirectories: createdDirectories,
      );
    }

    final temporaryDirectory = Directory.systemTemp;
    final temporaryFile = File(
      path.join(
        temporaryDirectory.path,
        'langbai-output-${DateTime.now().microsecondsSinceEpoch}'
        '${workspaceType == WorkspaceType.text ? '.txt' : '.png'}',
      ),
    );
    await temporaryFile.writeAsBytes(bytes, flush: true);
    try {
      if (target.singleFile && target.treeUri == null) {
        final saved = await _channel.invokeMethod<dynamic>('saveDocument', {
          'sourcePath': temporaryFile.path,
          'suggestedName': fileName,
          'mimeType': mimeType,
        });
        if (saved == null) throw const ExportCancelledException();
        final uri = saved is String
            ? saved
            : Map<String, dynamic>.from(saved as Map)['uri'] as String;
        final actualName = saved is String
            ? fileName
            : Map<String, dynamic>.from(saved as Map)['name'] as String? ??
                  fileName;
        return SaveOutputResult(
          location: uri,
          displayName: actualName,
          sha256Digest: sha256.convert(bytes).toString(),
          sizeBytes: bytes.length,
        );
      }
      final relativeFolder = [
        if ((target.taskRootFolderNames[task.id] ?? target.rootFolderName)
            .isNotEmpty)
          target.taskRootFolderNames[task.id] ?? target.rootFolderName,
        if (task.relativeDirectory.isNotEmpty) task.relativeDirectory,
      ].join('/');
      final saved = await _channel
          .invokeMapMethod<String, dynamic>('writeFileToTree', {
            'treeUri': target.treeUri,
            'relativeFolder': relativeFolder,
            'fileName': fileName,
            'sourcePath': temporaryFile.path,
            'mimeType': mimeType,
          });
      if (saved == null) {
        throw const FileServiceException('写入 Android 文件夹失败');
      }
      final uri = saved['uri'] as String?;
      if (uri == null) throw const FileServiceException('写入 Android 文件夹失败');
      return SaveOutputResult(
        location: uri,
        displayName: saved['name'] as String? ?? fileName,
        sha256Digest: sha256.convert(bytes).toString(),
        sizeBytes: bytes.length,
        createdDirectories:
            (saved['createdDirectories'] as List<dynamic>? ?? const [])
                .whereType<String>()
                .toList(growable: false),
      );
    } finally {
      if (await temporaryFile.exists()) await temporaryFile.delete();
    }
  }

  Future<T> _enqueueSave<T>(Future<T> Function() action) {
    final completer = Completer<T>();
    _saveTail = _saveTail.then((_) async {
      try {
        completer.complete(await action());
      } catch (error, stackTrace) {
        completer.completeError(error, stackTrace);
      }
    });
    return completer.future;
  }

  Future<UndoResult> undoExport(ExportHistoryEntry entry) async {
    var deleted = 0;
    var modified = 0;
    var missing = 0;
    var failed = 0;
    for (final artifact in entry.artifacts) {
      try {
        if (Platform.isAndroid) {
          final status = await _channel.invokeMethod<String>(
            'deleteDocumentIfHash',
            {'uri': artifact.location, 'sha256': artifact.sha256},
          );
          switch (status) {
            case 'deleted':
              deleted++;
              break;
            case 'modified':
              modified++;
              break;
            case 'missing':
              missing++;
              break;
            default:
              failed++;
              break;
          }
          continue;
        }
        final file = File(artifact.location);
        if (!await file.exists()) {
          missing++;
          continue;
        }
        final currentHash = sha256.convert(await file.readAsBytes()).toString();
        if (currentHash != artifact.sha256) {
          modified++;
          continue;
        }
        await file.delete();
        deleted++;
      } catch (_) {
        failed++;
      }
    }

    final directories = entry.createdDirectories.toSet().toList()
      ..sort((left, right) => right.length.compareTo(left.length));
    for (final location in directories) {
      try {
        if (Platform.isAndroid) {
          await _channel.invokeMethod<bool>('deleteEmptyDocument', {
            'uri': location,
          });
        } else {
          final directory = Directory(location);
          if (await directory.exists()) {
            final children = await directory.list().toList();
            if (children.isEmpty) await directory.delete();
          }
        }
      } catch (_) {
        // A non-empty or externally changed folder is intentionally preserved.
      }
    }
    return UndoResult(
      deleted: deleted,
      modified: modified,
      missing: missing,
      failed: failed,
    );
  }

  Future<DefaultExportSelection?> chooseDefaultExport() async {
    if (Platform.isAndroid) {
      final tree = await _pickTree();
      if (tree == null) return null;
      return DefaultExportSelection(treeUri: tree.uri, label: tree.name);
    }
    final selected = await FilePicker.platform.getDirectoryPath(
      dialogTitle: '选择固定导出文件夹',
    );
    if (selected == null) return null;
    return DefaultExportSelection(path: selected, label: selected);
  }

  String outputFileName(
    ImageTask task,
    ProcessMode mode, {
    WorkspaceType workspaceType = WorkspaceType.image,
  }) {
    var base = basenameWithoutExtension(task.originalName);
    if (workspaceType == WorkspaceType.text) {
      if (mode == ProcessMode.restore) {
        base = base.replaceFirst(
          RegExp(r'[_-](混淆|混淆文|encoded|base64)$', caseSensitive: false),
          '',
        );
        return '${sanitizeFileName(base)}_还原.txt';
      }
      return '${sanitizeFileName(base)}_混淆.txt';
    }
    if (mode == ProcessMode.restore) {
      base = base.replaceFirst(RegExp(r'[_-](混淆|混淆圖|scrambled)$'), '');
    }
    return '${sanitizeFileName(base)}.png';
  }

  Future<String> _uniqueFilePath(String desiredPath) async {
    if (!await FileSystemEntity.type(
      desiredPath,
    ).then((type) => type != FileSystemEntityType.notFound)) {
      return desiredPath;
    }
    final directory = path.dirname(desiredPath);
    final extension = path.extension(desiredPath);
    final base = path.basenameWithoutExtension(desiredPath);
    var index = 1;
    while (true) {
      final candidate = path.join(directory, '$base（$index）$extension');
      final exists = await FileSystemEntity.type(
        candidate,
      ).then((type) => type != FileSystemEntityType.notFound);
      if (!exists) return candidate;
      index++;
    }
  }

  Future<Directory> _createUniqueDirectory(String desiredPath) async {
    var candidate = desiredPath;
    var index = 1;
    while (await FileSystemEntity.type(
      candidate,
    ).then((type) => type != FileSystemEntityType.notFound)) {
      candidate = '$desiredPath（$index）';
      index++;
    }
    return Directory(candidate).create(recursive: true);
  }

  Future<List<String>> _createMissingDirectories(Directory directory) async {
    final missing = <String>[];
    var current = directory;
    while (!await current.exists()) {
      missing.add(current.path);
      final parent = current.parent;
      if (parent.path == current.path) break;
      current = parent;
    }
    for (final item in missing.reversed) {
      await Directory(item).create();
    }
    return missing;
  }

  String _batchFolderName(ProcessMode mode, WorkspaceType workspaceType) {
    final now = DateTime.now();
    String two(int value) => value.toString().padLeft(2, '0');
    final stamp =
        '${now.year}${two(now.month)}${two(now.day)}_'
        '${two(now.hour)}${two(now.minute)}${two(now.second)}';
    final action = workspaceType == WorkspaceType.text
        ? (mode == ProcessMode.scramble ? 'TXT转码' : 'TXT恢复')
        : (mode == ProcessMode.scramble ? '混淆' : '还原');
    return 'Langbai_${action}_$stamp';
  }

  Future<ImportBatch?> _pickAndroidFolder(WorkspaceType workspaceType) async {
    final tree = await _pickTree();
    if (tree == null) return null;
    final result = await _channel.invokeMapMethod<String, dynamic>('listTree', {
      'treeUri': tree.uri,
    });
    if (result == null) return null;
    final items = (result['items'] as List<dynamic>? ?? const []);
    final tasks = <ImageTask>[];
    for (var index = 0; index < items.length; index++) {
      final item = Map<String, dynamic>.from(items[index] as Map);
      final name = item['name'] as String? ?? '';
      if (!_isSupported(name, workspaceType)) continue;
      tasks.add(
        ImageTask(
          id: '${DateTime.now().microsecondsSinceEpoch}-$index',
          originalName: name,
          relativeDirectory: item['relativeDirectory'] as String? ?? '',
          sourceRootName: tree.name,
          sourceRootId: tree.uri,
          sourceUri: item['uri'] as String?,
          sizeBytes: (item['size'] as num?)?.toInt() ?? 0,
        ),
      );
    }
    return ImportBatch(
      tasks: tasks,
      isFolder: true,
      rootName: tree.name,
      workspaceType: workspaceType,
    );
  }

  bool _isSupported(String name, WorkspaceType workspaceType) {
    return workspaceType == WorkspaceType.text
        ? isSupportedTextName(name)
        : isSupportedImageName(name);
  }

  List<_OutputGroup> _outputGroups(ImportBatch batch, String fallbackName) {
    final grouped = <String, List<ImageTask>>{};
    final names = <String, String>{};
    final loose = <ImageTask>[];
    for (final task in batch.tasks) {
      if (task.sourceRootId.isEmpty) {
        loose.add(task);
      } else {
        grouped.putIfAbsent(task.sourceRootId, () => []).add(task);
        names[task.sourceRootId] = task.sourceRootName;
      }
    }
    final output = <_OutputGroup>[
      for (final entry in grouped.entries)
        _OutputGroup(names[entry.key] ?? fallbackName, entry.value),
    ];
    if (loose.isNotEmpty) output.add(_OutputGroup(fallbackName, loose));
    return output;
  }

  Future<_AndroidTree?> _pickTree() async {
    final result = await _channel.invokeMapMethod<String, dynamic>('pickTree');
    if (result == null) return null;
    return _AndroidTree(
      result['uri'] as String,
      result['name'] as String? ?? '图片',
    );
  }
}

class DefaultExportSelection {
  const DefaultExportSelection({this.path, this.treeUri, required this.label});
  final String? path;
  final String? treeUri;
  final String label;
}

class SaveOutputResult {
  const SaveOutputResult({
    required this.location,
    required this.displayName,
    required this.sha256Digest,
    required this.sizeBytes,
    this.createdDirectories = const [],
  });

  final String location;
  final String displayName;
  final String sha256Digest;
  final int sizeBytes;
  final List<String> createdDirectories;
}

class _AndroidTree {
  const _AndroidTree(this.uri, this.name);
  final String uri;
  final String name;
}

class _OutputGroup {
  const _OutputGroup(this.name, this.tasks);
  final String name;
  final List<ImageTask> tasks;
}

class FileServiceException implements Exception {
  const FileServiceException(this.message);
  final String message;

  @override
  String toString() => message;
}

class ExportCancelledException extends FileServiceException {
  const ExportCancelledException() : super('已取消导出');
}

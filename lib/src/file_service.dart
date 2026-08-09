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
import 'windows_archive_extractor.dart';

class FileService {
  FileService({WindowsArchiveExtractor? windowsArchiveExtractor})
    : _windowsArchiveExtractor =
          windowsArchiveExtractor ?? const WindowsArchiveExtractor();

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
  final WindowsArchiveExtractor _windowsArchiveExtractor;
  bool _drainingSharedIntents = false;
  void Function(SharedImportRequest request)? _sharedImportListener;

  Future<void> initializeSharedImports(
    void Function(SharedImportRequest request) listener,
  ) async {
    if (!Platform.isAndroid) return;
    _sharedImportListener = listener;
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'sharedIntentAvailable') await _drainSharedIntents();
    });
    await _drainSharedIntents();
  }

  Future<void> _drainSharedIntents() async {
    if (_drainingSharedIntents) return;
    _drainingSharedIntents = true;
    try {
      while (true) {
        final raw = await _channel.invokeMapMethod<String, dynamic>(
          'takePendingShare',
        );
        if (raw == null) break;
        final request = SharedImportRequest.fromMap(raw);
        if (request.items.isNotEmpty) _sharedImportListener?.call(request);
      }
    } finally {
      _drainingSharedIntents = false;
    }
  }

  Future<SharedImportRequest?> pickArchives() async {
    final result = await FilePicker.platform.pickFiles(
      allowMultiple: true,
      type: FileType.custom,
      allowedExtensions: const ['zip', '7z', 'rar'],
      dialogTitle: '选择 ZIP、7Z 或 RAR 压缩包',
      withData: false,
      withReadStream: false,
    );
    if (result == null || result.files.isEmpty) return null;
    final items = result.files
        .where((file) => file.path != null)
        .map(
          (file) => SharedImportItem(
            name: file.name,
            sourcePath: file.path,
            sizeBytes: file.size,
            mimeType: _archiveMimeType(file.name),
          ),
        )
        .toList(growable: false);
    if (items.isEmpty) return null;
    return SharedImportRequest(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      items: items,
    );
  }

  Future<ImportBatch> importShared(
    SharedImportRequest request, {
    Map<String, String> archivePasswords = const {},
  }) async {
    final tasks = <ImageTask>[];
    final temporaryRoots = <String>[];
    var skippedCount = 0;
    var containsFolder = false;
    var firstRootName = '';
    var taskIndex = 0;

    try {
      for (final item in request.items) {
        if (item.isDirectory) {
          final uri = item.uri;
          if (uri == null) {
            skippedCount++;
            continue;
          }
          final listed = await _channel.invokeMapMethod<String, dynamic>(
            'listSharedDirectory',
            {'uri': uri},
          );
          if (listed == null) {
            throw SharedImportException('分享的文件夹无法读取');
          }
          final rootName = listed['name'] as String? ?? item.name;
          firstRootName = firstRootName.isEmpty ? rootName : firstRootName;
          containsFolder = true;
          for (final raw in listed['items'] as List<dynamic>? ?? const []) {
            final entry = Map<String, dynamic>.from(raw as Map);
            final name = entry['name'] as String? ?? '';
            final kind = _workspaceForName(name);
            if (kind == null) {
              skippedCount++;
              continue;
            }
            tasks.add(
              ImageTask(
                id: '${request.id}-${taskIndex++}',
                originalName: name,
                relativeDirectory: entry['relativeDirectory'] as String? ?? '',
                sourceRootName: rootName,
                sourceRootId: uri,
                sourceUri: entry['uri'] as String?,
                sizeBytes: (entry['size'] as num?)?.toInt() ?? 0,
                workspaceType: kind,
              ),
            );
          }
          continue;
        }

        if (item.isArchive) {
          final sourceKey = _sharedSourceKey(item);
          final arguments = <String, dynamic>{
            'name': item.name,
            'password': archivePasswords[sourceKey] ?? '',
            if (item.uri != null) 'uri': item.uri,
            if (item.sourcePath != null) 'sourcePath': item.sourcePath,
          };
          late final Map<String, dynamic>? extracted;
          try {
            if (Platform.isWindows && item.sourcePath != null) {
              extracted = await _windowsArchiveExtractor.extract(
                sourcePath: item.sourcePath!,
                displayName: item.name,
                password: archivePasswords[sourceKey],
              );
            } else {
              extracted = await _channel.invokeMapMethod<String, dynamic>(
                'extractArchive',
                arguments,
              );
            }
          } on WindowsArchiveException catch (error) {
            throw SharedImportException(
              error.message,
              code: error.code,
              sourceName: item.name,
            );
          } on PlatformException catch (error) {
            throw SharedImportException(
              error.message ?? '压缩包解压失败',
              code: error.code,
              sourceName: item.name,
            );
          }
          if (extracted == null) {
            throw SharedImportException('压缩包解压失败', sourceName: item.name);
          }
          final rootName =
              extracted['rootName'] as String? ??
              basenameWithoutExtension(item.name);
          firstRootName = firstRootName.isEmpty ? rootName : firstRootName;
          containsFolder = true;
          final temporaryRoot = extracted['temporaryRoot'] as String?;
          if (temporaryRoot != null) temporaryRoots.add(temporaryRoot);
          skippedCount += (extracted['skippedCount'] as num?)?.toInt() ?? 0;
          for (final raw in extracted['items'] as List<dynamic>? ?? const []) {
            final entry = Map<String, dynamic>.from(raw as Map);
            final name = entry['name'] as String? ?? '';
            final kind = entry['kind'] == 'text'
                ? WorkspaceType.text
                : WorkspaceType.image;
            tasks.add(
              ImageTask(
                id: '${request.id}-${taskIndex++}',
                originalName: name,
                relativeDirectory: entry['relativeDirectory'] as String? ?? '',
                sourceRootName: rootName,
                sourceRootId: sourceKey,
                inputPath: entry['path'] as String?,
                sizeBytes: (entry['size'] as num?)?.toInt() ?? 0,
                workspaceType: kind,
              ),
            );
          }
          continue;
        }

        final kind = _workspaceForName(item.name);
        if (kind == null) {
          skippedCount++;
          continue;
        }
        tasks.add(
          ImageTask(
            id: '${request.id}-${taskIndex++}',
            originalName: item.name,
            relativeDirectory: '',
            sourceRootName: '',
            inputPath: item.sourcePath,
            sourceUri: item.uri,
            sizeBytes: item.sizeBytes,
            workspaceType: kind,
          ),
        );
      }
    } catch (_) {
      await cleanupTemporaryRoots(temporaryRoots);
      rethrow;
    }

    tasks.sort((left, right) {
      final a = path.join(
        left.sourceRootName,
        left.relativeDirectory,
        left.originalName,
      );
      final b = path.join(
        right.sourceRootName,
        right.relativeDirectory,
        right.originalName,
      );
      return a.toLowerCase().compareTo(b.toLowerCase());
    });
    final containsImages = tasks.any(
      (task) => task.workspaceType == WorkspaceType.image,
    );
    final containsText = tasks.any(
      (task) => task.workspaceType == WorkspaceType.text,
    );
    final batchWorkspace = containsImages && containsText
        ? WorkspaceType.mixed
        : containsText
        ? WorkspaceType.text
        : WorkspaceType.image;
    return ImportBatch(
      tasks: tasks,
      isFolder: containsFolder,
      rootName: firstRootName,
      workspaceType: batchWorkspace,
      temporaryRoots: temporaryRoots,
      skippedCount: skippedCount,
    );
  }

  Future<void> cleanupTemporaryRoots(Iterable<String> roots) async {
    for (final root in roots.toSet()) {
      try {
        final directory = Directory(root);
        if (await directory.exists()) await directory.delete(recursive: true);
      } catch (_) {
        // The Android cache directory may already have been reclaimed.
      }
    }
  }

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
          workspaceType: workspaceType,
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
          workspaceType: workspaceType,
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
          workspaceType: workspaceType,
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

  Future<String> stageOutputBytes(
    Uint8List bytes, {
    String suffix = '.png',
  }) async {
    final directory = await Directory.systemTemp.createTemp('langbai-stage-');
    final file = File(path.join(directory.path, 'output$suffix'));
    await file.writeAsBytes(bytes, flush: true);
    return file.path;
  }

  Future<void> cleanupStagedFiles(Iterable<String> paths) async {
    final parents = <String>{};
    for (final item in paths) {
      final file = File(item);
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

  Future<ExportTarget?> chooseArchiveExportTarget({
    required List<String> fileNames,
    required AppSettings settings,
  }) async {
    if (fileNames.isEmpty) return null;
    final single = fileNames.length == 1;
    final suggestedName = fileNames.first;
    if (Platform.isAndroid) {
      if (single && settings.askExportEveryTime) {
        final selected = await _channel
            .invokeMapMethod<String, dynamic>('pickSaveDocument', {
              'suggestedName': suggestedName,
              'mimeType': suggestedName.toLowerCase().endsWith('.zip')
                  ? 'application/zip'
                  : 'application/x-7z-compressed',
            });
        if (selected == null) return null;
        final documentUri = selected['uri'] as String?;
        if (documentUri == null || documentUri.isEmpty) return null;
        return ExportTarget(
          documentUri: documentUri,
          rootFolderName: '',
          singleFile: true,
          displayLabel: selected['name'] as String? ?? suggestedName,
        );
      }
      var treeUri = settings.askExportEveryTime
          ? null
          : settings.defaultExportTreeUri;
      if (treeUri == null) {
        final tree = await _pickTree();
        if (tree == null) return null;
        treeUri = tree.uri;
        if (!settings.askExportEveryTime) {
          await settings.setDefaultExport(treeUri: tree.uri, label: tree.name);
        }
      }
      if (single) {
        return ExportTarget(
          treeUri: treeUri,
          rootFolderName: '',
          singleFile: true,
          displayLabel: suggestedName,
        );
      }
      final reserved = await _channel.invokeMapMethod<String, dynamic>(
        'createUniqueDirectory',
        {'treeUri': treeUri, 'desiredName': _archiveBatchFolderName()},
      );
      if (reserved == null) {
        throw const FileServiceException('建立压缩包导出文件夹失败');
      }
      final actualName =
          reserved['name'] as String? ?? _archiveBatchFolderName();
      final uri = reserved['uri'] as String?;
      return ExportTarget(
        treeUri: treeUri,
        rootFolderName: actualName,
        singleFile: false,
        displayLabel: '$actualName/',
        createdDirectories: uri == null ? const [] : [uri],
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
      final extension = path.extension(suggestedName).replaceFirst('.', '');
      var selected = await FilePicker.platform.saveFile(
        dialogTitle: '导出压缩包',
        fileName: suggestedName,
        type: FileType.custom,
        allowedExtensions: [extension],
      );
      if (selected == null) return null;
      if (!selected.toLowerCase().endsWith('.$extension')) {
        selected += '.$extension';
      }
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
      dialogTitle: '选择压缩包导出位置',
    );
    if (selectedDirectory == null) return null;
    final directory = await _createUniqueDirectory(
      path.join(selectedDirectory, _archiveBatchFolderName()),
    );
    return ExportTarget(
      path: directory.path,
      rootFolderName: '',
      singleFile: false,
      displayLabel: directory.path,
      createdDirectories: [directory.path],
    );
  }

  Future<SaveOutputResult> savePreparedArchive({
    required String sourcePath,
    required String fileName,
    required ExportTarget target,
  }) => _enqueueSave(
    () => _savePreparedArchiveUnlocked(
      sourcePath: sourcePath,
      fileName: fileName,
      target: target,
    ),
  );

  Future<SaveOutputResult> _savePreparedArchiveUnlocked({
    required String sourcePath,
    required String fileName,
    required ExportTarget target,
  }) async {
    final source = File(sourcePath);
    if (!await source.exists()) {
      throw const FileServiceException('待导出的压缩包不存在');
    }
    final mimeType = fileName.toLowerCase().endsWith('.zip')
        ? 'application/zip'
        : 'application/x-7z-compressed';
    late final String location;
    late final String displayName;
    var createdDirectories = const <String>[];
    if (!Platform.isAndroid) {
      final desired = target.singleFile
          ? target.path!
          : path.join(target.path!, fileName);
      final outputPath = await _uniqueFilePath(desired);
      final output = await source.copy(outputPath);
      location = output.path;
      displayName = path.basename(output.path);
    } else if (target.documentUri != null) {
      final saved = await _channel.invokeMapMethod<String, dynamic>(
        'writeFileToUri',
        {'uri': target.documentUri, 'sourcePath': sourcePath},
      );
      if (saved == null) throw const FileServiceException('写入导出文件失败');
      location = saved['uri'] ?? target.documentUri!;
      displayName = saved['name'] ?? fileName;
    } else if (target.singleFile && target.treeUri == null) {
      final saved = await _channel.invokeMethod<dynamic>('saveDocument', {
        'sourcePath': sourcePath,
        'suggestedName': fileName,
        'mimeType': mimeType,
      });
      if (saved == null) throw const ExportCancelledException();
      final map = Map<String, dynamic>.from(saved as Map);
      location = map['uri'] as String;
      displayName = map['name'] as String? ?? fileName;
    } else {
      final saved = await _channel
          .invokeMapMethod<String, dynamic>('writeFileToTree', {
            'treeUri': target.treeUri,
            'relativeFolder': target.singleFile ? '' : target.rootFolderName,
            'fileName': fileName,
            'sourcePath': sourcePath,
            'mimeType': mimeType,
          });
      if (saved == null) throw const FileServiceException('写入压缩包失败');
      location = saved['uri'] as String;
      displayName = saved['name'] as String? ?? fileName;
      createdDirectories =
          (saved['createdDirectories'] as List<dynamic>? ?? const [])
              .cast<String>();
    }
    final digest = await sha256.bind(source.openRead()).first;
    return SaveOutputResult(
      location: location,
      displayName: displayName,
      sha256Digest: digest.toString(),
      sizeBytes: await source.length(),
      createdDirectories: createdDirectories,
    );
  }

  Future<void> cleanupUnusedExportTarget(ExportTarget target) async {
    try {
      if (Platform.isAndroid && target.documentUri != null) {
        await _channel.invokeMethod<bool>('deleteEmptyFile', {
          'uri': target.documentUri,
        });
      }
    } catch (_) {}
    final directories = target.createdDirectories.toSet().toList()
      ..sort((left, right) => right.length.compareTo(left.length));
    for (final location in directories) {
      try {
        if (Platform.isAndroid) {
          await _channel.invokeMethod<bool>('deleteEmptyDocument', {
            'uri': location,
          });
        } else {
          final directory = Directory(location);
          if (await directory.exists() && (await directory.list().isEmpty)) {
            await directory.delete();
          }
        }
      } catch (_) {}
    }
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
      workspaceType: batch.tasks.first.workspaceType,
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

  Future<void> openExportLocation(ExportHistoryEntry entry) async {
    final location = entry.locationToReveal;
    if (location == null || location.isEmpty) {
      throw const FileServiceException('导出记录中没有可打开的位置');
    }
    await openOutputLocation(location, isDirectory: entry.locationIsDirectory);
  }

  Future<void> openOutputLocation(
    String location, {
    required bool isDirectory,
  }) async {
    try {
      if (Platform.isAndroid) {
        await _channel.invokeMethod<void>('openOutputLocation', {
          'uri': location,
          'isDirectory': isDirectory,
        });
        return;
      }

      var target = location;
      if (isDirectory) {
        final type = await FileSystemEntity.type(target);
        if (type == FileSystemEntityType.notFound) {
          final parent = Directory(target).parent.path;
          if (await Directory(parent).exists()) target = parent;
        }
        await Process.start('explorer.exe', [
          target,
        ], mode: ProcessStartMode.detached);
        return;
      }

      if (!await File(target).exists()) {
        final parent = File(target).parent.path;
        if (await Directory(parent).exists()) {
          await Process.start('explorer.exe', [
            parent,
          ], mode: ProcessStartMode.detached);
          return;
        }
      }
      await Process.start('explorer.exe', [
        '/select,',
        target,
      ], mode: ProcessStartMode.detached);
    } catch (error) {
      throw FileServiceException('打开输出位置失败：$error');
    }
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
      return sanitizeFileName(task.originalName);
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
    final action = switch (workspaceType) {
      WorkspaceType.text => mode == ProcessMode.scramble ? 'TXT转码' : 'TXT恢复',
      WorkspaceType.mixed => mode == ProcessMode.scramble ? '混合混淆' : '混合还原',
      WorkspaceType.image => mode == ProcessMode.scramble ? '混淆' : '还原',
    };
    return 'Langbai_${action}_$stamp';
  }

  String _archiveBatchFolderName() {
    final now = DateTime.now();
    String two(int value) => value.toString().padLeft(2, '0');
    return 'Langbai_压缩_${now.year}${two(now.month)}${two(now.day)}_'
        '${two(now.hour)}${two(now.minute)}${two(now.second)}';
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
          workspaceType: workspaceType,
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

  WorkspaceType? _workspaceForName(String name) {
    if (isSupportedImageName(name)) return WorkspaceType.image;
    if (isSupportedTextName(name)) return WorkspaceType.text;
    return null;
  }

  String _sharedSourceKey(SharedImportItem item) =>
      item.uri ?? item.sourcePath ?? item.name;

  String _archiveMimeType(String name) =>
      switch (name.toLowerCase().split('.').last) {
        'zip' => 'application/zip',
        '7z' => 'application/x-7z-compressed',
        'rar' => 'application/vnd.rar',
        _ => 'application/octet-stream',
      };

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

class SharedImportException extends FileServiceException {
  const SharedImportException(
    super.message, {
    this.code = 'shared_import_failed',
    this.sourceName,
  });

  final String code;
  final String? sourceName;

  bool get isPasswordError => code == 'archive_password';
}

class ExportCancelledException extends FileServiceException {
  const ExportCancelledException() : super('已取消导出');
}

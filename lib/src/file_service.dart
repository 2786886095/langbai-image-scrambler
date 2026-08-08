import 'dart:io';
import 'package:cross_file/cross_file.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as path;

import 'app_settings.dart';
import 'models.dart';

class FileService {
  static const _channel = MethodChannel('com.langbai.imagescrambler/saf');
  static const _extensions = [
    'png',
    'jpg',
    'jpeg',
    'webp',
    'bmp',
    'tif',
    'tiff',
  ];

  Future<ImportBatch?> pickImages() async {
    final result = await FilePicker.platform.pickFiles(
      allowMultiple: true,
      type: FileType.custom,
      allowedExtensions: _extensions,
      dialogTitle: '选择图片',
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
    return ImportBatch(tasks: tasks, isFolder: false, rootName: '');
  }

  Future<ImportBatch?> pickFolder() async {
    if (Platform.isAndroid) return _pickAndroidFolder();
    final selected = await FilePicker.platform.getDirectoryPath(
      dialogTitle: '选择图片文件夹',
    );
    if (selected == null) return null;
    return importFolderPath(selected);
  }

  Future<ImportBatch> importFolderPath(String folderPath) async {
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
      if (entity is! File || !isSupportedImageName(entity.path)) continue;
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
    return ImportBatch(tasks: tasks, isFolder: true, rootName: rootName);
  }

  Future<ImportBatch?> importDropped(List<XFile> dropped) async {
    if (dropped.isEmpty) return null;
    if (dropped.length == 1 && await Directory(dropped.first.path).exists()) {
      return importFolderPath(dropped.first.path);
    }
    final tasks = <ImageTask>[];
    var index = 0;
    for (final item in dropped) {
      final file = File(item.path);
      if (!await file.exists() || !isSupportedImageName(item.path)) continue;
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
        : ImportBatch(tasks: tasks, isFolder: false, rootName: '');
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
        : _batchFolderName(mode);

    if (Platform.isAndroid) {
      if (single && settings.askExportEveryTime) {
        return const ExportTarget(rootFolderName: '', singleFile: true);
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
      return ExportTarget(
        treeUri: treeUri,
        rootFolderName: single ? '' : rootFolderName,
        singleFile: single,
      );
    }

    if (single) {
      final suggestedName = outputFileName(batch.tasks.first, mode);
      if (!settings.askExportEveryTime && settings.defaultExportPath != null) {
        return ExportTarget(
          path: path.join(settings.defaultExportPath!, suggestedName),
          rootFolderName: '',
          singleFile: true,
        );
      }
      var selected = await FilePicker.platform.saveFile(
        dialogTitle: '导出图片',
        fileName: suggestedName,
        type: FileType.custom,
        allowedExtensions: const ['png'],
      );
      if (selected == null) return null;
      if (!selected.toLowerCase().endsWith('.png')) selected += '.png';
      return ExportTarget(path: selected, rootFolderName: '', singleFile: true);
    }

    var selectedDirectory = settings.askExportEveryTime
        ? null
        : settings.defaultExportPath;
    selectedDirectory ??= await FilePicker.platform.getDirectoryPath(
      dialogTitle: '选择导出位置',
    );
    if (selectedDirectory == null) return null;
    return ExportTarget(
      path: selectedDirectory,
      rootFolderName: rootFolderName,
      singleFile: false,
    );
  }

  Future<String> saveOutput({
    required Uint8List bytes,
    required ImageTask task,
    required ProcessMode mode,
    required ExportTarget target,
  }) async {
    final fileName = outputFileName(task, mode);
    if (!Platform.isAndroid) {
      final outputPath = target.singleFile
          ? target.path!
          : path.join(
              target.path!,
              target.rootFolderName,
              task.relativeDirectory,
              fileName,
            );
      final file = File(outputPath);
      await file.parent.create(recursive: true);
      await file.writeAsBytes(bytes, flush: true);
      return file.path;
    }

    final temporaryDirectory = Directory.systemTemp;
    final temporaryFile = File(
      path.join(
        temporaryDirectory.path,
        'langbai-output-${DateTime.now().microsecondsSinceEpoch}.png',
      ),
    );
    await temporaryFile.writeAsBytes(bytes, flush: true);
    if (target.singleFile && target.treeUri == null) {
      final uri = await _channel.invokeMethod<String>('saveDocument', {
        'sourcePath': temporaryFile.path,
        'suggestedName': fileName,
      });
      if (uri == null) throw const ExportCancelledException();
      return uri;
    }
    final relativeFolder = [
      if (target.rootFolderName.isNotEmpty) target.rootFolderName,
      if (task.relativeDirectory.isNotEmpty) task.relativeDirectory,
    ].join('/');
    final uri = await _channel.invokeMethod<String>('writeFileToTree', {
      'treeUri': target.treeUri,
      'relativeFolder': relativeFolder,
      'fileName': fileName,
      'sourcePath': temporaryFile.path,
    });
    if (uri == null) throw const FileServiceException('写入 Android 文件夹失败');
    return uri;
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

  String outputFileName(ImageTask task, ProcessMode mode) {
    var base = basenameWithoutExtension(task.originalName);
    if (mode == ProcessMode.restore) {
      base = base.replaceFirst(RegExp(r'[_-](混淆|混淆圖|scrambled)$'), '');
      return '${sanitizeFileName(base)}_还原.png';
    }
    return '${sanitizeFileName(base)}_混淆.png';
  }

  String _batchFolderName(ProcessMode mode) {
    final now = DateTime.now();
    String two(int value) => value.toString().padLeft(2, '0');
    final stamp =
        '${now.year}${two(now.month)}${two(now.day)}_'
        '${two(now.hour)}${two(now.minute)}${two(now.second)}';
    return 'Langbai_${mode == ProcessMode.scramble ? '混淆' : '还原'}_$stamp';
  }

  Future<ImportBatch?> _pickAndroidFolder() async {
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
      if (!isSupportedImageName(name)) continue;
      tasks.add(
        ImageTask(
          id: '${DateTime.now().microsecondsSinceEpoch}-$index',
          originalName: name,
          relativeDirectory: item['relativeDirectory'] as String? ?? '',
          sourceRootName: tree.name,
          sourceUri: item['uri'] as String?,
          sizeBytes: (item['size'] as num?)?.toInt() ?? 0,
        ),
      );
    }
    return ImportBatch(tasks: tasks, isFolder: true, rootName: tree.name);
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

class _AndroidTree {
  const _AndroidTree(this.uri, this.name);
  final String uri;
  final String name;
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

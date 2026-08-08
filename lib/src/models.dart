import 'dart:io';

enum ProcessMode { scramble, restore }

enum ScrambleAlgorithm {
  auto,
  blockShuffle,
  rowShift,
  columnShift,
  pixelPermutation,
  channelDisturbance,
  composite,
  cherryTomato,
}

extension ScrambleAlgorithmX on ScrambleAlgorithm {
  String get id => switch (this) {
    ScrambleAlgorithm.auto => 'auto',
    ScrambleAlgorithm.blockShuffle => 'block_shuffle',
    ScrambleAlgorithm.rowShift => 'row_shift',
    ScrambleAlgorithm.columnShift => 'column_shift',
    ScrambleAlgorithm.pixelPermutation => 'pixel_permutation',
    ScrambleAlgorithm.channelDisturbance => 'channel_disturbance',
    ScrambleAlgorithm.composite => 'composite',
    ScrambleAlgorithm.cherryTomato => 'cherry_tomato_gilbert',
  };

  bool get isAutomatic => this == ScrambleAlgorithm.auto;
  bool get isCompatibility => this == ScrambleAlgorithm.cherryTomato;
  bool get needsSeed => !isAutomatic && !isCompatibility;

  static ScrambleAlgorithm fromId(String value) =>
      ScrambleAlgorithm.values.firstWhere(
        (item) => item.id == value,
        orElse: () => ScrambleAlgorithm.auto,
      );
}

enum TaskStatus { queued, processing, completed, failed }

class ImageTask {
  ImageTask({
    required this.id,
    required this.originalName,
    required this.relativeDirectory,
    required this.sourceRootName,
    this.inputPath,
    this.sourceUri,
    this.sizeBytes = 0,
  });

  final String id;
  final String originalName;
  final String relativeDirectory;
  final String sourceRootName;
  final String? inputPath;
  final String? sourceUri;
  final int sizeBytes;

  TaskStatus status = TaskStatus.queued;
  String? outputLocation;
  String? error;
  String? detectedAlgorithmId;

  bool get isUriBacked => sourceUri != null;
  String get extension => originalName.contains('.')
      ? originalName.split('.').last.toLowerCase()
      : '';

  ImageTask copyForRetry() => ImageTask(
    id: id,
    originalName: originalName,
    relativeDirectory: relativeDirectory,
    sourceRootName: sourceRootName,
    inputPath: inputPath,
    sourceUri: sourceUri,
    sizeBytes: sizeBytes,
  );
}

class ImportBatch {
  const ImportBatch({
    required this.tasks,
    required this.isFolder,
    required this.rootName,
  });

  final List<ImageTask> tasks;
  final bool isFolder;
  final String rootName;
}

class ProcessedImage {
  const ProcessedImage({
    required this.bytes,
    required this.algorithm,
    required this.verified,
  });

  final List<int> bytes;
  final ScrambleAlgorithm algorithm;
  final bool verified;
}

class ExportTarget {
  const ExportTarget({
    this.path,
    this.treeUri,
    required this.rootFolderName,
    required this.singleFile,
  });

  final String? path;
  final String? treeUri;
  final String rootFolderName;
  final bool singleFile;

  bool get isAndroidTree => treeUri != null;
}

bool isSupportedImageName(String name) {
  final extension = name.toLowerCase().split('.').last;
  return const {
    'png',
    'jpg',
    'jpeg',
    'webp',
    'bmp',
    'tif',
    'tiff',
  }.contains(extension);
}

String basenameWithoutExtension(String name) {
  final index = name.lastIndexOf('.');
  return index <= 0 ? name : name.substring(0, index);
}

String sanitizeFileName(String input) => input.replaceAll(
  RegExp(Platform.isWindows ? r'[<>:"/\\|?*]' : r'[/]'),
  '_',
);

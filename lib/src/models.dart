import 'dart:io';

enum ProcessMode { scramble, restore }

enum WorkspaceType { image, text, mixed }

enum CompressionArchiveFormat { zip, sevenZip }

extension CompressionArchiveFormatX on CompressionArchiveFormat {
  String get extension => this == CompressionArchiveFormat.zip ? 'zip' : '7z';
}

enum CompressionGrouping { perFolder, perFile, combined }

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
    this.sourceRootId = '',
    this.inputPath,
    this.sourceUri,
    this.sizeBytes = 0,
    this.workspaceType = WorkspaceType.image,
  });

  final String id;
  final String originalName;
  final String relativeDirectory;
  final String sourceRootName;
  final String sourceRootId;
  final String? inputPath;
  final String? sourceUri;
  final int sizeBytes;
  final WorkspaceType workspaceType;

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
    sourceRootId: sourceRootId,
    inputPath: inputPath,
    sourceUri: sourceUri,
    sizeBytes: sizeBytes,
    workspaceType: workspaceType,
  );
}

class ImportBatch {
  const ImportBatch({
    required this.tasks,
    required this.isFolder,
    required this.rootName,
    this.workspaceType = WorkspaceType.image,
    this.temporaryRoots = const [],
    this.skippedCount = 0,
  });

  final List<ImageTask> tasks;
  final bool isFolder;
  final String rootName;
  final WorkspaceType workspaceType;
  final List<String> temporaryRoots;
  final int skippedCount;

  bool get containsImages =>
      tasks.any((task) => task.workspaceType == WorkspaceType.image);
  bool get containsText =>
      tasks.any((task) => task.workspaceType == WorkspaceType.text);
  bool get isMixed => containsImages && containsText;
}

class SharedImportItem {
  const SharedImportItem({
    required this.name,
    this.uri,
    this.sourcePath,
    this.mimeType = 'application/octet-stream',
    this.sizeBytes = 0,
    this.isDirectory = false,
  });

  factory SharedImportItem.fromMap(Map<String, dynamic> map) =>
      SharedImportItem(
        name: map['name'] as String? ?? '分享文件',
        uri: map['uri'] as String?,
        sourcePath: map['sourcePath'] as String?,
        mimeType: map['mimeType'] as String? ?? 'application/octet-stream',
        sizeBytes: (map['size'] as num?)?.toInt() ?? 0,
        isDirectory: map['isDirectory'] as bool? ?? false,
      );

  final String name;
  final String? uri;
  final String? sourcePath;
  final String mimeType;
  final int sizeBytes;
  final bool isDirectory;

  String get extension =>
      name.contains('.') ? name.split('.').last.toLowerCase() : '';
  bool get isArchive => const {'zip', '7z', 'rar'}.contains(extension);
  bool get isImage => isSupportedImageName(name);
  bool get isText => isSupportedTextName(name);
}

class SharedImportRequest {
  const SharedImportRequest({required this.id, required this.items});

  factory SharedImportRequest.fromMap(Map<String, dynamic> map) =>
      SharedImportRequest(
        id:
            map['id'] as String? ??
            DateTime.now().microsecondsSinceEpoch.toString(),
        items: (map['items'] as List<dynamic>? ?? const [])
            .whereType<Map>()
            .map(
              (item) =>
                  SharedImportItem.fromMap(Map<String, dynamic>.from(item)),
            )
            .toList(growable: false),
      );

  final String id;
  final List<SharedImportItem> items;

  List<SharedImportItem> get archives =>
      items.where((item) => item.isArchive).toList(growable: false);
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
    this.displayLabel = '',
    this.createdDirectories = const [],
    this.taskRootPaths = const {},
    this.taskRootFolderNames = const {},
  });

  final String? path;
  final String? treeUri;
  final String rootFolderName;
  final bool singleFile;
  final String displayLabel;
  final List<String> createdDirectories;
  final Map<String, String> taskRootPaths;
  final Map<String, String> taskRootFolderNames;

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

bool isSupportedTextName(String name) => name.toLowerCase().endsWith('.txt');

bool isSupportedArchiveName(String name) {
  final extension = name.toLowerCase().split('.').last;
  return const {'zip', '7z', 'rar'}.contains(extension);
}

String basenameWithoutExtension(String name) {
  final index = name.lastIndexOf('.');
  return index <= 0 ? name : name.substring(0, index);
}

String sanitizeFileName(String input) => input.replaceAll(
  RegExp(Platform.isWindows ? r'[<>:"/\\|?*]' : r'[/]'),
  '_',
);

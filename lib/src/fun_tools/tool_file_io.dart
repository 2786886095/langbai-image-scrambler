import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as path;

class PickedToolFile {
  const PickedToolFile({required this.name, required this.bytes});

  final String name;
  final Uint8List bytes;

  String get extension {
    final value = path.extension(name).replaceFirst('.', '').toLowerCase();
    return value.isEmpty ? 'bin' : value;
  }
}

class ToolFileIo {
  const ToolFileIo();

  static const _channel = MethodChannel('com.langbai.imagescrambler/saf');

  Future<PickedToolFile?> pickImage() => _pick(FileType.custom, const [
    'png',
    'jpg',
    'jpeg',
    'webp',
    'bmp',
    'tif',
    'tiff',
  ]);

  Future<PickedToolFile?> pickAny() => _pick(FileType.any, null);

  Future<PickedToolFile?> _pick(FileType type, List<String>? extensions) async {
    final result = await FilePicker.platform.pickFiles(
      type: type,
      allowedExtensions: extensions,
      allowMultiple: false,
      withData: true,
    );
    final file = result?.files.singleOrNull;
    if (file == null) return null;
    final bytes =
        file.bytes ??
        (file.path == null ? null : await File(file.path!).readAsBytes());
    if (bytes == null) throw const ToolFileIoException('所选文件读取失败');
    return PickedToolFile(name: file.name, bytes: bytes);
  }

  Future<String?> saveBytes({
    required Uint8List bytes,
    required String suggestedName,
    required String mimeType,
  }) async {
    if (!kIsWeb && Platform.isAndroid) {
      final temporary = File(
        path.join(
          Directory.systemTemp.path,
          'langbai-tool-${DateTime.now().microsecondsSinceEpoch}-${path.basename(suggestedName)}',
        ),
      );
      await temporary.writeAsBytes(bytes, flush: true);
      try {
        final saved = await _channel
            .invokeMapMethod<String, dynamic>('saveDocument', {
              'sourcePath': temporary.path,
              'suggestedName': suggestedName,
              'mimeType': mimeType,
            });
        return saved?['uri'];
      } finally {
        if (await temporary.exists()) await temporary.delete();
      }
    }

    final output = await FilePicker.platform.saveFile(
      dialogTitle: '选择导出位置',
      fileName: suggestedName,
      type: FileType.custom,
      allowedExtensions: [path.extension(suggestedName).replaceFirst('.', '')],
    );
    if (output == null) return null;
    await File(output).writeAsBytes(bytes, flush: true);
    return output;
  }

  Future<String?> saveSource({
    required String sourcePath,
    required String suggestedName,
    required String mimeType,
  }) async {
    if (!kIsWeb && Platform.isAndroid) {
      final saved = await _channel.invokeMapMethod<String, dynamic>(
        'saveDocument',
        {
          'sourcePath': sourcePath,
          'suggestedName': suggestedName,
          'mimeType': mimeType,
        },
      );
      return saved?['uri'];
    }
    final output = await FilePicker.platform.saveFile(
      dialogTitle: '选择导出位置',
      fileName: suggestedName,
      type: FileType.custom,
      allowedExtensions: [path.extension(suggestedName).replaceFirst('.', '')],
    );
    if (output == null) return null;
    await File(sourcePath).copy(output);
    return output;
  }

  Future<void> openSavedLocation(String location) async {
    if (!kIsWeb && Platform.isAndroid) {
      await _channel.invokeMethod<void>('openOutputLocation', {
        'uri': location,
        'isDirectory': false,
      });
      return;
    }
    if (!kIsWeb && Platform.isWindows) {
      await Process.start('explorer.exe', [
        '/select,',
        path.normalize(location),
      ], mode: ProcessStartMode.detached);
    }
  }
}

class ToolFileIoException implements Exception {
  const ToolFileIoException(this.message);

  final String message;

  @override
  String toString() => message;
}

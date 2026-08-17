import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as path;

import 'video_models.dart';

class FfmpegResult {
  const FfmpegResult({required this.exitCode, required this.output});
  final int exitCode;
  final String output;
}

class VideoFfmpeg {
  const VideoFfmpeg();

  static const _channel = MethodChannel('com.langbai.imagescrambler/saf');

  Future<FfmpegResult> run(
    List<String> arguments, {
    bool allowFailure = false,
  }) async {
    if (!kIsWeb && Platform.isAndroid) {
      final result = await _channel.invokeMapMethod<String, dynamic>(
        'runFfmpeg',
        {'arguments': arguments},
      );
      final exitCode = result?['exitCode'] as int? ?? -1;
      final output = result?['output'] as String? ?? '';
      if (!allowFailure && exitCode != 0) {
        throw VideoProcessException(_friendlyError(output));
      }
      return FfmpegResult(exitCode: exitCode, output: output);
    }
    if (!Platform.isWindows) {
      throw const VideoProcessException('当前平台尚未启用视频处理引擎');
    }
    final binary = await _ensureWindowsBinary();
    final process = await Process.start(
      binary,
      arguments,
      runInShell: false,
      mode: ProcessStartMode.normal,
    );
    final outputBuffer = StringBuffer();
    final stdoutFuture = process.stdout
        .transform(const SystemEncoding().decoder)
        .forEach(outputBuffer.write);
    final stderrFuture = process.stderr
        .transform(const SystemEncoding().decoder)
        .forEach(outputBuffer.write);
    final exitCode = await process.exitCode;
    await Future.wait([stdoutFuture, stderrFuture]);
    final output = outputBuffer.toString();
    if (!allowFailure && exitCode != 0) {
      throw VideoProcessException(_friendlyError(output));
    }
    return FfmpegResult(exitCode: exitCode, output: output);
  }

  Future<String> _ensureWindowsBinary() async {
    final cacheDirectory = Directory(
      path.join(
        Platform.environment['LOCALAPPDATA'] ?? Directory.systemTemp.path,
        'Langbai Image Scrambler',
        'video-engine-v9',
      ),
    );
    final binary = File(path.join(cacheDirectory.path, 'ffmpeg.exe'));
    if (await binary.exists() && await binary.length() > 20 * 1024 * 1024) {
      return binary.path;
    }
    await cacheDirectory.create(recursive: true);
    final archive = _assetPath('ffmpeg.7z');
    final extractor = _assetPath('7z.exe');
    if (!File(archive).existsSync() || !File(extractor).existsSync()) {
      throw const VideoProcessException('Windows 视频引擎资源缺失，请重新安装软件');
    }
    final result = await Process.run(extractor, [
      'e',
      archive,
      r'ffmpeg-9.0.1-essentials_build\bin\ffmpeg.exe',
      '-o${cacheDirectory.path}',
      '-y',
    ], runInShell: false);
    if (result.exitCode != 0 ||
        !await binary.exists() ||
        await binary.length() < 20 * 1024 * 1024) {
      throw const VideoProcessException('Windows 视频引擎初始化失败');
    }
    return binary.path;
  }

  String _assetPath(String name) {
    if (name.startsWith('ffmpeg')) {
      final windowsOnlyAsset = path.join(
        path.dirname(Platform.resolvedExecutable),
        'data',
        'video',
        name,
      );
      if (File(windowsOnlyAsset).existsSync()) return windowsOnlyAsset;
    }
    final release = path.join(
      path.dirname(Platform.resolvedExecutable),
      'data',
      'flutter_assets',
      'assets',
      'bin',
      'windows',
      name,
    );
    if (File(release).existsSync()) return release;
    return path.join(Directory.current.path, 'assets', 'bin', 'windows', name);
  }

  String _friendlyError(String raw) {
    final lines = raw
        .split(RegExp(r'[\r\n]+'))
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .toList();
    final useful = lines.reversed.firstWhere(
      (line) =>
          line.toLowerCase().contains('error') ||
          line.toLowerCase().contains('invalid') ||
          line.toLowerCase().contains('failed'),
      orElse: () => lines.isEmpty ? '视频处理失败' : lines.last,
    );
    return '视频处理失败：$useful';
  }
}

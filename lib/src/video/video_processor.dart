import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'dart:math';
import 'dart:typed_data';
import 'package:image/image.dart' as image;
import 'package:path/path.dart' as path;

import '../algorithms.dart';
import '../models.dart';
import 'video_container.dart';
import 'video_ffmpeg.dart';
import 'video_models.dart';

typedef VideoProgressCallback = void Function(double progress, String stage);

int computeVideoWorkerCount({
  required VideoPerformanceMode performanceMode,
  required int width,
  required int height,
  required bool android,
  int? logicalProcessors,
}) {
  final processors = logicalProcessors ?? Platform.numberOfProcessors;
  final cpuLimit = performanceMode == VideoPerformanceMode.fullPower
      ? processors
      : (android ? min(2, processors) : min(4, processors));
  final memoryBudget = performanceMode == VideoPerformanceMode.fullPower
      ? (android ? 512 : 2048) * 1024 * 1024
      : (android ? 256 : 768) * 1024 * 1024;
  final estimatedBytesPerWorker = max(width * height * 16, 1);
  final memoryLimit = max(1, memoryBudget ~/ estimatedBytesPerWorker);
  return min(max(1, cpuLimit), memoryLimit);
}

class VideoProcessor {
  VideoProcessor({VideoFfmpeg? ffmpeg, VideoContainer? container})
    : _ffmpeg = ffmpeg ?? const VideoFfmpeg(),
      _container = container ?? VideoContainer();

  final VideoFfmpeg _ffmpeg;
  final VideoContainer _container;
  final Random _random = Random.secure();

  Future<VideoInspection> inspect(String inputPath) async {
    final manifest = await _container.inspect(inputPath);
    if (manifest != null) {
      return VideoInspection(
        hasExactPayload: true,
        algorithm: manifest.algorithm,
        audioMode: manifest.audioMode,
        seed: manifest.seed,
        originalName: manifest.originalName,
        passwordProtected: manifest.passwordProtected,
      );
    }
    final probe = await _ffmpeg.run([
      '-hide_banner',
      '-i',
      inputPath,
    ], allowFailure: true);
    final marker = RegExp(
      r'LANGBAI_VIDEO_V1;algorithm=([a-z_]+);seed=(\d+);audio=([a-z]+)',
      caseSensitive: false,
    ).firstMatch(probe.output);
    return VideoInspection(
      hasExactPayload: false,
      algorithm: VideoAlgorithmX.fromId(marker?.group(1)),
      audioMode: VideoAudioModeX.fromId(marker?.group(3)),
      seed: int.tryParse(marker?.group(2) ?? '') ?? 0,
    );
  }

  Future<VideoProcessResult> scramble({
    required String inputPath,
    required String outputPath,
    required VideoAlgorithm algorithm,
    required VideoAudioMode audioMode,
    VideoPerformanceMode performanceMode = VideoPerformanceMode.normal,
    String? password,
    VideoProgressCallback? onProgress,
  }) async {
    if (algorithm == VideoAlgorithm.auto) {
      throw const VideoProcessException('请选择视频混淆算法');
    }
    final seed = _random.nextInt(0x7ffffffe) + 1;
    final temporaryRoot = await Directory.systemTemp.createTemp(
      'langbai-video-',
    );
    try {
      final playable = path.join(temporaryRoot.path, 'playable.mp4');
      await _transformVideo(
        inputPath: inputPath,
        outputPath: playable,
        algorithm: algorithm,
        audioMode: audioMode,
        seed: seed,
        reverse: false,
        performanceMode: performanceMode,
        onProgress: onProgress,
      );
      onProgress?.call(.9, '正在写入精确还原数据');
      await _container.appendOriginal(
        playablePath: playable,
        originalPath: inputPath,
        outputPath: outputPath,
        algorithm: algorithm,
        audioMode: audioMode,
        seed: seed,
        password: password,
        performanceMode: performanceMode,
      );
      onProgress?.call(1, '视频混淆完成');
      return VideoProcessResult(
        path: outputPath,
        outputName: path.basename(inputPath),
        exact: true,
        algorithm: algorithm,
      );
    } finally {
      if (await temporaryRoot.exists()) {
        await temporaryRoot.delete(recursive: true);
      }
    }
  }

  Future<VideoProcessResult> restore({
    required String inputPath,
    required String outputPath,
    VideoAlgorithm requestedAlgorithm = VideoAlgorithm.auto,
    VideoAudioMode requestedAudioMode = VideoAudioMode.keep,
    int? manualSeed,
    String? password,
    VideoPerformanceMode performanceMode = VideoPerformanceMode.normal,
    VideoProgressCallback? onProgress,
  }) async {
    final inspection = await inspect(inputPath);
    if (inspection.hasExactPayload) {
      onProgress?.call(.1, '检测到无损还原数据');
      final manifest = await _container.extractOriginal(
        inputPath: inputPath,
        outputPath: outputPath,
        password: password,
        performanceMode: performanceMode,
      );
      onProgress?.call(1, 'SHA-256 校验通过');
      return VideoProcessResult(
        path: outputPath,
        outputName: manifest.originalName,
        exact: true,
        algorithm: manifest.algorithm,
      );
    }
    final algorithm = inspection.algorithm == VideoAlgorithm.auto
        ? requestedAlgorithm
        : inspection.algorithm;
    final seed = inspection.seed == 0 ? manualSeed : inspection.seed;
    if (algorithm == VideoAlgorithm.auto || seed == null || seed <= 0) {
      throw const VideoProcessException('平台转码后未识别到算法参数，请手动选择算法并输入随机种子');
    }
    await _transformVideo(
      inputPath: inputPath,
      outputPath: outputPath,
      algorithm: algorithm,
      audioMode: inspection.audioMode == VideoAudioMode.keep
          ? requestedAudioMode
          : inspection.audioMode,
      seed: seed,
      reverse: true,
      performanceMode: performanceMode,
      onProgress: onProgress,
    );
    return VideoProcessResult(
      path: outputPath,
      outputName: path.basename(inputPath),
      exact: false,
      algorithm: algorithm,
    );
  }

  Future<void> _transformVideo({
    required String inputPath,
    required String outputPath,
    required VideoAlgorithm algorithm,
    required VideoAudioMode audioMode,
    required int seed,
    required bool reverse,
    required VideoPerformanceMode performanceMode,
    VideoProgressCallback? onProgress,
  }) async {
    final work = await Directory.systemTemp.createTemp('langbai-frames-');
    final frames = Directory(path.join(work.path, 'frames'));
    await frames.create();
    try {
      onProgress?.call(.03, '正在读取视频信息');
      final info = await _ffmpeg.run([
        '-hide_banner',
        '-i',
        inputPath,
      ], allowFailure: true);
      final fps = _fpsFromProbe(info.output);
      onProgress?.call(.08, '正在提取视频帧');
      await _ffmpeg.run([
        '-hide_banner',
        '-nostdin',
        '-y',
        '-i',
        inputPath,
        '-map',
        '0:v:0',
        '-fps_mode',
        'passthrough',
        '-threads',
        performanceMode == VideoPerformanceMode.fullPower
            ? '0'
            : (Platform.isAndroid ? '2' : '4'),
        '-compression_level',
        performanceMode == VideoPerformanceMode.fullPower ? '1' : '3',
        path.join(frames.path, 'frame-%08d.png'),
      ]);
      final files = await frames
          .list()
          .where((entity) => entity is File && entity.path.endsWith('.png'))
          .cast<File>()
          .toList();
      files.sort((a, b) => a.path.compareTo(b.path));
      if (files.isEmpty) throw const VideoProcessException('视频中没有可处理的画面');
      final dimensions = await _readPngDimensions(files.first);
      final workerCount = computeVideoWorkerCount(
        performanceMode: performanceMode,
        width: dimensions.$1,
        height: dimensions.$2,
        android: Platform.isAndroid,
      ).clamp(1, files.length);
      await _transformFrames(
        files: files,
        workerCount: workerCount,
        algorithm: algorithm,
        seed: seed,
        reverse: reverse,
        pngLevel: performanceMode == VideoPerformanceMode.fullPower ? 1 : 3,
        onProgress: onProgress,
      );
      onProgress?.call(.8, '正在合成可播放视频');
      final marker =
          'LANGBAI_VIDEO_V1;algorithm=${algorithm.id};seed=$seed;audio=${audioMode.id}';
      final arguments = <String>[
        '-hide_banner',
        '-nostdin',
        '-y',
        '-framerate',
        fps.toStringAsFixed(6),
        '-i',
        path.join(frames.path, 'frame-%08d.png'),
        '-i',
        inputPath,
        '-map',
        '0:v:0',
        '-map',
        '1:a?',
        '-c:v',
        'libx264',
        '-preset',
        performanceMode == VideoPerformanceMode.fullPower
            ? 'superfast'
            : 'veryfast',
        '-crf',
        '18',
        '-threads',
        performanceMode == VideoPerformanceMode.fullPower
            ? '0'
            : (Platform.isAndroid ? '2' : '4'),
        '-pix_fmt',
        'yuv420p',
        '-vf',
        'pad=ceil(iw/2)*2:ceil(ih/2)*2',
        if (audioMode == VideoAudioMode.reversibleScramble) ...[
          '-af',
          'areverse',
        ],
        '-c:a',
        'aac',
        '-b:a',
        '192k',
        '-metadata',
        'comment=$marker',
        '-movflags',
        '+faststart',
        outputPath,
      ];
      await _ffmpeg.run(arguments);
      if (!await File(outputPath).exists() ||
          await File(outputPath).length() == 0) {
        throw const VideoProcessException('视频合成结果为空');
      }
      onProgress?.call(.88, '可播放视频已生成');
    } finally {
      if (await work.exists()) await work.delete(recursive: true);
    }
  }

  Future<(int, int)> _readPngDimensions(File file) async {
    final handle = await file.open();
    try {
      final header = Uint8List.fromList(await handle.read(24));
      if (header.length >= 24) {
        final data = ByteData.sublistView(header);
        final width = data.getUint32(16, Endian.big);
        final height = data.getUint32(20, Endian.big);
        if (width > 0 && height > 0) return (width, height);
      }
      return (1920, 1080);
    } finally {
      await handle.close();
    }
  }

  Future<void> _transformFrames({
    required List<File> files,
    required int workerCount,
    required VideoAlgorithm algorithm,
    required int seed,
    required bool reverse,
    required int pngLevel,
    VideoProgressCallback? onProgress,
  }) async {
    final receivePort = ReceivePort();
    final isolates = <Isolate>[];
    final completer = Completer<void>();
    var completed = 0;
    var finishedWorkers = 0;
    late final StreamSubscription<dynamic> subscription;
    subscription = receivePort.listen((message) {
      if (message == 'progress') {
        completed++;
        onProgress?.call(
          .12 + .65 * completed / files.length,
          '正在多核处理视频帧 $completed/${files.length}',
        );
      } else if (message == 'done') {
        finishedWorkers++;
        if (finishedWorkers == workerCount && !completer.isCompleted) {
          completer.complete();
        }
      } else if (message is Map && message['error'] != null) {
        if (!completer.isCompleted) {
          completer.completeError(VideoProcessException('${message['error']}'));
        }
      }
    });
    try {
      for (var worker = 0; worker < workerCount; worker++) {
        final workerPaths = <String>[
          for (var index = worker; index < files.length; index += workerCount)
            files[index].path,
        ];
        isolates.add(
          await Isolate.spawn(_videoFrameWorker, {
            'sendPort': receivePort.sendPort,
            'paths': workerPaths,
            'algorithm': algorithm.id,
            'seed': seed,
            'reverse': reverse,
            'pngLevel': pngLevel,
          }),
        );
      }
      await completer.future;
    } finally {
      await subscription.cancel();
      receivePort.close();
      for (final isolate in isolates) {
        isolate.kill(priority: Isolate.immediate);
      }
    }
  }

  double _fpsFromProbe(String output) {
    final streamLine = output
        .split(RegExp(r'[\r\n]+'))
        .firstWhere((line) => line.contains('Video:'), orElse: () => '');
    final match = RegExp(r'([0-9]+(?:\.[0-9]+)?)\s*fps').firstMatch(streamLine);
    return (double.tryParse(match?.group(1) ?? '') ?? 30).clamp(1, 120);
  }
}

void _videoFrameWorker(Map<String, dynamic> request) {
  final sendPort = request['sendPort'] as SendPort;
  try {
    final paths = (request['paths'] as List).cast<String>();
    final algorithm = VideoAlgorithmX.fromId(request['algorithm'] as String?);
    final seed = request['seed'] as int;
    final reverse = request['reverse'] as bool;
    final pngLevel = request['pngLevel'] as int;
    for (final framePath in paths) {
      _transformVideoFrame(framePath, algorithm, seed, reverse, pngLevel);
      sendPort.send('progress');
    }
    sendPort.send('done');
  } catch (error) {
    sendPort.send({'error': '视频帧处理失败：$error'});
  }
}

void _transformVideoFrame(
  String framePath,
  VideoAlgorithm algorithm,
  int seed,
  bool reverse,
  int pngLevel,
) {
  final file = File(framePath);
  final decoded = image.decodePng(file.readAsBytesSync());
  if (decoded == null) throw const VideoProcessException('视频帧读取失败');
  final rgba = decoded.getBytes(order: image.ChannelOrder.rgba);
  final raster = ImageRaster(decoded.width, decoded.height, rgba);
  final transformed = algorithm == VideoAlgorithm.rowColumnShift
      ? ScrambleEngine.transformRowColumn(raster, seed, reverse: reverse)
      : ScrambleEngine.transform(
          raster,
          algorithm == VideoAlgorithm.gilbert
              ? ScrambleAlgorithm.cherryTomato
              : ScrambleAlgorithm.blockShuffle,
          seed,
          reverse: reverse,
        );
  final output = image.Image.fromBytes(
    width: transformed.width,
    height: transformed.height,
    bytes: transformed.rgba.buffer,
    numChannels: 4,
    order: image.ChannelOrder.rgba,
  );
  file.writeAsBytesSync(image.encodePng(output, level: pngLevel), flush: false);
}

import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:langbai_image_scrambler/src/video/video_models.dart';
import 'package:langbai_image_scrambler/src/video/video_processor.dart';
import 'package:path/path.dart' as path;

const _runVideoEngine = bool.fromEnvironment('RUN_VIDEO_ENGINE');

void main() {
  test(
    'Windows 视频输出可播放且精确还原与源文件一致',
    () async {
      final temporary = await Directory.systemTemp.createTemp(
        'langbai-video-engine-test-',
      );
      addTearDown(() => temporary.delete(recursive: true));
      final ffmpeg = await _extractTestFfmpeg(temporary);
      final source = path.join(temporary.path, '像素测试.mp4');
      final generated = await Process.run(ffmpeg, [
        '-hide_banner',
        '-loglevel',
        'error',
        '-f',
        'lavfi',
        '-i',
        'testsrc2=size=64x48:rate=5:duration=1',
        '-f',
        'lavfi',
        '-i',
        'sine=frequency=880:duration=1',
        '-c:v',
        'libx264',
        '-pix_fmt',
        'yuv420p',
        '-c:a',
        'aac',
        '-shortest',
        source,
      ]);
      expect(generated.exitCode, 0, reason: generated.stderr.toString());

      final processor = VideoProcessor();
      final scrambled = path.join(temporary.path, '像素测试-输出.mp4');
      await processor.scramble(
        inputPath: source,
        outputPath: scrambled,
        algorithm: VideoAlgorithm.blockShuffle,
        audioMode: VideoAudioMode.reversibleScramble,
        password: '视频测试密码',
        performanceMode: VideoPerformanceMode.fullPower,
      );

      final playable = await Process.run(ffmpeg, [
        '-v',
        'error',
        '-i',
        scrambled,
        '-f',
        'null',
        '-',
      ]);
      expect(playable.exitCode, 0, reason: playable.stderr.toString());
      final inspection = await processor.inspect(scrambled);
      expect(inspection.hasExactPayload, isTrue);
      expect(inspection.algorithm, VideoAlgorithm.blockShuffle);
      expect(inspection.passwordProtected, isTrue);

      final restored = path.join(temporary.path, '像素测试-还原.mp4');
      final result = await processor.restore(
        inputPath: scrambled,
        outputPath: restored,
        requestedAlgorithm: VideoAlgorithm.auto,
        requestedAudioMode: VideoAudioMode.keep,
        password: '视频测试密码',
        performanceMode: VideoPerformanceMode.fullPower,
      );
      expect(result.exact, isTrue);
      expect(
        sha256.convert(await File(restored).readAsBytes()),
        sha256.convert(await File(source).readAsBytes()),
      );
    },
    skip: !_runVideoEngine || !Platform.isWindows,
    timeout: const Timeout(Duration(minutes: 3)),
  );
}

Future<String> _extractTestFfmpeg(Directory target) async {
  final root = Directory.current.path;
  final archive = path.join(root, 'assets', 'bin', 'windows', 'ffmpeg.7z');
  final sevenZip = path.join(root, 'assets', 'bin', 'windows', '7z.exe');
  final result = await Process.run(sevenZip, [
    'e',
    archive,
    r'ffmpeg-9.0.1-essentials_build\bin\ffmpeg.exe',
    '-o${target.path}',
    '-y',
  ]);
  expect(result.exitCode, 0, reason: result.stderr.toString());
  final binary = path.join(target.path, 'ffmpeg.exe');
  expect(File(binary).existsSync(), isTrue);
  return binary;
}

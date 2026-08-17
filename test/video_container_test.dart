import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:langbai_image_scrambler/src/video/video_container.dart';
import 'package:langbai_image_scrambler/src/video/video_models.dart';

void main() {
  for (final password in <String?>[null, '测试密码-123']) {
    test('视频容器可流式精确还原 ${password == null ? '公开模式' : '密码模式'}', () async {
      final directory = await Directory.systemTemp.createTemp(
        'video-container-test-',
      );
      try {
        final playable = File('${directory.path}/playable.mp4');
        final original = File('${directory.path}/原视频.mp4');
        final containerFile = File('${directory.path}/mixed.mp4');
        final restored = File('${directory.path}/restored.mp4');
        await playable.writeAsBytes(List<int>.generate(1024, (i) => i & 255));
        final originalBytes = Uint8List.fromList(
          List<int>.generate(
            VideoContainer.chunkSize + 137,
            (i) => (i * 31) & 255,
          ),
        );
        await original.writeAsBytes(originalBytes);
        final container = VideoContainer();
        await container.appendOriginal(
          playablePath: playable.path,
          originalPath: original.path,
          outputPath: containerFile.path,
          algorithm: VideoAlgorithm.gilbert,
          audioMode: VideoAudioMode.reversibleScramble,
          seed: 12345,
          password: password,
        );
        final inspected = await container.inspect(containerFile.path);
        expect(inspected, isNotNull);
        expect(inspected!.originalName, '原视频.mp4');
        expect(inspected.passwordProtected, password != null);
        await container.extractOriginal(
          inputPath: containerFile.path,
          outputPath: restored.path,
          password: password,
        );
        expect(await restored.readAsBytes(), originalBytes);
      } finally {
        await directory.delete(recursive: true);
      }
    });
  }
}

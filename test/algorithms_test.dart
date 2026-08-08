import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:langbai_image_scrambler/src/algorithms.dart';
import 'package:langbai_image_scrambler/src/models.dart';

void main() {
  group('ScrambleEngine', () {
    final algorithms = ScrambleAlgorithm.values.where(
      (algorithm) => !algorithm.isAutomatic,
    );

    for (final algorithm in algorithms) {
      test('${algorithm.id} round-trips non-square RGBA pixels', () {
        const width = 37;
        const height = 23;
        final source = Uint8List(width * height * 4);
        for (var index = 0; index < source.length; index++) {
          source[index] = (index * 73 + 19) & 0xff;
        }
        final raster = ImageRaster(width, height, source);
        final scrambled = ScrambleEngine.transform(
          raster,
          algorithm,
          19491001,
          reverse: false,
        );
        final restored = ScrambleEngine.transform(
          scrambled,
          algorithm,
          19491001,
          reverse: true,
        );
        expect(restored.width, width);
        expect(restored.height, height);
        expect(restored.rgba, orderedEquals(source));
      });
    }

    test('小番茄算法与参考 Python 实现映射一致', () {
      const width = 4;
      const height = 3;
      final source = Uint8List(width * height * 4);
      for (var pixel = 0; pixel < width * height; pixel++) {
        source[pixel * 4] = pixel;
        source[pixel * 4 + 1] = pixel + 20;
        source[pixel * 4 + 2] = pixel + 40;
        source[pixel * 4 + 3] = 255;
      }
      final scrambled = ScrambleEngine.transform(
        ImageRaster(width, height, source),
        ScrambleAlgorithm.cherryTomato,
        0,
        reverse: false,
      );
      final red = <int>[
        for (var pixel = 0; pixel < width * height; pixel++)
          scrambled.rgba[pixel * 4],
      ];
      // 由 MIT 参考实现 ok8634673/Cherry-tomato-image-obfuscation 计算。
      expect(red, [9, 10, 4, 8, 7, 11, 5, 1, 6, 2, 3, 0]);
    });
  });
}

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as image;
import 'package:langbai_image_scrambler/src/image_processor.dart';
import 'package:langbai_image_scrambler/src/metadata.dart';
import 'package:langbai_image_scrambler/src/models.dart';

void main() {
  late Uint8List originalPng;
  late Uint8List originalRgba;

  setUpAll(() {
    final source = image.Image(width: 29, height: 17, numChannels: 4);
    for (var y = 0; y < source.height; y++) {
      for (var x = 0; x < source.width; x++) {
        source.setPixelRgba(
          x,
          y,
          (x * 17 + y * 3) & 0xff,
          (x * 5 + y * 29) & 0xff,
          (x * 41 + y * 7) & 0xff,
          (x * 11 + y * 13) & 0xff,
        );
      }
    }
    originalRgba = source.getBytes(order: image.ChannelOrder.rgba);
    originalPng = image.encodePng(source);
  });

  test('all algorithms preserve exact decoded pixels through PNG', () async {
    final processor = ImageProcessor();
    for (final algorithm in ScrambleAlgorithm.values.where(
      (algorithm) => !algorithm.isAutomatic,
    )) {
      final scrambled = await processor.scramble(
        inputBytes: originalPng,
        sourceName: 'fixture.png',
        algorithm: algorithm,
      );
      expect(
        PngManifestReader.read(Uint8List.fromList(scrambled.bytes)),
        isNotNull,
      );
      final restored = await processor.restore(
        inputBytes: Uint8List.fromList(scrambled.bytes),
        requestedAlgorithm: ScrambleAlgorithm.auto,
      );
      final decoded = image.decodePng(Uint8List.fromList(restored.bytes));
      expect(decoded, isNotNull);
      expect(
        decoded!.getBytes(order: image.ChannelOrder.rgba),
        orderedEquals(originalRgba),
        reason: algorithm.id,
      );
      expect(restored.verified, isTrue);
      expect(restored.algorithm, algorithm);
    }
  });

  test('password-protected manifest restores only with its password', () async {
    final processor = ImageProcessor();
    final scrambled = await processor.scramble(
      inputBytes: originalPng,
      sourceName: 'protected.png',
      algorithm: ScrambleAlgorithm.composite,
      password: 'Langbai-测试-2026',
    );
    final bytes = Uint8List.fromList(scrambled.bytes);
    expect(processor.inspectProtection(bytes)?.protected, isTrue);
    await expectLater(
      processor.restore(
        inputBytes: bytes,
        requestedAlgorithm: ScrambleAlgorithm.auto,
        password: 'wrong',
      ),
      throwsA(isA<InvalidPasswordException>()),
    );
    final restored = await processor.restore(
      inputBytes: bytes,
      requestedAlgorithm: ScrambleAlgorithm.auto,
      password: 'Langbai-测试-2026',
    );
    final decoded = image.decodePng(Uint8List.fromList(restored.bytes))!;
    expect(
      decoded.getBytes(order: image.ChannelOrder.rgba),
      orderedEquals(originalRgba),
    );
  });

  test('automatic restore reports missing metadata', () async {
    await expectLater(
      ImageProcessor().restore(
        inputBytes: originalPng,
        requestedAlgorithm: ScrambleAlgorithm.auto,
      ),
      throwsA(isA<MetadataMissingException>()),
    );
  });
}

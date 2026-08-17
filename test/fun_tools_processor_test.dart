import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as image;
import 'package:langbai_image_scrambler/src/fun_tools/fun_tools_models.dart';
import 'package:langbai_image_scrambler/src/fun_tools/fun_tools_processor.dart';

void main() {
  test('幻影 v0-v3 可完整提取隐藏文件', () async {
    final inner = image.Image(width: 384, height: 384);
    image.fill(inner, color: image.ColorRgba8(20, 40, 80, 255));
    final cover = image.Image(width: 384, height: 384);
    image.fill(cover, color: image.ColorRgba8(220, 180, 100, 255));
    final innerBytes = image.encodePng(inner);
    final coverBytes = image.encodePng(cover);
    final payload = Uint8List.fromList(
      List<int>.generate(2048, (index) => index & 255),
    );
    const processor = FunToolsProcessor();

    for (final version in CloakVersion.values.take(4)) {
      final encoded = await processor.createCloak(
        innerBytes: innerBytes,
        coverBytes: version.needsCover ? coverBytes : null,
        payloadBytes: payload,
        payloadExtension: 'bin',
        config: CloakConfig(version: version),
      );
      final decoded = await processor.decodeCloak(encoded);
      expect(decoded.version, version);
      expect(decoded.extension, 'bin');
      expect(decoded.bytes, payload);
    }
  });

  test('幻影 v4-v5 只生成视觉 PNG', () async {
    final inner = image.encodePng(image.Image(width: 64, height: 64));
    final cover = image.encodePng(image.Image(width: 64, height: 64));
    const processor = FunToolsProcessor();
    for (final version in [CloakVersion.v4, CloakVersion.v5]) {
      final encoded = await processor.createCloak(
        innerBytes: inner,
        coverBytes: cover,
        config: CloakConfig(version: version),
      );
      expect(image.decodePng(encoded), isNotNull);
      expect(
        () => processor.decodeCloak(encoded),
        throwsA(isA<FunToolException>()),
      );
    }
  });
}

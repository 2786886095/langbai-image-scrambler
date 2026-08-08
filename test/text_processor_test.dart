import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:langbai_image_scrambler/src/text_processor.dart';

void main() {
  test(
    'Base64 round-trip preserves UTF-8 novel bytes and line endings',
    () async {
      final source = Uint8List.fromList(
        utf8.encode('\ufeff第一章\r\n雨落在旧城。\n第二行保留不同换行。\r\n'),
      );
      const processor = TextProcessor();
      final encoded = await processor.encode(source);
      expect(ascii.decode(encoded), base64Encode(source));
      final restored = await processor.restore(encoded);
      expect(restored, orderedEquals(source));
    },
  );

  test('Base64 round-trip preserves non-UTF8 original bytes', () async {
    final source = Uint8List.fromList([
      0xff,
      0xfe,
      0x47,
      0x00,
      0x42,
      0x00,
      0x4b,
      0x00,
      0x0d,
      0x0a,
    ]);
    const processor = TextProcessor();
    final restored = await processor.restore(await processor.encode(source));
    expect(restored, orderedEquals(source));
  });

  test('restore accepts wrapped Base64 whitespace', () async {
    const processor = TextProcessor();
    final encoded = base64Encode(utf8.encode('小说文本'));
    final wrapped = Uint8List.fromList(
      ascii.encode('${encoded.substring(0, 8)}\r\n${encoded.substring(8)}'),
    );
    expect(utf8.decode(await processor.restore(wrapped)), '小说文本');
  });

  test('restore rejects invalid Base64 text', () async {
    await expectLater(
      const TextProcessor().restore(
        Uint8List.fromList(utf8.encode('不是Base64')),
      ),
      throwsA(isA<TextProcessingException>()),
    );
  });
}

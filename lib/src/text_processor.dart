import 'dart:convert';
import 'dart:isolate';
import 'dart:typed_data';

class TextProcessor {
  const TextProcessor();

  Future<Uint8List> encode(Uint8List inputBytes) {
    return Isolate.run(() => _encodeBase64(inputBytes));
  }

  Future<Uint8List> restore(Uint8List inputBytes) {
    return Isolate.run(() => _decodeBase64(inputBytes));
  }

  Future<String> encodeUtf8Text(String input) {
    return Isolate.run(() => base64Encode(utf8.encode(input)));
  }

  Future<String> restoreUtf8Text(String input) {
    return Isolate.run(() => _decodeUtf8Text(input));
  }
}

Uint8List _encodeBase64(Uint8List inputBytes) {
  return Uint8List.fromList(ascii.encode(base64Encode(inputBytes)));
}

Uint8List _decodeBase64(Uint8List inputBytes) {
  try {
    var encoded = ascii.decode(inputBytes, allowInvalid: false);
    if (encoded.startsWith('\ufeff')) encoded = encoded.substring(1);
    encoded = encoded.replaceAll(RegExp(r'\s'), '');
    return Uint8List.fromList(base64Decode(encoded));
  } on FormatException {
    throw const TextProcessingException('TXT 内容不是有效的 Base64 数据');
  }
}

String _decodeUtf8Text(String input) {
  try {
    var encoded = input;
    if (encoded.startsWith('\ufeff')) encoded = encoded.substring(1);
    encoded = encoded.replaceAll(RegExp(r'\s'), '');
    return utf8.decode(base64Decode(encoded), allowMalformed: false);
  } on FormatException {
    throw const TextProcessingException('内容不是有效的 Base64，或还原结果不是 UTF-8 文本');
  }
}

class TextProcessingException implements Exception {
  const TextProcessingException(this.message);

  final String message;

  @override
  String toString() => message;
}

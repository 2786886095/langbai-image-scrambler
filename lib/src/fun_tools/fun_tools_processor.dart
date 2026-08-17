// ignore_for_file: curly_braces_in_flow_control_structures

import 'dart:convert';
import 'dart:isolate';
import 'dart:math';
import 'dart:typed_data';

import 'package:image/image.dart' as image;

import 'fun_tools_models.dart';

/// Flutter/Dart port of the visual algorithms documented by
/// luminousott/cryptoimage (MIT). See THIRD_PARTY_NOTICES.md.
class FunToolsProcessor {
  const FunToolsProcessor();

  Future<Uint8List> createPrism({
    required Uint8List innerBytes,
    required Uint8List coverBytes,
    PrismConfig config = const PrismConfig(),
  }) => Isolate.run(() => _createPrism(innerBytes, coverBytes, config));

  Future<Uint8List> restorePrism({
    required Uint8List inputBytes,
    PrismConfig config = const PrismConfig(),
  }) => Isolate.run(() => _restorePrism(inputBytes, config));

  Future<Uint8List> createCloak({
    required Uint8List innerBytes,
    Uint8List? coverBytes,
    Uint8List? payloadBytes,
    String payloadExtension = 'bin',
    CloakConfig config = const CloakConfig(),
  }) => Isolate.run(
    () => _createCloak(
      innerBytes,
      coverBytes,
      payloadBytes,
      payloadExtension,
      config,
    ),
  );

  Future<CloakDecodedFile> decodeCloak(Uint8List inputBytes) =>
      Isolate.run(() => _decodeCloak(inputBytes));
}

Uint8List _createPrism(
  Uint8List innerBytes,
  Uint8List coverBytes,
  PrismConfig config,
) {
  final inner = _decode(innerBytes, '里图');
  final cover = _fit(_decode(coverBytes, '表图'), inner.width, inner.height);
  final source = inner.getBytes(order: image.ChannelOrder.rgba);
  final outer = cover.getBytes(order: image.ChannelOrder.rgba);
  final output = Uint8List(source.length);
  for (var y = 0; y < inner.height; y++) {
    for (var x = 0; x < inner.width; x++) {
      final offset = (y * inner.width + x) * 4;
      final coordinate = config.slope == 0
          ? (config.slope == 0 ? y : x).toDouble()
          : y / config.slope + x;
      final isCover = config.slope == 0
          ? y % (config.gap + 1) < config.gap
          : coordinate % (config.gap + 1) < config.gap;
      final input = isCover ? outer : source;
      final gray = isCover ? config.coverGray : config.innerGray;
      final threshold = isCover ? config.coverThreshold : config.innerThreshold;
      final luma = _luma(input, offset);
      for (var channel = 0; channel < 3; channel++) {
        final value = gray ? luma : input[offset + channel].toDouble();
        output[offset + channel] = isCover
            ? _scaleCover(value, threshold, config.reverse)
            : _scaleInner(value, threshold, config.reverse);
      }
      output[offset + 3] = input[offset + 3];
    }
  }
  return _png(inner.width, inner.height, output);
}

Uint8List _restorePrism(Uint8List inputBytes, PrismConfig config) {
  final inputImage = _decode(inputBytes, '光棱图片');
  final source = inputImage.getBytes(order: image.ChannelOrder.rgba);
  final output = Uint8List(source.length);
  final missing = Uint8List(inputImage.width * inputImage.height);
  final lower = config.reverse ? 255 - config.innerThreshold : 0;
  final higher = config.reverse ? 255 : config.innerThreshold;
  final scale = higher > lower ? 255 / (higher - lower) : 0.0;
  for (var pixel = 0; pixel < missing.length; pixel++) {
    final offset = pixel * 4;
    final luminance = _luma(source, offset);
    if (luminance < lower || luminance > higher) {
      missing[pixel] = 1;
      output[offset + 3] = 255;
    } else {
      for (var channel = 0; channel < 3; channel++) {
        output[offset + channel] = _clamp(
          (source[offset + channel] - lower) * scale,
        );
      }
      output[offset + 3] = source[offset + 3];
    }
  }
  _fillMissing(output, missing, inputImage.width, inputImage.height, 16);
  return _png(inputImage.width, inputImage.height, output);
}

Uint8List _createCloak(
  Uint8List innerBytes,
  Uint8List? coverBytes,
  Uint8List? payloadBytes,
  String payloadExtension,
  CloakConfig config,
) {
  final innerImage = _decode(innerBytes, '里图');
  final inner = innerImage.getBytes(order: image.ChannelOrder.rgba);
  final cover = coverBytes == null
      ? null
      : _fit(
          _decode(coverBytes, '表图'),
          innerImage.width,
          innerImage.height,
        ).getBytes(order: image.ChannelOrder.rgba);
  final version = config.version.number;
  if (config.version.needsCover && cover == null) {
    throw const FunToolException('该版本需要选择表图');
  }
  late final Uint8List output;
  if (version >= 4) {
    output = _cloakVisual(inner, cover!, config);
  } else {
    if (payloadBytes == null) {
      throw const FunToolException('v0–v3 需要选择要隐藏的文件');
    }
    final extension = _safeExtension(payloadExtension);
    final difference = config.difference.clamp(2, 80);
    final required = _requiredPixels(
      version,
      payloadBytes.length,
      extension,
      difference,
    );
    if (required > innerImage.width * innerImage.height) {
      throw FunToolException(
        '当前图片容量不足：需要约 $required 个像素，当前只有 ${innerImage.width * innerImage.height} 个像素',
      );
    }
    output = switch (version) {
      0 => _encodeV0(
        inner,
        cover!,
        innerImage.width,
        payloadBytes,
        extension,
        difference,
      ),
      1 => _encodeV1(
        inner,
        cover!,
        innerImage.width,
        payloadBytes,
        extension,
        1,
        difference,
      ),
      2 => _encodeV2(
        inner,
        cover!,
        innerImage.width,
        payloadBytes,
        extension,
        difference,
      ),
      _ => _encodeV3(inner, payloadBytes, extension, difference),
    };
  }
  return _png(innerImage.width, innerImage.height, output);
}

CloakDecodedFile _decodeCloak(Uint8List inputBytes) {
  final decoded = _decode(inputBytes, '幻影图片');
  final data = decoded.getBytes(order: image.ChannelOrder.rgba);
  final version = _detectVersion(data);
  if (version == null) throw const FunToolException('未识别到幻影坦克版本');
  if (version >= 4) {
    throw FunToolException('v$version 是视觉生成模式，不包含可提取的隐藏文件');
  }
  final result = switch (version) {
    0 => _decodeV0(data, 0),
    1 => _decodeV1(data),
    2 => _decodeV2(data),
    _ => _decodeV0(data, 3),
  };
  return CloakDecodedFile(
    version: CloakVersion.values[result.version],
    extension: result.extension,
    bytes: result.bytes,
  );
}

image.Image _decode(Uint8List bytes, String label) {
  final decoded = image.decodeImage(bytes);
  if (decoded == null) throw FunToolException('$label 格式不受支持或文件已损坏');
  return image.bakeOrientation(decoded);
}

image.Image _fit(image.Image source, int width, int height) {
  final scale = max(width / source.width, height / source.height);
  final resized = image.copyResize(
    source,
    width: max(1, (source.width * scale).round()),
    height: max(1, (source.height * scale).round()),
    interpolation: image.Interpolation.linear,
  );
  return image.copyCrop(
    resized,
    x: max(0, (resized.width - width) ~/ 2),
    y: max(0, (resized.height - height) ~/ 2),
    width: width,
    height: height,
  );
}

Uint8List _png(int width, int height, Uint8List rgba) {
  final output = image.Image.fromBytes(
    width: width,
    height: height,
    bytes: rgba.buffer,
    bytesOffset: rgba.offsetInBytes,
    numChannels: 4,
    order: image.ChannelOrder.rgba,
  );
  return image.encodePng(output, level: 6);
}

double _luma(Uint8List data, int offset) =>
    data[offset] * 0.299 + data[offset + 1] * 0.587 + data[offset + 2] * 0.114;

int _clamp(num value) => value.round().clamp(0, 255);

int _scaleInner(num value, int threshold, bool reverse) => _clamp(
  reverse ? 255 - threshold + value * threshold / 255 : value * threshold / 255,
);

int _scaleCover(num value, int threshold, bool reverse) => _clamp(
  reverse
      ? value * (255 - threshold) / 255
      : threshold + value * (255 - threshold) / 255,
);

void _fillMissing(
  Uint8List output,
  Uint8List missing,
  int width,
  int height,
  int iterations,
) {
  const offsets = <(int, int, double)>[
    (-1, 0, .6065),
    (1, 0, .6065),
    (0, -1, .6065),
    (0, 1, .6065),
    (-1, -1, .3679),
    (1, 1, .3679),
    (-1, 1, .3679),
    (1, -1, .3679),
  ];
  for (var iteration = 0; iteration < iterations; iteration++) {
    var changed = false;
    final next = Uint8List.fromList(output);
    final nextMissing = Uint8List.fromList(missing);
    for (var pixel = 0; pixel < missing.length; pixel++) {
      if (missing[pixel] == 0) continue;
      final x = pixel % width;
      final y = pixel ~/ width;
      final sums = List<double>.filled(4, 0);
      var weightSum = 0.0;
      for (final (dx, dy, weight) in offsets) {
        final nx = x + dx;
        final ny = y + dy;
        if (nx < 0 || ny < 0 || nx >= width || ny >= height) continue;
        final neighbor = ny * width + nx;
        if (missing[neighbor] != 0) continue;
        final source = neighbor * 4;
        for (var channel = 0; channel < 4; channel++) {
          sums[channel] += output[source + channel] * weight;
        }
        weightSum += weight;
      }
      if (weightSum > 0) {
        final target = pixel * 4;
        for (var channel = 0; channel < 4; channel++) {
          next[target + channel] = _clamp(sums[channel] / weightSum);
        }
        nextMissing[pixel] = 0;
        changed = true;
      }
    }
    output.setAll(0, next);
    missing.setAll(0, nextMissing);
    if (!changed) break;
  }
}

Uint8List _cloakVisual(Uint8List inner, Uint8List cover, CloakConfig config) {
  final version = config.version.number;
  final gray = version == 4 || config.grayMode;
  final innerScale = version == 4 ? .5 : config.innerScale;
  final coverScale = version == 4 ? .5 : 1 - config.coverScale;
  final innerWeight = config.innerWeight.clamp(0.0, 1.0);
  final output = Uint8List(inner.length);
  output.setRange(0, 4, [
    version == 4 ? 114 : 51,
    version == 4 ? 114 : 51,
    version == 4 ? 114 : 51,
    255,
  ]);
  for (var index = 4; index < inner.length; index += 4) {
    final innerGray = _luma(inner, index);
    final coverGray = _luma(cover, index);
    if (gray) {
      final low = (innerGray * innerScale).floor();
      final high = (255 - (255 - coverGray) * coverScale).floor();
      final alpha = (255 - high + low).clamp(0, 255);
      final color = alpha > 0 ? low * 255 / alpha : 0;
      output[index] = output[index + 1] = output[index + 2] = _clamp(color);
      output[index + 3] = alpha;
      continue;
    }
    final low = List<double>.generate(3, (c) => inner[index + c] * innerScale);
    final high = List<double>.generate(
      3,
      (c) => 255 - (255 - cover[index + c]) * coverScale,
    );
    final alpha =
        ((255 +
                    innerGray * innerScale -
                    (255 - (255 - coverGray) * coverScale)) /
                255)
            .clamp(0.0, 1.0);
    if (alpha <= 0) continue;
    final alphaPixels = 255 * alpha;
    for (var channel = 0; channel < 3; channel++) {
      output[index + channel] = _clamp(
        ((low[channel] - alphaPixels + 255 - high[channel]) * innerWeight +
                alphaPixels -
                255 +
                high[channel]) /
            alpha,
      );
    }
    output[index + 3] = _clamp(alphaPixels);
  }
  return output;
}

String _safeExtension(String value) {
  final cleaned = value.toLowerCase().replaceAll(RegExp('[^a-z0-9]'), '');
  return cleaned.isEmpty
      ? 'bin'
      : cleaned.substring(0, min(10, cleaned.length));
}

Uint8List _headerV3(String extension, int payloadLength) => Uint8List.fromList(
  utf8.encode(
    '$payloadLength\x01mtc.$extension\x01application/octet-stream\x00',
  ),
);

int _compressBits(int difference) => (difference ~/ 10).clamp(1, 7);

int _requiredPixels(
  int version,
  int payloadLength,
  String extension,
  int difference,
) {
  if (version == 0 || version == 3) {
    return (((_headerV3(extension, payloadLength).length + payloadLength) * 8) /
                _compressBits(difference) /
                3)
            .ceil() +
        1;
  }
  if (version == 1) return (payloadLength + 32) * 3;
  if (version == 2) return ((payloadLength / 2).ceil() + 32) * 3 + 3;
  return 1;
}

bool _isInner(int pixel, int width) =>
    ((pixel % width) + pixel ~/ width).isEven;

int _pixelAlpha(Uint8List data, int offset, bool inner) {
  final luminance = _luma(data, offset);
  return _clamp(inner ? luminance * .8 + 32 : 255 - luminance * .8);
}

List<int> _byteBits(int value, int group) {
  final shifted = value >> (group * 3);
  if (group != 2) return [shifted & 1, shifted >> 1 & 1, shifted >> 2 & 1];
  var parity = 0;
  for (var bit = 0; bit < 8; bit++) parity ^= value >> bit & 1;
  return [shifted & 1, shifted >> 1 & 1, parity];
}

List<int> _pairBits(int value, int group) {
  final shifted = value >> (group * 6);
  if (group != 2) return [shifted & 3, shifted >> 2 & 3, shifted >> 4 & 3];
  var low = 0;
  var high = 0;
  for (var bit = 0; bit < 8; bit++) low ^= value >> bit & 1;
  for (var bit = 8; bit < 16; bit++) high ^= (value >> bit & 1) << 1;
  return [shifted & 3, shifted >> 2 & 3, low | high];
}

void _versionMarker(
  Uint8List inner,
  Uint8List cover,
  int width,
  Uint8List output,
  int version,
) {
  for (var pixel = 0; pixel < 3; pixel++) {
    final offset = pixel * 4;
    final bits = _byteBits(version, pixel);
    final useInner = _isInner(pixel, width);
    for (var channel = 0; channel < 3; channel++) {
      output[offset + channel] = useInner
          ? (bits[channel] == 1 ? 223 : 255)
          : (bits[channel] == 1 ? 32 : 0);
    }
    output[offset + 3] = _pixelAlpha(
      useInner ? inner : cover,
      offset,
      useInner,
    );
  }
}

Uint8List _encodeV1(
  Uint8List inner,
  Uint8List cover,
  int width,
  Uint8List payload,
  String extension,
  int version,
  int difference,
) {
  final header = Uint8List(16);
  header[0] = version;
  header[1] = difference ~/ 2;
  ByteData.sublistView(header).setUint32(2, payload.length, Endian.little);
  for (var i = 0; i < min(10, extension.length); i++)
    header[6 + i] = extension.codeUnitAt(i);
  final stream = Uint8List(inner.length ~/ 4 ~/ 3);
  stream.setAll(0, header);
  stream.setAll(header.length, payload);
  final random = Random.secure();
  for (var i = header.length + payload.length; i < stream.length; i++)
    stream[i] = random.nextInt(256);
  final output = Uint8List(inner.length);
  _versionMarker(inner, cover, width, output, version);
  for (var pixel = 3; pixel < inner.length ~/ 4; pixel++) {
    final offset = pixel * 4;
    final streamIndex = pixel ~/ 3;
    final bits = _byteBits(
      streamIndex < stream.length ? stream[streamIndex] : 0,
      pixel % 3,
    );
    final useInner = _isInner(pixel, width);
    for (var c = 0; c < 3; c++)
      output[offset + c] = useInner
          ? (bits[c] == 1 ? 255 - difference : 255)
          : (bits[c] == 1 ? difference : 0);
    output[offset + 3] = _pixelAlpha(
      useInner ? inner : cover,
      offset,
      useInner,
    );
  }
  return output;
}

Uint8List _encodeV2(
  Uint8List inner,
  Uint8List cover,
  int width,
  Uint8List payload,
  String extension,
  int difference,
) {
  final capacity = (inner.length ~/ 4 - 3) ~/ 3;
  final stream = Uint16List(capacity);
  stream[0] = difference ~/ 6;
  stream[1] = stream[0];
  stream[2] = payload.length & 0xffff;
  stream[3] = payload.length >> 16 & 0xffff;
  for (var i = 0; i < min(12, extension.length); i++)
    stream[4 + i] = extension.codeUnitAt(i);
  for (var i = 0; i < (payload.length / 2).ceil(); i++)
    stream[16 + i] =
        payload[i * 2] |
        ((i * 2 + 1 < payload.length ? payload[i * 2 + 1] : 0) << 8);
  final output = Uint8List(inner.length);
  _versionMarker(inner, cover, width, output, 2);
  for (var pixel = 3; pixel < inner.length ~/ 4; pixel++) {
    final streamIndex = (pixel - 3) ~/ 3;
    final bits = _pairBits(
      streamIndex < stream.length ? stream[streamIndex] : 0,
      (pixel - 3) % 3,
    );
    final offset = pixel * 4;
    final useInner = _isInner(pixel, width);
    final delta = ((pixel < 6 ? 60 : difference) / 3).floor();
    for (var c = 0; c < 3; c++)
      output[offset + c] = useInner ? 255 - delta * bits[c] : delta * bits[c];
    output[offset + 3] = _pixelAlpha(
      useInner ? inner : cover,
      offset,
      useInner,
    );
  }
  return output;
}

Uint8List _encodeV0(
  Uint8List inner,
  Uint8List cover,
  int width,
  Uint8List payload,
  String extension,
  int difference,
) {
  final compress = _compressBits(difference);
  final header = _headerV3(extension, payload.length);
  final stream = Uint8List(header.length + payload.length)
    ..setAll(0, header)
    ..setAll(header.length, payload);
  final output = Uint8List(inner.length);
  output.setRange(0, 4, [
    248,
    251,
    248 | compress,
    _pixelAlpha(inner, 0, true),
  ]);
  final state = _BitReadState();
  final base = 255 & ~((1 << compress) - 1);
  for (var pixel = 1; pixel < inner.length ~/ 4; pixel++) {
    final offset = pixel * 4;
    final useInner = _isInner(pixel, width);
    for (var c = 0; c < 3; c++) {
      final chunk = _readStreamChunk(stream, state, compress);
      output[offset + c] = useInner ? base | chunk : chunk;
    }
    output[offset + 3] = _pixelAlpha(
      useInner ? inner : cover,
      offset,
      useInner,
    );
  }
  return output;
}

Uint8List _encodeV3(
  Uint8List inner,
  Uint8List payload,
  String extension,
  int difference,
) {
  final compress = _compressBits(difference);
  final header = _headerV3(extension, payload.length);
  final stream = Uint8List(header.length + payload.length)
    ..setAll(0, header)
    ..setAll(header.length, payload);
  final output = Uint8List(inner.length);
  output.setRange(0, 4, [
    (inner[0] & 192) | 56,
    (inner[1] & 192) | 35,
    (inner[2] & 192) | compress,
    255,
  ]);
  final state = _BitReadState();
  final base = 255 & ~((1 << compress) - 1);
  for (var pixel = 1; pixel < inner.length ~/ 4; pixel++) {
    final offset = pixel * 4;
    for (var c = 0; c < 3; c++)
      output[offset + c] = base | _readStreamChunk(stream, state, compress);
    output[offset + 3] = 255;
  }
  return output;
}

int _readStreamChunk(Uint8List stream, _BitReadState state, int compress) {
  var value = 0;
  for (var count = 0; count < compress; count++) {
    final byte = state.bitPosition ~/ 8 < stream.length
        ? stream[state.bitPosition ~/ 8]
        : 0;
    value = value << 1 | (byte >> (7 - state.bitPosition % 8) & 1);
    state.bitPosition++;
  }
  return value;
}

int? _detectVersion(Uint8List data) {
  if (data.length < 12) return null;
  if (data[0] == 114 && data[1] == 114 && data[2] == 114 && data[3] == 255)
    return 4;
  if (data[0] == 51 && data[1] == 51 && data[2] == 51 && data[3] == 255)
    return 5;
  if (data[0] & 63 == 56 &&
      data[1] & 63 == 35 &&
      (data[2] & 63) >= 1 &&
      (data[2] & 63) <= 7)
    return 3;
  if (data[0] & 7 == 0 && data[1] & 7 == 3 && (data[2] & 7) >= 1) return 0;
  for (final candidate in [1, 2]) {
    try {
      if (_readByte(data, _PixelState(), 16) == candidate) return candidate;
    } catch (_) {}
  }
  return null;
}

_Decoded _decodeV1(Uint8List data) {
  final state = _PixelState(pixel: 3);
  final threshold = _readByte(data, state, 16);
  var length = 0;
  for (var shift = 0; shift < 32; shift += 8)
    length |= _readByte(data, state, threshold) << shift;
  if (length < 0 || length > data.length)
    throw const FunToolException('幻影隐藏文件长度无效');
  final extension = StringBuffer();
  for (var i = 0; i < 10; i++) {
    final value = _readByte(data, state, threshold);
    if (value != 0) extension.writeCharCode(value);
  }
  final bytes = Uint8List(length);
  for (var i = 0; i < length; i++) bytes[i] = _readByte(data, state, threshold);
  return _Decoded(1, extension.isEmpty ? 'bin' : extension.toString(), bytes);
}

_Decoded _decodeV2(Uint8List data) {
  final state = _PixelState(pixel: 3);
  final threshold = _readPair(data, state, 10);
  _readPair(data, state, threshold);
  final length =
      _readPair(data, state, threshold) |
      _readPair(data, state, threshold) << 16;
  if (length > data.length) throw const FunToolException('幻影隐藏文件长度无效');
  final extension = StringBuffer();
  for (var i = 0; i < 12; i++) {
    final value = _readPair(data, state, threshold);
    if (value != 0) extension.writeCharCode(value & 255);
  }
  final bytes = Uint8List(length);
  for (var i = 0; i < length; i += 2) {
    final pair = _readPair(data, state, threshold);
    bytes[i] = pair & 255;
    if (i + 1 < length) bytes[i + 1] = pair >> 8;
  }
  return _Decoded(2, extension.isEmpty ? 'bin' : extension.toString(), bytes);
}

_Decoded _decodeV0(Uint8List data, int version) {
  final compress = data[2] & 7;
  final state = _CompressedState();
  final lengthText = StringBuffer();
  var value = 0;
  while ((value = _readCompressed(data, state, compress)) != 1)
    lengthText.writeCharCode(value);
  final length = int.tryParse(lengthText.toString());
  if (length == null || length < 0 || length > data.length)
    throw const FunToolException('幻影隐藏文件长度无效');
  final extensionText = StringBuffer();
  while ((value = _readCompressed(data, state, compress)) != 1)
    extensionText.writeCharCode(value);
  final raw = extensionText.toString();
  final extension = raw.contains('.')
      ? raw.substring(raw.indexOf('.') + 1)
      : raw;
  while (_readCompressed(data, state, compress) != 0) {}
  final bytes = Uint8List(length);
  for (var i = 0; i < length; i++)
    bytes[i] = _readCompressed(data, state, compress);
  return _Decoded(version, extension.isEmpty ? 'bin' : extension, bytes);
}

int _readByte(Uint8List data, _PixelState state, int threshold) {
  var value = 0;
  var bitCount = 0;
  while (state.pixel < data.length ~/ 4) {
    final offset = state.pixel * 4;
    final high = data[offset] > 127;
    bool isSet(int number) =>
        high ? number < 255 - threshold : number > threshold;
    for (var channel = 0; channel < 3; channel++) {
      if (bitCount == 8) break;
      value |= (isSet(data[offset + channel]) ? 1 : 0) << bitCount++;
    }
    final parity = isSet(data[offset + 2]) ? 1 : 0;
    state.pixel++;
    if (bitCount == 8) {
      var expected = 0;
      for (var bit = 0; bit < 8; bit++) expected ^= value >> bit & 1;
      if (expected != parity) throw const FunToolException('幻影数据校验失败');
      return value;
    }
  }
  throw const FunToolException('幻影数据不完整');
}

int _readPair(Uint8List data, _PixelState state, int threshold) {
  var value = 0;
  var pairCount = 0;
  int highBits(int number) =>
      ((255 - number + threshold) ~/ max(1, threshold * 2)).clamp(0, 3);
  int lowBits(int number) =>
      ((number + threshold) ~/ max(1, threshold * 2)).clamp(0, 3);
  while (state.pixel < data.length ~/ 4) {
    final offset = state.pixel * 4;
    final get = data[offset] > 127 ? highBits : lowBits;
    for (var channel = 0; channel < 3; channel++) {
      if (pairCount == 8) break;
      value |= get(data[offset + channel]) << pairCount++ * 2;
    }
    final parity = get(data[offset + 2]);
    state.pixel++;
    if (pairCount == 8) {
      var expected = 0;
      for (var bit = 0; bit < 8; bit++) expected ^= value >> bit & 1;
      for (var bit = 8; bit < 16; bit++) expected ^= (value >> bit & 1) << 1;
      if (expected != parity) throw const FunToolException('幻影数据校验失败');
      return value;
    }
  }
  throw const FunToolException('幻影数据不完整');
}

int _readCompressed(Uint8List data, _CompressedState state, int compress) {
  if (compress == 0) throw const FunToolException('幻影压缩位无效');
  while (state.bits < 8) {
    if (state.pixel >= data.length ~/ 4)
      throw const FunToolException('幻影数据不完整');
    final offset = state.pixel * 4 + state.channel;
    state.buffer =
        state.buffer << compress | data[offset] & ((1 << compress) - 1);
    state.bits += compress;
    state.channel++;
    if (state.channel == 3) {
      state.channel = 0;
      state.pixel++;
    }
  }
  final shift = state.bits - 8;
  final value = state.buffer >> shift & 255;
  state.bits = shift;
  state.buffer = shift == 0 ? 0 : state.buffer & ((1 << shift) - 1);
  return value;
}

class _BitReadState {
  int bitPosition = 0;
}

class _PixelState {
  _PixelState({this.pixel = 0});
  int pixel;
}

class _CompressedState {
  int pixel = 1;
  int channel = 0;
  int buffer = 0;
  int bits = 0;
}

class _Decoded {
  const _Decoded(this.version, this.extension, this.bytes);
  final int version;
  final String extension;
  final Uint8List bytes;
}

import 'dart:isolate';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:image/image.dart' as image;

import 'algorithms.dart';
import 'metadata.dart';
import 'models.dart';

class ImageProcessor {
  ImageProcessor({ManifestCodec? manifestCodec})
    : _manifestCodec = manifestCodec ?? ManifestCodec();

  final ManifestCodec _manifestCodec;
  final Random _random = Random.secure();

  Future<ProcessedImage> scramble({
    required Uint8List inputBytes,
    required String sourceName,
    required ScrambleAlgorithm algorithm,
    String? password,
  }) async {
    if (algorithm.isAutomatic) {
      throw const ImageProcessingException('请选择混淆算法');
    }
    final seed = algorithm.needsSeed ? _nextSeed() : 0;
    final rawResult = await Isolate.run(
      () => _transformForScramble(inputBytes, algorithm.id, seed),
    );
    final manifest = ScrambleManifest(
      algorithm: algorithm,
      seed: seed,
      width: rawResult['width']! as int,
      height: rawResult['height']! as int,
      sourceName: sourceName,
      pixelChecksum: rawResult['checksum']! as String,
      createdAt: DateTime.now(),
    );
    final envelope = await _manifestCodec.encode(manifest, password);
    final pngBytes = await Isolate.run(
      () => _encodePng(
        rawResult['width']! as int,
        rawResult['height']! as int,
        rawResult['rgba']! as Uint8List,
        envelope,
      ),
    );
    return ProcessedImage(
      bytes: pngBytes,
      algorithm: algorithm,
      verified: true,
    );
  }

  Future<ProcessedImage> restore({
    required Uint8List inputBytes,
    required ScrambleAlgorithm requestedAlgorithm,
    String? password,
    int? manualSeed,
  }) async {
    final encodedManifest = PngManifestReader.read(inputBytes);
    ScrambleManifest? manifest;
    late final ScrambleAlgorithm algorithm;
    late final int seed;

    if (encodedManifest != null) {
      manifest = await _manifestCodec.decode(encodedManifest, password);
      algorithm = manifest.algorithm;
      seed = manifest.seed;
    } else {
      if (requestedAlgorithm.isAutomatic) {
        throw const MetadataMissingException();
      }
      algorithm = requestedAlgorithm;
      if (algorithm.needsSeed && manualSeed == null) {
        throw const ImageProcessingException('该图片没有算法标识，请输入生成时的随机种子');
      }
      seed = algorithm.needsSeed ? manualSeed! : 0;
    }

    final result = await Isolate.run(
      () => _transformForRestore(
        inputBytes,
        algorithm.id,
        seed,
        manifest?.pixelChecksum,
      ),
    );
    return ProcessedImage(
      bytes: result['png']! as Uint8List,
      algorithm: algorithm,
      verified: result['verified']! as bool,
    );
  }

  ManifestEnvelope? inspectProtection(Uint8List inputBytes) {
    final encoded = PngManifestReader.read(inputBytes);
    return encoded == null ? null : _manifestCodec.inspect(encoded);
  }

  int _nextSeed() {
    var seed = _random.nextInt(0x7fffffff);
    if (seed == 0) seed = 1;
    return seed;
  }
}

Map<String, Object> _transformForScramble(
  Uint8List bytes,
  String algorithmId,
  int seed,
) {
  final decoded = image.decodeImage(bytes);
  if (decoded == null) {
    throw const ImageProcessingException('图片格式不受支持或文件已损坏');
  }
  final oriented = image.bakeOrientation(decoded);
  final rgba = oriented.getBytes(order: image.ChannelOrder.rgba);
  final checksum = sha256.convert(rgba).toString();
  final transformed = ScrambleEngine.transform(
    ImageRaster(oriented.width, oriented.height, rgba),
    ScrambleAlgorithmX.fromId(algorithmId),
    seed,
    reverse: false,
  );
  return <String, Object>{
    'width': transformed.width,
    'height': transformed.height,
    'rgba': transformed.rgba,
    'checksum': checksum,
  };
}

Map<String, Object> _transformForRestore(
  Uint8List bytes,
  String algorithmId,
  int seed,
  String? expectedChecksum,
) {
  final decoded = image.decodeImage(bytes);
  if (decoded == null) {
    throw const ImageProcessingException('图片格式不受支持或文件已损坏');
  }
  final oriented = image.bakeOrientation(decoded);
  final rgba = oriented.getBytes(order: image.ChannelOrder.rgba);
  final restored = ScrambleEngine.transform(
    ImageRaster(oriented.width, oriented.height, rgba),
    ScrambleAlgorithmX.fromId(algorithmId),
    seed,
    reverse: true,
  );
  final checksum = sha256.convert(restored.rgba).toString();
  final verified = expectedChecksum == null || expectedChecksum.isEmpty
      ? false
      : checksum == expectedChecksum;
  if (expectedChecksum != null && expectedChecksum.isNotEmpty && !verified) {
    throw const ImageProcessingException('像素校验失败：图片可能已被压缩、缩放或修改');
  }
  return <String, Object>{
    'png': _encodePng(restored.width, restored.height, restored.rgba, null),
    'verified': verified,
  };
}

Uint8List _encodePng(int width, int height, Uint8List rgba, String? envelope) {
  final output = image.Image.fromBytes(
    width: width,
    height: height,
    bytes: rgba.buffer,
    bytesOffset: rgba.offsetInBytes,
    numChannels: 4,
    order: image.ChannelOrder.rgba,
  );
  if (envelope != null) {
    output.textData = {PngManifestReader.keyword: envelope};
  }
  return image.encodePng(output, level: 6);
}

class ImageProcessingException implements Exception {
  const ImageProcessingException(this.message);
  final String message;

  @override
  String toString() => message;
}

class MetadataMissingException extends ImageProcessingException {
  const MetadataMissingException() : super('未识别到 Langbai 算法标识，请手动选择算法');
}

import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' as crypto;
import 'package:cryptography/cryptography.dart';

import 'video_models.dart';

class VideoContainer {
  VideoContainer({Random? random}) : _random = random ?? Random.secure();

  static const _magicText = 'LANGBAI-VIDEO-1!';
  static final _magic = ascii.encode(_magicText);
  static const chunkSize = 4 * 1024 * 1024;
  static const _iterations = 210000;

  final Random _random;
  final AesGcm _cipher = AesGcm.with256bits();

  Future<VideoManifest> appendOriginal({
    required String playablePath,
    required String originalPath,
    required String outputPath,
    required VideoAlgorithm algorithm,
    required VideoAudioMode audioMode,
    required int seed,
    String? password,
  }) async {
    final original = File(originalPath);
    final output = File(outputPath);
    await output.parent.create(recursive: true);
    await File(playablePath).openRead().pipe(output.openWrite());

    final protected = password != null && password.isNotEmpty;
    final salt = protected ? _randomBytes(16) : null;
    final baseNonce = protected ? _randomBytes(8) : null;
    final key = protected ? await _deriveKey(password, salt!) : null;
    final digest = _DigestSink();
    final hashInput = crypto.sha256.startChunkedConversion(digest);
    final payloadStart = await output.length();
    final sink = output.openWrite(mode: FileMode.append);
    var chunkIndex = 0;
    final originalHandle = await original.open();
    try {
      while (true) {
        final raw = await originalHandle.read(chunkSize);
        if (raw.isEmpty) break;
        hashInput.add(raw);
        if (!protected) {
          sink.add(raw);
        } else {
          final nonce = Uint8List(12)..setAll(0, baseNonce!);
          ByteData.sublistView(nonce).setUint32(8, chunkIndex, Endian.big);
          final box = await _cipher.encrypt(raw, secretKey: key!, nonce: nonce);
          sink
            ..add(box.cipherText)
            ..add(box.mac.bytes);
        }
        chunkIndex++;
      }
      hashInput.close();
      await sink.flush();
      await sink.close();
    } catch (_) {
      await sink.close();
      rethrow;
    } finally {
      await originalHandle.close();
    }

    final payloadLength = await output.length() - payloadStart;
    final manifest = VideoManifest(
      originalName: original.uri.pathSegments.last,
      originalLength: await original.length(),
      originalSha256: digest.value.toString(),
      algorithm: algorithm,
      audioMode: audioMode,
      seed: seed,
      passwordProtected: protected,
      chunkSize: chunkSize,
      salt: salt,
      baseNonce: baseNonce,
    );
    final metadata = utf8.encode(
      jsonEncode({
        'version': 1,
        'originalName': manifest.originalName,
        'originalLength': manifest.originalLength,
        'originalSha256': manifest.originalSha256,
        'algorithm': algorithm.id,
        'audioMode': audioMode.id,
        'seed': seed,
        'passwordProtected': protected,
        'kdf': protected ? 'PBKDF2-HMAC-SHA256' : null,
        'iterations': protected ? _iterations : null,
        'chunkSize': chunkSize,
        'salt': salt == null ? null : base64Encode(salt),
        'baseNonce': baseNonce == null ? null : base64Encode(baseNonce),
      }),
    );
    final footer = ByteData(16)
      ..setUint64(0, payloadLength, Endian.big)
      ..setUint64(8, metadata.length, Endian.big);
    final footerSink = output.openWrite(mode: FileMode.append);
    footerSink
      ..add(metadata)
      ..add(footer.buffer.asUint8List())
      ..add(_magic);
    await footerSink.flush();
    await footerSink.close();
    return manifest;
  }

  Future<VideoManifest?> inspect(String path) async {
    final file = File(path);
    if (!await file.exists() || await file.length() < 32) return null;
    final handle = await file.open();
    try {
      final length = await file.length();
      await handle.setPosition(length - _magic.length);
      if (!_same(await handle.read(_magic.length), _magic)) return null;
      await handle.setPosition(length - _magic.length - 16);
      final footer = ByteData.sublistView(
        Uint8List.fromList(await handle.read(16)),
      );
      final payloadLength = footer.getUint64(0, Endian.big);
      final metadataLength = footer.getUint64(8, Endian.big);
      final metadataStart = length - _magic.length - 16 - metadataLength;
      if (payloadLength <= 0 || metadataStart - payloadLength < 0) return null;
      await handle.setPosition(metadataStart);
      final json =
          jsonDecode(utf8.decode(await handle.read(metadataLength)))
              as Map<String, dynamic>;
      if (json['version'] != 1) return null;
      return _manifestFromJson(json);
    } catch (_) {
      return null;
    } finally {
      await handle.close();
    }
  }

  Future<VideoManifest> extractOriginal({
    required String inputPath,
    required String outputPath,
    String? password,
  }) async {
    final file = File(inputPath);
    final handle = await file.open();
    late final VideoManifest manifest;
    try {
      final length = await file.length();
      await handle.setPosition(length - _magic.length - 16);
      final footer = ByteData.sublistView(
        Uint8List.fromList(await handle.read(16)),
      );
      final payloadLength = footer.getUint64(0, Endian.big);
      final metadataLength = footer.getUint64(8, Endian.big);
      final metadataStart = length - _magic.length - 16 - metadataLength;
      final payloadStart = metadataStart - payloadLength;
      if (payloadStart < 0) throw const VideoProcessException('视频精确还原数据已损坏');
      await handle.setPosition(metadataStart);
      final json =
          jsonDecode(utf8.decode(await handle.read(metadataLength)))
              as Map<String, dynamic>;
      manifest = _manifestFromJson(json);
      if (manifest.passwordProtected &&
          (password == null || password.isEmpty)) {
        throw const VideoProcessException('该视频受密码保护，请输入密码');
      }
      final output = File(outputPath);
      await output.parent.create(recursive: true);
      final sink = output.openWrite();
      final digest = _DigestSink();
      final hashInput = crypto.sha256.startChunkedConversion(digest);
      final key = manifest.passwordProtected
          ? await _deriveKey(password!, manifest.salt!)
          : null;
      await handle.setPosition(payloadStart);
      var remainingPlain = manifest.originalLength;
      var remainingPayload = payloadLength;
      var chunkIndex = 0;
      try {
        while (remainingPlain > 0) {
          final plainLength = min(manifest.chunkSize, remainingPlain);
          final storedLength =
              plainLength + (manifest.passwordProtected ? 16 : 0);
          if (storedLength > remainingPayload) {
            throw const VideoProcessException('视频精确还原数据不完整');
          }
          final stored = Uint8List.fromList(await handle.read(storedLength));
          if (stored.length != storedLength) {
            throw const VideoProcessException('视频精确还原数据不完整');
          }
          late final List<int> plain;
          if (!manifest.passwordProtected) {
            plain = stored;
          } else {
            final nonce = Uint8List(12)..setAll(0, manifest.baseNonce!);
            ByteData.sublistView(nonce).setUint32(8, chunkIndex, Endian.big);
            try {
              plain = await _cipher.decrypt(
                SecretBox(
                  stored.sublist(0, plainLength),
                  nonce: nonce,
                  mac: Mac(stored.sublist(plainLength)),
                ),
                secretKey: key!,
              );
            } on SecretBoxAuthenticationError {
              throw const VideoProcessException('密码不正确或视频还原数据已损坏');
            }
          }
          sink.add(plain);
          hashInput.add(plain);
          remainingPlain -= plainLength;
          remainingPayload -= storedLength;
          chunkIndex++;
        }
        hashInput.close();
        await sink.flush();
        await sink.close();
      } catch (_) {
        await sink.close();
        if (await output.exists()) await output.delete();
        rethrow;
      }
      if (digest.value.toString() != manifest.originalSha256) {
        await output.delete();
        throw const VideoProcessException('SHA-256 校验失败，原视频数据不完整');
      }
      return manifest;
    } finally {
      await handle.close();
    }
  }

  VideoManifest _manifestFromJson(Map<String, dynamic> json) => VideoManifest(
    originalName: json['originalName'] as String? ?? 'video.mp4',
    originalLength: (json['originalLength'] as num?)?.toInt() ?? 0,
    originalSha256: json['originalSha256'] as String? ?? '',
    algorithm: VideoAlgorithmX.fromId(json['algorithm'] as String?),
    audioMode: VideoAudioModeX.fromId(json['audioMode'] as String?),
    seed: (json['seed'] as num?)?.toInt() ?? 0,
    passwordProtected: json['passwordProtected'] == true,
    chunkSize: (json['chunkSize'] as num?)?.toInt() ?? chunkSize,
    salt: json['salt'] == null ? null : base64Decode(json['salt'] as String),
    baseNonce: json['baseNonce'] == null
        ? null
        : base64Decode(json['baseNonce'] as String),
  );

  Future<SecretKey> _deriveKey(String password, List<int> salt) => Pbkdf2(
    macAlgorithm: Hmac.sha256(),
    iterations: _iterations,
    bits: 256,
  ).deriveKey(secretKey: SecretKey(utf8.encode(password)), nonce: salt);

  Uint8List _randomBytes(int length) => Uint8List.fromList(
    List<int>.generate(length, (_) => _random.nextInt(256)),
  );

  bool _same(List<int> left, List<int> right) {
    if (left.length != right.length) return false;
    for (var i = 0; i < left.length; i++) {
      if (left[i] != right[i]) return false;
    }
    return true;
  }
}

class _DigestSink implements Sink<crypto.Digest> {
  crypto.Digest? _value;

  crypto.Digest get value {
    final result = _value;
    if (result == null) throw StateError('SHA-256 尚未完成');
    return result;
  }

  @override
  void add(crypto.Digest data) => _value = data;

  @override
  void close() {}
}

import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

import 'models.dart';

class ScrambleManifest {
  const ScrambleManifest({
    required this.algorithm,
    required this.seed,
    required this.width,
    required this.height,
    required this.sourceName,
    required this.pixelChecksum,
    required this.createdAt,
  });

  static const formatVersion = 1;

  final ScrambleAlgorithm algorithm;
  final int seed;
  final int width;
  final int height;
  final String sourceName;
  final String pixelChecksum;
  final DateTime createdAt;

  Map<String, Object> toJson() => {
    'version': formatVersion,
    'algorithm': algorithm.id,
    'seed': seed,
    'width': width,
    'height': height,
    'sourceName': sourceName,
    'pixelChecksum': pixelChecksum,
    'createdAt': createdAt.toUtc().toIso8601String(),
  };

  factory ScrambleManifest.fromJson(Map<String, dynamic> json) {
    if (json['version'] != formatVersion) {
      throw const ManifestException('暂不支持此混淆图版本');
    }
    final algorithm = ScrambleAlgorithmX.fromId(
      json['algorithm'] as String? ?? '',
    );
    if (algorithm.isAutomatic) {
      throw const ManifestException('混淆算法标识无效');
    }
    return ScrambleManifest(
      algorithm: algorithm,
      seed: (json['seed'] as num?)?.toInt() ?? 0,
      width: (json['width'] as num?)?.toInt() ?? 0,
      height: (json['height'] as num?)?.toInt() ?? 0,
      sourceName: json['sourceName'] as String? ?? 'image',
      pixelChecksum: json['pixelChecksum'] as String? ?? '',
      createdAt:
          DateTime.tryParse(json['createdAt'] as String? ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
    );
  }
}

class ManifestEnvelope {
  const ManifestEnvelope({required this.protected, required this.json});

  final bool protected;
  final Map<String, dynamic> json;
}

class ManifestCodec {
  ManifestCodec({Random? random}) : _random = random ?? Random.secure();

  static const magic = 'LBS1';
  final Random _random;
  final AesGcm _cipher = AesGcm.with256bits();

  Future<String> encode(ScrambleManifest manifest, String? password) async {
    final plainBytes = utf8.encode(jsonEncode(manifest.toJson()));
    if (password == null || password.isEmpty) {
      return jsonEncode({
        'magic': magic,
        'protected': false,
        'payload': base64Encode(plainBytes),
      });
    }

    final salt = _randomBytes(16);
    final nonce = _randomBytes(12);
    final key = await _deriveKey(password, salt);
    final secretBox = await _cipher.encrypt(
      plainBytes,
      secretKey: key,
      nonce: nonce,
    );
    return jsonEncode({
      'magic': magic,
      'protected': true,
      'kdf': 'PBKDF2-HMAC-SHA256',
      'iterations': 210000,
      'salt': base64Encode(salt),
      'nonce': base64Encode(nonce),
      'cipherText': base64Encode(secretBox.cipherText),
      'mac': base64Encode(secretBox.mac.bytes),
    });
  }

  ManifestEnvelope inspect(String encoded) {
    try {
      final json = jsonDecode(encoded) as Map<String, dynamic>;
      if (json['magic'] != magic) {
        throw const ManifestException('不是 Langbai 混淆图');
      }
      return ManifestEnvelope(protected: json['protected'] == true, json: json);
    } on ManifestException {
      rethrow;
    } catch (_) {
      throw const ManifestException('混淆图标识已损坏');
    }
  }

  Future<ScrambleManifest> decode(String encoded, String? password) async {
    final envelope = inspect(encoded);
    try {
      late final List<int> plainBytes;
      if (!envelope.protected) {
        plainBytes = base64Decode(envelope.json['payload'] as String);
      } else {
        if (password == null || password.isEmpty) {
          throw const PasswordRequiredException();
        }
        final salt = base64Decode(envelope.json['salt'] as String);
        final nonce = base64Decode(envelope.json['nonce'] as String);
        final key = await _deriveKey(password, salt);
        plainBytes = await _cipher.decrypt(
          SecretBox(
            base64Decode(envelope.json['cipherText'] as String),
            nonce: nonce,
            mac: Mac(base64Decode(envelope.json['mac'] as String)),
          ),
          secretKey: key,
        );
      }
      return ScrambleManifest.fromJson(
        jsonDecode(utf8.decode(plainBytes)) as Map<String, dynamic>,
      );
    } on PasswordRequiredException {
      rethrow;
    } on SecretBoxAuthenticationError {
      throw const InvalidPasswordException();
    } on ManifestException {
      rethrow;
    } catch (_) {
      throw const ManifestException('混淆图标识已损坏或密码不正确');
    }
  }

  Future<SecretKey> _deriveKey(String password, List<int> salt) {
    final kdf = Pbkdf2(
      macAlgorithm: Hmac.sha256(),
      iterations: 210000,
      bits: 256,
    );
    return kdf.deriveKey(
      secretKey: SecretKey(utf8.encode(password)),
      nonce: salt,
    );
  }

  Uint8List _randomBytes(int length) => Uint8List.fromList(
    List<int>.generate(length, (_) => _random.nextInt(256)),
  );
}

class PngManifestReader {
  const PngManifestReader._();

  static const keyword = 'LangbaiScrambler';
  static const _signature = <int>[137, 80, 78, 71, 13, 10, 26, 10];

  static String? read(Uint8List bytes) {
    if (bytes.length < 20) return null;
    for (var index = 0; index < _signature.length; index++) {
      if (bytes[index] != _signature[index]) return null;
    }
    final data = ByteData.sublistView(bytes);
    var offset = 8;
    while (offset + 12 <= bytes.length) {
      final length = data.getUint32(offset, Endian.big);
      if (length < 0 || offset + 12 + length > bytes.length) return null;
      final type = ascii.decode(bytes.sublist(offset + 4, offset + 8));
      if (type == 'tEXt') {
        final payload = bytes.sublist(offset + 8, offset + 8 + length);
        final separator = payload.indexOf(0);
        if (separator > 0) {
          final key = latin1.decode(payload.sublist(0, separator));
          if (key == keyword) {
            return latin1.decode(payload.sublist(separator + 1));
          }
        }
      }
      if (type == 'IEND') break;
      offset += length + 12;
    }
    return null;
  }
}

class ManifestException implements Exception {
  const ManifestException(this.message);
  final String message;

  @override
  String toString() => message;
}

class PasswordRequiredException extends ManifestException {
  const PasswordRequiredException() : super('此混淆图受密码保护');
}

class InvalidPasswordException extends ManifestException {
  const InvalidPasswordException() : super('密码不正确');
}

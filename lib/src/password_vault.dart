import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class PasswordProfile {
  const PasswordProfile({
    required this.id,
    required this.name,
    required this.password,
  });

  final String id;
  final String name;
  final String password;

  Map<String, String> toJson() => {
    'id': id,
    'name': name,
    'password': password,
  };

  factory PasswordProfile.fromJson(Map<String, dynamic> json) =>
      PasswordProfile(
        id: json['id'] as String? ?? '',
        name: json['name'] as String? ?? '',
        password: json['password'] as String? ?? '',
      );
}

abstract interface class PasswordStorage {
  Future<String?> read(String key);
  Future<void> write(String key, String? value);
}

class SecurePasswordStorage implements PasswordStorage {
  const SecurePasswordStorage([this.storage = const FlutterSecureStorage()]);

  final FlutterSecureStorage storage;

  @override
  Future<String?> read(String key) => storage.read(key: key);

  @override
  Future<void> write(String key, String? value) =>
      storage.write(key: key, value: value);
}

class PasswordVault extends ChangeNotifier {
  PasswordVault._(this._storage, this._profiles);

  static const storageKey = 'langbai.archive_password_profiles.v1';
  final PasswordStorage _storage;
  final List<PasswordProfile> _profiles;

  List<PasswordProfile> get profiles => List.unmodifiable(_profiles);

  static Future<PasswordVault> load({PasswordStorage? storage}) async {
    final backend = storage ?? const SecurePasswordStorage();
    final profiles = <PasswordProfile>[];
    try {
      final raw = await backend.read(storageKey);
      if (raw != null && raw.isNotEmpty) {
        for (final item in (jsonDecode(raw) as List<dynamic>)) {
          if (item is! Map) continue;
          final profile = PasswordProfile.fromJson(
            Map<String, dynamic>.from(item),
          );
          if (profile.id.isNotEmpty &&
              profile.name.isNotEmpty &&
              profile.password.isNotEmpty) {
            profiles.add(profile);
          }
        }
      }
    } catch (_) {
      // A corrupt vault is treated as empty and replaced on the next edit.
    }
    return PasswordVault._(backend, profiles);
  }

  PasswordProfile? find(String? id) {
    if (id == null) return null;
    for (final profile in _profiles) {
      if (profile.id == id) return profile;
    }
    return null;
  }

  Future<PasswordProfile> add({
    required String name,
    required String password,
  }) async {
    final cleanName = _validatedName(name);
    final cleanPassword = _validatedPassword(password);
    final profile = PasswordProfile(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      name: cleanName,
      password: cleanPassword,
    );
    _profiles.add(profile);
    await _save();
    notifyListeners();
    return profile;
  }

  Future<void> update(
    String id, {
    required String name,
    required String password,
  }) async {
    final index = _profiles.indexWhere((item) => item.id == id);
    if (index < 0) return;
    final cleanPassword = _validatedPassword(password);
    _profiles[index] = PasswordProfile(
      id: id,
      name: _validatedName(name, excludingId: id),
      password: cleanPassword,
    );
    await _save();
    notifyListeners();
  }

  Future<void> delete(String id) async {
    _profiles.removeWhere((item) => item.id == id);
    await _save();
    notifyListeners();
  }

  String _validatedName(String value, {String? excludingId}) {
    final name = value.trim();
    if (name.isEmpty) throw ArgumentError('名称不能为空');
    if (_profiles.any(
      (item) =>
          item.id != excludingId &&
          item.name.toLowerCase() == name.toLowerCase(),
    )) {
      throw ArgumentError('名称已存在');
    }
    return name;
  }

  String _validatedPassword(String value) {
    if (value.trim().isEmpty) throw ArgumentError('密码不能为空');
    if (value.contains('\r') || value.contains('\n')) {
      throw ArgumentError('密码不能包含换行符');
    }
    return value;
  }

  Future<void> _save() => _storage.write(
    storageKey,
    jsonEncode(_profiles.map((item) => item.toJson()).toList()),
  );
}

class MemoryPasswordStorage implements PasswordStorage {
  final Map<String, String> values = {};

  @override
  Future<String?> read(String key) async => values[key];

  @override
  Future<void> write(String key, String? value) async {
    if (value == null) {
      values.remove(key);
    } else {
      values[key] = value;
    }
  }
}

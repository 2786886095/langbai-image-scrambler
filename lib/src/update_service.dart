import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as path;
import 'package:url_launcher/url_launcher.dart';

import 'app_version.dart';

enum UpdatePlatform { windows, android }

enum UpdateStage { downloading, verifying, installing }

class UpdateProgress {
  const UpdateProgress({
    required this.stage,
    this.receivedBytes = 0,
    this.totalBytes,
  });

  final UpdateStage stage;
  final int receivedBytes;
  final int? totalBytes;

  double? get fraction {
    final total = totalBytes;
    if (total == null || total <= 0) return null;
    return (receivedBytes / total).clamp(0, 1);
  }
}

class UpdateInfo {
  const UpdateInfo({
    required this.currentVersion,
    required this.latestVersion,
    required this.releaseUrl,
    required this.downloadUrl,
    required this.assetName,
    required this.releaseNotes,
    this.sha256Digest,
    this.checksumUrl,
  });

  final String currentVersion;
  final String latestVersion;
  final Uri releaseUrl;
  final Uri downloadUrl;
  final String assetName;
  final String releaseNotes;
  final String? sha256Digest;
  final Uri? checksumUrl;
}

typedef UpdateInstaller = Future<void> Function(File package);
typedef WindowsUpdateLauncher =
    Future<int> Function(String helperPath, List<String> arguments);

class UpdateService {
  UpdateService({
    http.Client? client,
    UpdatePlatform? platform,
    this.installerOverride,
    this.windowsLauncherOverride,
    MethodChannel? channel,
  }) : _client = client ?? http.Client(),
       _platform =
           platform ??
           (Platform.isAndroid
               ? UpdatePlatform.android
               : UpdatePlatform.windows),
       _channel =
           channel ?? const MethodChannel('com.langbai.imagescrambler/saf');

  static const repository = '2786886095/langbai-image-scrambler';
  static final projectUrl = Uri.parse('https://github.com/$repository');

  final http.Client _client;
  final UpdatePlatform _platform;
  final UpdateInstaller? installerOverride;
  final WindowsUpdateLauncher? windowsLauncherOverride;
  final MethodChannel _channel;

  static const _headers = {
    'Accept': 'application/vnd.github+json',
    'X-GitHub-Api-Version': '2022-11-28',
    'User-Agent': 'Langbai-Image-Scrambler-Updater',
  };

  Future<UpdateInfo?> check() async {
    final response = await _client
        .get(
          Uri.parse('https://api.github.com/repos/$repository/releases/latest'),
          headers: _headers,
        )
        .timeout(const Duration(seconds: 15));
    if (response.statusCode == 404) return null;
    if (response.statusCode != 200) {
      throw UpdateException('GitHub API ${response.statusCode}');
    }
    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final latest = (data['tag_name'] as String? ?? '').replaceFirst('v', '');
    if (latest.isEmpty || _compareVersions(latest, AppVersion.current) <= 0) {
      return null;
    }
    final assets = (data['assets'] as List<dynamic>? ?? const [])
        .whereType<Map<String, dynamic>>()
        .toList(growable: false);
    final preferred = assets.where(_isPlatformPackage).toList(growable: false);
    if (preferred.isEmpty) {
      throw const UpdateException('新版本缺少当前平台安装包');
    }
    final asset = preferred.first;
    final assetName = asset['name'] as String? ?? '';
    final downloadUrl = asset['browser_download_url'] as String?;
    if (assetName.isEmpty || downloadUrl == null || downloadUrl.isEmpty) {
      throw const UpdateException('新版本安装包信息不完整');
    }
    final digest = _normalizeDigest(asset['digest'] as String?);
    final checksumAsset = assets.where(
      (item) =>
          (item['name'] as String? ?? '').toUpperCase() == 'SHA256SUMS.TXT',
    );
    final checksumDownload = checksumAsset.isEmpty
        ? null
        : checksumAsset.first['browser_download_url'] as String?;
    return UpdateInfo(
      currentVersion: AppVersion.current,
      latestVersion: latest,
      releaseUrl: Uri.parse(data['html_url'] as String),
      downloadUrl: Uri.parse(downloadUrl),
      assetName: assetName,
      releaseNotes: data['body'] as String? ?? '',
      sha256Digest: digest,
      checksumUrl: checksumDownload == null
          ? null
          : Uri.parse(checksumDownload),
    );
  }

  Future<void> downloadAndInstall(
    UpdateInfo info, {
    void Function(UpdateProgress progress)? onProgress,
  }) async {
    final root = await Directory.systemTemp.createTemp('langbai-update-');
    final safeName = path
        .basename(info.assetName)
        .replaceAll(RegExp(r'[<>:"/\\|?*\x00-\x1f]'), '_');
    final package = File(path.join(root.path, safeName));
    try {
      final request = http.Request('GET', info.downloadUrl)
        ..headers.addAll(_headers);
      final response = await _client
          .send(request)
          .timeout(const Duration(seconds: 20));
      if (response.statusCode != 200) {
        throw UpdateException('下载安装包失败：HTTP ${response.statusCode}');
      }
      final total = response.contentLength;
      var received = 0;
      final sink = package.openWrite();
      try {
        await for (final chunk in response.stream) {
          sink.add(chunk);
          received += chunk.length;
          onProgress?.call(
            UpdateProgress(
              stage: UpdateStage.downloading,
              receivedBytes: received,
              totalBytes: total,
            ),
          );
        }
      } finally {
        await sink.close();
      }
      if (!await package.exists() || await package.length() == 0) {
        throw const UpdateException('下载的安装包为空');
      }

      onProgress?.call(const UpdateProgress(stage: UpdateStage.verifying));
      final expected =
          info.sha256Digest ??
          await _checksumFromManifest(info, asset: safeName);
      if (expected == null) {
        throw const UpdateException('发布页缺少安装包 SHA-256 校验值');
      }
      final actual = (await sha256.bind(package.openRead()).first).toString();
      if (actual.toLowerCase() != expected.toLowerCase()) {
        throw const UpdateException('安装包校验失败，请重新下载');
      }

      onProgress?.call(const UpdateProgress(stage: UpdateStage.installing));
      final installer = installerOverride;
      if (installer != null) {
        await installer(package);
      } else if (_platform == UpdatePlatform.android) {
        await _installAndroid(package);
      } else {
        await _installWindows(package);
      }
    } catch (_) {
      try {
        if (await root.exists()) await root.delete(recursive: true);
      } catch (_) {}
      rethrow;
    }
  }

  Future<void> openProjectPage() async {
    final opened = await launchUrl(
      projectUrl,
      mode: LaunchMode.externalApplication,
    );
    if (!opened) throw const UpdateException('打开 GitHub 项目主页失败');
  }

  Future<String?> _checksumFromManifest(
    UpdateInfo info, {
    required String asset,
  }) async {
    final url = info.checksumUrl;
    if (url == null) return null;
    final response = await _client
        .get(url, headers: _headers)
        .timeout(const Duration(seconds: 12));
    if (response.statusCode != 200) return null;
    for (final line in const LineSplitter().convert(response.body)) {
      final match = RegExp(
        r'^([0-9a-fA-F]{64})\s+\*?(.+)$',
      ).firstMatch(line.trim());
      if (match != null && match.group(2)!.trim() == asset) {
        return match.group(1)!.toLowerCase();
      }
    }
    return null;
  }

  Future<void> _installAndroid(File package) async {
    final started = await _channel.invokeMethod<bool>('installApk', {
      'path': package.path,
    });
    if (started != true) {
      throw const UpdateException('需要允许安装此来源的应用后继续更新');
    }
  }

  Future<void> _installWindows(File package) async {
    final currentExe = Platform.resolvedExecutable;
    final installDir = path.dirname(currentExe);
    final helperSource = File(
      path.join(installDir, 'langbai_update_helper.exe'),
    );
    if (!await helperSource.exists()) {
      await _launchLegacyWindowsInstaller(package, installDir: installDir);
      return;
    }
    final helper = File(
      path.join(package.parent.path, path.basename(helperSource.path)),
    );
    await helperSource.copy(helper.path);
    final logDirectory = await _windowsLogDirectory(package.parent.path);
    final log = File(path.join(logDirectory.path, 'update.log'));
    final ready = File(path.join(package.parent.path, 'helper.ready'));
    final arguments = [
      package.path,
      pid.toString(),
      installDir,
      currentExe,
      log.path,
      ready.path,
    ];
    final launcher = windowsLauncherOverride;
    final helperPid = launcher == null
        ? (await Process.start(
            helper.path,
            arguments,
            mode: ProcessStartMode.detached,
          )).pid
        : await launcher(helper.path, arguments);
    if (helperPid <= 0) {
      throw const UpdateException('启动更新组件失败，请重试');
    }
    final deadline = DateTime.now().add(const Duration(seconds: 5));
    while (!await ready.exists() && DateTime.now().isBefore(deadline)) {
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
    if (!await ready.exists()) {
      throw const UpdateException('更新组件没有响应，请重试');
    }
    if (launcher == null) exit(0);
  }

  Future<void> _launchLegacyWindowsInstaller(
    File package, {
    required String installDir,
  }) async {
    // Builds up to v1.2.4 do not contain the native helper. Keep the first
    // fixed update actionable by opening Setup visibly instead of using the
    // former detached PowerShell hand-off that could disappear silently.
    final logDirectory = await _windowsLogDirectory(package.parent.path);
    final arguments = [
      '/VERYSILENT',
      '/SUPPRESSMSGBOXES',
      '/NORESTART',
      '/CLOSEAPPLICATIONS',
      '/RESTARTAPPLICATIONS',
      '/LOG=${path.join(logDirectory.path, 'installer.log')}',
      '/DIR=$installDir',
    ];
    final launcher = windowsLauncherOverride;
    final installerPid = launcher == null
        ? (await Process.start(
            package.path,
            arguments,
            mode: ProcessStartMode.detached,
          )).pid
        : await launcher(package.path, arguments);
    if (installerPid <= 0) {
      throw const UpdateException('启动安装程序失败，请重试');
    }
  }

  Future<Directory> _windowsLogDirectory(String fallbackRoot) async {
    final directory = Directory(
      path.join(
        Platform.environment['LOCALAPPDATA'] ?? fallbackRoot,
        'LangbaiImageScrambler',
        'logs',
      ),
    );
    await directory.create(recursive: true);
    return directory;
  }

  bool _isPlatformPackage(Map<String, dynamic> asset) {
    final name = (asset['name'] as String? ?? '').toLowerCase();
    if (_platform == UpdatePlatform.android) return name.endsWith('.apk');
    return name.endsWith('.exe') && name.contains('setup');
  }

  static String? _normalizeDigest(String? value) {
    if (value == null || value.trim().isEmpty) return null;
    final normalized = value.trim().replaceFirst(
      RegExp(r'^sha256:', caseSensitive: false),
      '',
    );
    return RegExp(r'^[0-9a-fA-F]{64}$').hasMatch(normalized)
        ? normalized.toLowerCase()
        : null;
  }

  int _compareVersions(String left, String right) {
    final a = left.split('.').map((part) => int.tryParse(part) ?? 0).toList();
    final b = right.split('.').map((part) => int.tryParse(part) ?? 0).toList();
    final length = a.length > b.length ? a.length : b.length;
    for (var index = 0; index < length; index++) {
      final av = index < a.length ? a[index] : 0;
      final bv = index < b.length ? b[index] : 0;
      if (av != bv) return av.compareTo(bv);
    }
    return 0;
  }
}

class UpdateException implements Exception {
  const UpdateException(this.message);
  final String message;

  @override
  String toString() => message;
}

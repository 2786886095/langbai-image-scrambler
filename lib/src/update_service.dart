import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';

import 'app_version.dart';

class UpdateInfo {
  const UpdateInfo({
    required this.currentVersion,
    required this.latestVersion,
    required this.releaseUrl,
    required this.downloadUrl,
    required this.releaseNotes,
  });

  final String currentVersion;
  final String latestVersion;
  final Uri releaseUrl;
  final Uri downloadUrl;
  final String releaseNotes;
}

class UpdateService {
  static const repository = '2786886095/langbai-image-scrambler';

  Future<UpdateInfo?> check() async {
    final response = await http
        .get(
          Uri.parse('https://api.github.com/repos/$repository/releases/latest'),
          headers: const {
            'Accept': 'application/vnd.github+json',
            'X-GitHub-Api-Version': '2022-11-28',
          },
        )
        .timeout(const Duration(seconds: 12));
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
        .cast<Map<String, dynamic>>();
    final preferredExtension = Platform.isAndroid ? '.apk' : '.exe';
    final preferred = assets.where(
      (asset) => (asset['name'] as String? ?? '').toLowerCase().endsWith(
        preferredExtension,
      ),
    );
    final download = preferred.isNotEmpty
        ? preferred.first['browser_download_url'] as String
        : data['html_url'] as String;
    return UpdateInfo(
      currentVersion: AppVersion.current,
      latestVersion: latest,
      releaseUrl: Uri.parse(data['html_url'] as String),
      downloadUrl: Uri.parse(download),
      releaseNotes: data['body'] as String? ?? '',
    );
  }

  Future<void> open(UpdateInfo info) async {
    final opened = await launchUrl(
      info.downloadUrl,
      mode: LaunchMode.externalApplication,
    );
    if (!opened) {
      await launchUrl(info.releaseUrl, mode: LaunchMode.externalApplication);
    }
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
}

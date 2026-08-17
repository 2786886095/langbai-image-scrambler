import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as path;

import 'video_models.dart';

typedef LinkProgressCallback = void Function(double progress, String stage);

class VideoLinkResolver {
  VideoLinkResolver({http.Client? client}) : _client = client ?? http.Client();

  static const defaultApiUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://127.0.0.1:8787',
  );

  final http.Client _client;
  static const _channel = MethodChannel('com.langbai.imagescrambler/saf');

  Future<String> resolveAndDownload(
    String source, {
    String? netscapeCookies,
    LinkProgressCallback? onProgress,
  }) async {
    final url = _extractUrl(source);
    final uri = Uri.tryParse(url);
    if (uri == null ||
        !uri.hasAuthority ||
        !{'http', 'https'}.contains(uri.scheme)) {
      throw const VideoProcessException('请输入有效的视频链接');
    }
    final extension = path.extension(uri.path).toLowerCase();
    if (const {'.mp4', '.mkv', '.webm', '.mov', '.m4v'}.contains(extension)) {
      return _download(uri, path.basename(uri.path), onProgress: onProgress);
    }
    if (!kIsWeb && Platform.isAndroid) {
      onProgress?.call(.05, '正在使用手机本地解析引擎');
      final result = await _channel.invokeMapMethod<String, dynamic>(
        'resolveVideoLink',
        {'url': url, 'cookies': netscapeCookies ?? ''},
      );
      final resolvedPath = result?['path']?.toString();
      if (resolvedPath == null || resolvedPath.isEmpty) {
        throw const VideoProcessException('手机解析器没有返回视频文件');
      }
      onProgress?.call(1, '视频解析下载完成');
      return resolvedPath;
    }
    if (!kIsWeb && Platform.isWindows) {
      return _resolveWindows(
        url,
        netscapeCookies: netscapeCookies,
        onProgress: onProgress,
      );
    }
    onProgress?.call(.04, '正在调用 Langbai 解析引擎');
    final resolveResponse = await _client
        .post(
          Uri.parse('$defaultApiUrl/api/v1/resolve'),
          headers: const {'content-type': 'application/json'},
          body: jsonEncode({'url': url}),
        )
        .timeout(const Duration(seconds: 75));
    final media = _json(resolveResponse, '解析链接失败');
    final options = (media['options'] as List<dynamic>? ?? const [])
        .whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item))
        .where((item) => item['kind'] == 'video')
        .toList();
    if (options.isEmpty) throw const VideoProcessException('解析结果中没有可下载的视频');
    options.sort((a, b) {
      final left = (a['filesize'] as num?)?.toInt() ?? 0;
      final right = (b['filesize'] as num?)?.toInt() ?? 0;
      return right.compareTo(left);
    });
    final selected = options.first;
    onProgress?.call(.12, '已解析，正在创建下载任务');
    final createResponse = await _client
        .post(
          Uri.parse('$defaultApiUrl/api/v1/jobs'),
          headers: const {'content-type': 'application/json'},
          body: jsonEncode({
            'media_id': media['media_id'],
            'option_id': selected['id'],
          }),
        )
        .timeout(const Duration(seconds: 20));
    var job = _json(createResponse, '创建下载任务失败');
    for (var attempt = 0; attempt < 720; attempt++) {
      final state = job['state']?.toString();
      final progress = ((job['progress'] as num?)?.toDouble() ?? 0).clamp(
        0,
        100,
      );
      onProgress?.call(
        .15 + .6 * progress / 100,
        '解析视频下载中 ${progress.toStringAsFixed(0)}%',
      );
      if (state == 'completed') break;
      if (state == 'failed' || state == 'cancelled') {
        throw VideoProcessException(job['error']?.toString() ?? '解析视频下载失败');
      }
      await Future<void>.delayed(const Duration(milliseconds: 750));
      final poll = await _client
          .get(Uri.parse('$defaultApiUrl/api/v1/jobs/${job['id']}'))
          .timeout(const Duration(seconds: 20));
      job = _json(poll, '读取下载进度失败');
    }
    if (job['state'] != 'completed') {
      throw const VideoProcessException('解析视频下载超时');
    }
    final filename =
        job['filename']?.toString() ?? '${media['title'] ?? 'video'}.mp4';
    return _download(
      Uri.parse('$defaultApiUrl/api/v1/jobs/${job['id']}/file'),
      filename,
      onProgress: (value, stage) => onProgress?.call(.75 + value * .25, stage),
    );
  }

  Future<String> _resolveWindows(
    String url, {
    String? netscapeCookies,
    LinkProgressCallback? onProgress,
  }) async {
    final binary = _windowsYtDlpPath();
    if (!await File(binary).exists()) {
      throw const VideoProcessException('Windows 视频解析引擎缺失，请重新安装软件');
    }
    final directory = await Directory.systemTemp.createTemp(
      'langbai-video-resolver-',
    );
    final cookieFile = File(path.join(directory.path, 'cookies.txt'));
    if (netscapeCookies != null && netscapeCookies.trim().isNotEmpty) {
      await cookieFile.writeAsString(netscapeCookies, flush: true);
    }
    onProgress?.call(.05, '正在使用本地账号会话解析视频');
    final arguments = <String>[
      '--no-playlist',
      '--no-mtime',
      '--newline',
      '--concurrent-fragments',
      '8',
      '--retries',
      '4',
      '--socket-timeout',
      '30',
      '--max-filesize',
      '${8 * 1024 * 1024 * 1024}',
      if (await cookieFile.exists()) ...['--cookies', cookieFile.path],
      '-f',
      'bestvideo*+bestaudio/best',
      '--merge-output-format',
      'mp4',
      '-o',
      path.join(directory.path, '%(title).120B.%(ext)s'),
      url,
    ];
    final process = await Process.start(
      binary,
      arguments,
      runInShell: false,
      mode: ProcessStartMode.normal,
    );
    final output = StringBuffer();
    var reported = .08;
    final streams = [process.stdout, process.stderr].map(
      (stream) => stream
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .forEach((line) {
            output.writeln(line);
            final match = RegExp(r'\[download\]\s+([0-9.]+)%').firstMatch(line);
            final percent = double.tryParse(match?.group(1) ?? '');
            if (percent != null) {
              reported = (.08 + percent / 100 * .86).clamp(.08, .94);
              onProgress?.call(
                reported,
                '账号视频解析下载中 ${percent.toStringAsFixed(0)}%',
              );
            }
          }),
    );
    final exitCode = await process.exitCode;
    await Future.wait(streams);
    if (await cookieFile.exists()) await cookieFile.delete();
    if (exitCode != 0) {
      final useful = output
          .toString()
          .split(RegExp(r'[\r\n]+'))
          .where((line) => line.trim().isNotEmpty)
          .toList();
      throw VideoProcessException(
        useful.isEmpty ? '视频解析失败' : '视频解析失败：${useful.last}',
      );
    }
    final candidates = await directory
        .list()
        .where((entry) => entry is File)
        .cast<File>()
        .where(
          (file) => const {
            '.mp4',
            '.mkv',
            '.webm',
            '.mov',
            '.m4v',
            '.avi',
          }.contains(path.extension(file.path).toLowerCase()),
        )
        .toList();
    if (candidates.isEmpty) {
      throw const VideoProcessException('解析完成但没有找到可处理的视频文件');
    }
    candidates.sort(
      (left, right) =>
          right.lastModifiedSync().compareTo(left.lastModifiedSync()),
    );
    onProgress?.call(1, '视频解析下载完成');
    return candidates.first.path;
  }

  String _windowsYtDlpPath() {
    final release = path.join(
      path.dirname(Platform.resolvedExecutable),
      'data',
      'video',
      'yt-dlp.exe',
    );
    if (File(release).existsSync()) return release;
    return path.join(
      Directory.current.path,
      'assets',
      'bin',
      'windows',
      'yt-dlp.exe',
    );
  }

  Future<String> _download(
    Uri uri,
    String filename, {
    LinkProgressCallback? onProgress,
  }) async {
    final request = http.Request('GET', uri);
    final response = await _client
        .send(request)
        .timeout(const Duration(seconds: 45));
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw VideoProcessException('视频下载失败（${response.statusCode}）');
    }
    final safeName = filename.replaceAll(RegExp(r'[<>:"/\\|?*]'), '_');
    final directory = await Directory.systemTemp.createTemp(
      'langbai-resolved-',
    );
    final file = File(
      path.join(directory.path, safeName.isEmpty ? 'video.mp4' : safeName),
    );
    final sink = file.openWrite();
    var received = 0;
    try {
      await for (final chunk in response.stream) {
        sink.add(chunk);
        received += chunk.length;
        final total = response.contentLength;
        onProgress?.call(
          total == null || total == 0 ? 0 : received / total,
          '正在下载解析视频',
        );
      }
      await sink.flush();
      await sink.close();
    } catch (_) {
      await sink.close();
      rethrow;
    }
    return file.path;
  }

  Map<String, dynamic> _json(http.Response response, String fallback) {
    try {
      final data =
          jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
      if (response.statusCode >= 200 && response.statusCode < 300) return data;
      final detail = data['detail'];
      throw VideoProcessException(
        detail is Map
            ? detail['message']?.toString() ?? fallback
            : detail?.toString() ?? fallback,
      );
    } on VideoProcessException {
      rethrow;
    } catch (_) {
      throw VideoProcessException('$fallback（${response.statusCode}）');
    }
  }

  String _extractUrl(String text) {
    final match = RegExp(
      r'''https?://[^\s<>"']+''',
      caseSensitive: false,
    ).firstMatch(text.trim());
    return match?.group(0)?.replaceFirst(RegExp(r'[\)\]}>，。！？；：、]+$'), '') ??
        text.trim();
  }
}

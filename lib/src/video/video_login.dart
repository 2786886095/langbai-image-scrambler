import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path/path.dart' as path;

enum VideoLoginProvider { bilibili, douyin }

extension VideoLoginProviderX on VideoLoginProvider {
  String get id => this == VideoLoginProvider.bilibili ? 'bilibili' : 'douyin';
  String get title => this == VideoLoginProvider.bilibili ? 'B站' : '抖音';
  String get loginUrl => this == VideoLoginProvider.bilibili
      ? 'https://passport.bilibili.com/login'
      : 'https://www.douyin.com/';
  List<String> get cookieUrls => this == VideoLoginProvider.bilibili
      ? const ['https://www.bilibili.com/', 'https://passport.bilibili.com/']
      : const ['https://www.douyin.com/', 'https://passport.douyin.com/'];
  Set<String> get loginCookieNames => this == VideoLoginProvider.bilibili
      ? const {'SESSDATA', 'DedeUserID'}
      : const {'sessionid', 'sessionid_ss'};
}

class VideoLoginStore {
  const VideoLoginStore({FlutterSecureStorage? storage})
    : _storage = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _storage;

  String _key(VideoLoginProvider provider) =>
      'langbai.video_login.${provider.id}.cookies.v1';

  Future<bool> hasSession(VideoLoginProvider provider) async {
    try {
      final value = await _storage.read(key: _key(provider));
      return value != null && value.trim().isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  Future<void> save(VideoLoginProvider provider, String netscapeCookies) =>
      _storage.write(key: _key(provider), value: netscapeCookies);

  Future<void> clear(VideoLoginProvider provider) =>
      _storage.delete(key: _key(provider));

  Future<String?> cookiesForSource(String source) async {
    final lower = source.toLowerCase();
    final provider = lower.contains('bilibili.com') || lower.contains('b23.tv')
        ? VideoLoginProvider.bilibili
        : lower.contains('douyin.com')
        ? VideoLoginProvider.douyin
        : null;
    if (provider == null) return null;
    try {
      return await _storage.read(key: _key(provider));
    } catch (_) {
      return null;
    }
  }
}

Future<bool?> showVideoLoginDialog({
  required BuildContext context,
  required VideoLoginProvider provider,
  required bool traditional,
  VideoLoginStore store = const VideoLoginStore(),
}) {
  return showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (_) => _VideoLoginDialog(
      provider: provider,
      traditional: traditional,
      store: store,
    ),
  );
}

class _VideoLoginDialog extends StatefulWidget {
  const _VideoLoginDialog({
    required this.provider,
    required this.traditional,
    required this.store,
  });

  final VideoLoginProvider provider;
  final bool traditional;
  final VideoLoginStore store;

  @override
  State<_VideoLoginDialog> createState() => _VideoLoginDialogState();
}

class _VideoLoginDialogState extends State<_VideoLoginDialog> {
  InAppWebViewController? _controller;
  WebViewEnvironment? _environment;
  bool _initializing = true;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _prepare();
  }

  Future<void> _prepare() async {
    try {
      if (!kIsWeb && Platform.isWindows) {
        final version = await WebViewEnvironment.getAvailableVersion();
        if (version == null) throw StateError('Windows 缺少 WebView2 Runtime');
        final root = path.join(
          Platform.environment['LOCALAPPDATA'] ?? Directory.systemTemp.path,
          'Langbai Image Scrambler',
          'video-login-webview',
        );
        _environment = await WebViewEnvironment.create(
          settings: WebViewEnvironmentSettings(userDataFolder: root),
        );
      }
    } catch (error) {
      _error = error.toString();
    }
    if (mounted) setState(() => _initializing = false);
  }

  @override
  void dispose() {
    _environment?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      insetPadding: const EdgeInsets.all(16),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 980, maxHeight: 760),
        child: SizedBox(
          width: 920,
          height: MediaQuery.sizeOf(context).height * .84,
          child: Column(
            children: [
              ListTile(
                leading: const Icon(Icons.account_circle_outlined),
                title: Text(
                  '${widget.provider.title}${_t('官方账号登录', '官方帳號登入')}',
                  style: const TextStyle(fontWeight: FontWeight.w900),
                ),
                subtitle: Text(
                  _t(
                    '登录页来自官方网站；软件只保存解析所需 Cookie，不保存账号密码。',
                    '登入頁來自官方網站；軟體只儲存解析所需 Cookie，不儲存帳號密碼。',
                  ),
                ),
                trailing: IconButton(
                  tooltip: _t('关闭', '關閉'),
                  onPressed: _saving ? null : () => Navigator.pop(context),
                  icon: const Icon(Icons.close_rounded),
                ),
              ),
              const Divider(height: 1),
              Expanded(
                child: _initializing
                    ? const Center(child: CircularProgressIndicator())
                    : _error != null
                    ? Center(child: Text(_error!))
                    : InAppWebView(
                        webViewEnvironment: _environment,
                        initialUrlRequest: URLRequest(
                          url: WebUri(widget.provider.loginUrl),
                        ),
                        initialSettings: InAppWebViewSettings(
                          javaScriptEnabled: true,
                          thirdPartyCookiesEnabled: true,
                          supportZoom: true,
                          useShouldOverrideUrlLoading: true,
                        ),
                        onWebViewCreated: (controller) =>
                            _controller = controller,
                      ),
              ),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
                  child: Text(
                    _error!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ),
              Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    TextButton(
                      onPressed: _saving ? null : _clear,
                      child: Text(_t('清除该账号登录', '清除該帳號登入')),
                    ),
                    const Spacer(),
                    FilledButton.icon(
                      onPressed: _saving || _controller == null ? null : _save,
                      icon: _saving
                          ? const SizedBox.square(
                              dimension: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.save_rounded),
                      label: Text(_t('登录完成并保存', '登入完成並儲存')),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _save() async {
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final manager = CookieManager.instance(webViewEnvironment: _environment);
      final cookies = <String, Cookie>{};
      for (final rawUrl in widget.provider.cookieUrls) {
        final uri = Uri.parse(rawUrl);
        for (final cookie in await manager.getCookies(
          url: WebUri(rawUrl),
          webViewController: _controller,
        )) {
          final domain = cookie.domain?.trim().isNotEmpty == true
              ? cookie.domain!
              : uri.host;
          cookies['$domain\t${cookie.path ?? '/'}\t${cookie.name}'] = cookie;
        }
      }
      final names = cookies.values.map((cookie) => cookie.name).toSet();
      if (!names.any(widget.provider.loginCookieNames.contains)) {
        throw StateError(_t('尚未检测到已登录账号，请先完成登录。', '尚未偵測到已登入帳號，請先完成登入。'));
      }
      final lines = <String>['# Netscape HTTP Cookie File'];
      for (final entry in cookies.entries) {
        final parts = entry.key.split('\t');
        final cookie = entry.value;
        final domain = parts[0];
        final includeSubdomains = domain.startsWith('.') ? 'TRUE' : 'FALSE';
        final expires = ((cookie.expiresDate ?? 0) ~/ 1000).toString();
        lines.add(
          [
            cookie.isHttpOnly == true ? '#HttpOnly_$domain' : domain,
            includeSubdomains,
            cookie.path ?? '/',
            cookie.isSecure == true ? 'TRUE' : 'FALSE',
            expires,
            cookie.name,
            cookie.value?.toString() ?? '',
          ].join('\t'),
        );
      }
      await widget.store.save(widget.provider, '${lines.join('\n')}\n');
      if (mounted) Navigator.pop(context, true);
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _clear() async {
    await widget.store.clear(widget.provider);
    final manager = CookieManager.instance(webViewEnvironment: _environment);
    for (final rawUrl in widget.provider.cookieUrls) {
      await manager.deleteCookies(url: WebUri(rawUrl));
    }
    if (mounted) Navigator.pop(context, false);
  }

  String _t(String simplified, String traditional) =>
      widget.traditional ? traditional : simplified;
}

import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as path;
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../app_controller.dart';
import '../export_history.dart';
import '../fun_tools/tool_file_io.dart';
import '../models.dart';
import 'video_link_resolver.dart';
import 'video_models.dart';
import 'video_processor.dart';

class VideoScreen extends StatefulWidget {
  const VideoScreen({super.key, this.traditional = false});

  final bool traditional;

  @override
  State<VideoScreen> createState() => _VideoScreenState();
}

class _VideoScreenState extends State<VideoScreen> {
  final _processor = VideoProcessor();
  final _resolver = VideoLinkResolver();
  final _fileIo = const ToolFileIo();
  final _linkController = TextEditingController();
  final _passwordController = TextEditingController();
  final _seedController = TextEditingController();
  bool _restore = false;
  VideoAlgorithm _scrambleAlgorithm = VideoAlgorithm.gilbert;
  VideoAlgorithm _restoreAlgorithm = VideoAlgorithm.auto;
  VideoAudioMode _scrambleAudioMode = VideoAudioMode.keep;
  VideoAudioMode _restoreAudioMode = VideoAudioMode.keep;
  bool _passwordEnabled = false;
  bool _obscurePassword = true;
  String? _inputPath;
  String? _inputName;
  String? _cachedOutputPath;
  String? _cachedOutputName;
  String? _lastSavedLocation;
  bool _working = false;
  double _progress = 0;
  String _stage = '准备就绪';
  String? _message;
  bool _error = false;
  VideoInspection? _inspection;

  @override
  void initState() {
    super.initState();
    _restoreSettings();
  }

  @override
  void dispose() {
    _linkController.dispose();
    _passwordController.dispose();
    _seedController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SafeArea(
      top: false,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final desktop = constraints.maxWidth >= 980;
          return SingleChildScrollView(
            padding: EdgeInsets.fromLTRB(
              desktop ? 36 : 16,
              desktop ? 30 : 16,
              desktop ? 36 : 16,
              96,
            ),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1240),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      _restore
                          ? _t('自动识别并还原视频', '自動識別並還原影片')
                          : _t('生成可播放的混淆视频', '生成可播放的混淆影片'),
                      style: Theme.of(context).textTheme.headlineMedium
                          ?.copyWith(fontWeight: FontWeight.w900),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _t(
                        '本地文件可通过内嵌原始数据精确恢复并校验 SHA-256；平台压缩版本会使用逐帧算法近似还原。',
                        '本機檔案可透過內嵌原始資料精確還原並校驗 SHA-256；平台壓縮版本會使用逐幀演算法近似還原。',
                      ),
                      style: TextStyle(
                        height: 1.55,
                        color: scheme.onSurface.withValues(alpha: .67),
                      ),
                    ),
                    const SizedBox(height: 20),
                    SegmentedButton<bool>(
                      segments: [
                        ButtonSegment(
                          value: false,
                          icon: const Icon(Icons.video_settings_outlined),
                          label: Text(_t('视频混淆', '影片混淆')),
                        ),
                        ButtonSegment(
                          value: true,
                          icon: const Icon(
                            Icons.settings_backup_restore_rounded,
                          ),
                          label: Text(_t('一键还原', '一鍵還原')),
                        ),
                      ],
                      selected: {_restore},
                      showSelectedIcon: false,
                      onSelectionChanged: _working
                          ? null
                          : (value) => setState(() {
                              _restore = value.first;
                              _inspection = null;
                              _discardCachedOutput();
                              _saveSettings();
                            }),
                      style: const ButtonStyle(
                        minimumSize: WidgetStatePropertyAll(Size(150, 50)),
                      ),
                    ),
                    const SizedBox(height: 16),
                    if (desktop)
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(flex: 4, child: _sourceCard()),
                          const SizedBox(width: 18),
                          Expanded(flex: 5, child: _settingsCard()),
                        ],
                      )
                    else ...[
                      _sourceCard(),
                      const SizedBox(height: 14),
                      _settingsCard(),
                    ],
                    const SizedBox(height: 16),
                    _actionCard(),
                    if (_message != null) ...[
                      const SizedBox(height: 14),
                      _messageCard(),
                    ],
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _sourceCard() {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              _t('导入视频', '匯入影片'),
              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 6),
            Text(
              _t('可选择本地视频，也可粘贴解析项目支持的平台链接。', '可選擇本機影片，也可貼上解析項目支援的平台連結。'),
              style: TextStyle(
                fontSize: 12,
                height: 1.5,
                color: scheme.onSurface.withValues(alpha: .62),
              ),
            ),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: _working ? null : _pickVideo,
              icon: const Icon(Icons.video_file_outlined),
              label: Text(_inputName ?? _t('选择本地视频', '選擇本機影片')),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _linkController,
              enabled: !_working,
              minLines: 2,
              maxLines: 3,
              keyboardType: TextInputType.url,
              decoration: InputDecoration(
                labelText: _t('视频链接', '影片連結'),
                hintText: _t('粘贴抖音、B站等分享链接或视频直链', '貼上抖音、B站等分享連結或影片直連'),
                prefixIcon: const Icon(Icons.link_rounded),
              ),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                TextButton.icon(
                  onPressed: _working ? null : _pasteLink,
                  icon: const Icon(Icons.content_paste_rounded),
                  label: Text(_t('粘贴', '貼上')),
                ),
                FilledButton.tonalIcon(
                  onPressed: _working ? null : _resolveLink,
                  icon: const Icon(Icons.cloud_download_outlined),
                  label: Text(_t('解析并导入', '解析並匯入')),
                ),
              ],
            ),
            if (_inspection != null) ...[
              const SizedBox(height: 14),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: scheme.secondary.withValues(alpha: .08),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: scheme.secondary.withValues(alpha: .24),
                  ),
                ),
                child: Text(
                  _inspection!.hasExactPayload
                      ? '已检测到精确还原数据${_inspection!.passwordProtected ? ' · 需要密码' : ''}'
                      : _inspection!.algorithm == VideoAlgorithm.auto
                      ? '未检测到算法标识，处理时需要手动参数'
                      : '已识别 ${_inspection!.algorithm.title}',
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _settingsCard() {
    final scheme = Theme.of(context).colorScheme;
    final exact = _inspection?.hasExactPayload == true;
    final effectiveAlgorithm = exact
        ? _inspection!.algorithm
        : _activeAlgorithm;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              _t('处理设置', '處理設定'),
              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<VideoAlgorithm>(
              key: ValueKey(
                'video-algorithm-${_restore ? 'restore' : 'scramble'}-${effectiveAlgorithm.id}',
              ),
              initialValue: effectiveAlgorithm,
              decoration: InputDecoration(
                labelText: _t('画面算法', '畫面演算法'),
                prefixIcon: const Icon(Icons.grid_view_rounded),
              ),
              items: [
                for (final algorithm in VideoAlgorithm.values.where(
                  (item) => _restore || item != VideoAlgorithm.auto,
                ))
                  DropdownMenuItem(
                    value: algorithm,
                    child: Text(algorithm.titleFor(widget.traditional)),
                  ),
              ],
              onChanged: _working || exact
                  ? null
                  : (value) => setState(() {
                      _activeAlgorithm = value ?? _activeAlgorithm;
                      _saveSettings();
                    }),
            ),
            const SizedBox(height: 8),
            Text(
              effectiveAlgorithm.descriptionFor(widget.traditional),
              style: TextStyle(
                fontSize: 12,
                height: 1.45,
                color: scheme.onSurface.withValues(alpha: .62),
              ),
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<VideoAudioMode>(
              key: ValueKey(
                'video-audio-${_restore ? 'restore' : 'scramble'}-${(exact ? _inspection!.audioMode : _activeAudioMode).id}',
              ),
              initialValue: exact ? _inspection!.audioMode : _activeAudioMode,
              decoration: InputDecoration(
                labelText: _t('音频处理', '音訊處理'),
                prefixIcon: const Icon(Icons.graphic_eq_rounded),
              ),
              items: [
                for (final mode in VideoAudioMode.values)
                  DropdownMenuItem(
                    value: mode,
                    child: Text(mode.titleFor(widget.traditional)),
                  ),
              ],
              onChanged: _working || exact
                  ? null
                  : (value) => setState(() {
                      _activeAudioMode = value ?? _activeAudioMode;
                      _saveSettings();
                    }),
            ),
            if (_restore && !exact) ...[
              const SizedBox(height: 16),
              TextField(
                controller: _seedController,
                enabled: !_working,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: const InputDecoration(
                  labelText: '手动随机种子',
                  hintText: '自动识别失败时填写',
                  prefixIcon: Icon(Icons.numbers_rounded),
                ),
              ),
            ],
            const SizedBox(height: 14),
            SwitchListTile.adaptive(
              contentPadding: EdgeInsets.zero,
              title: Text(
                _t('密码保护', '密碼保護'),
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
              subtitle: Text(_t('加密视频内嵌的精确还原数据', '加密影片內嵌的精確還原資料')),
              value:
                  _passwordEnabled || (_inspection?.passwordProtected ?? false),
              onChanged: _working || exact
                  ? null
                  : (value) => setState(() {
                      _passwordEnabled = value;
                      _saveSettings();
                    }),
            ),
            if (_passwordEnabled ||
                (_inspection?.passwordProtected ?? false)) ...[
              const SizedBox(height: 10),
              TextField(
                controller: _passwordController,
                enabled: !_working,
                obscureText: _obscurePassword,
                decoration: InputDecoration(
                  labelText: _restore ? '还原密码' : '视频密码',
                  prefixIcon: const Icon(Icons.lock_outline_rounded),
                  suffixIcon: IconButton(
                    tooltip: _obscurePassword ? '显示密码' : '隐藏密码',
                    onPressed: () =>
                        setState(() => _obscurePassword = !_obscurePassword),
                    icon: Icon(
                      _obscurePassword
                          ? Icons.visibility_outlined
                          : Icons.visibility_off_outlined,
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _actionCard() {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (_working || _progress > 0) ...[
              Row(
                children: [
                  Expanded(
                    child: Text(
                      _stage,
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                  ),
                  Text(
                    '${(_progress * 100).clamp(0, 100).toStringAsFixed(0)}%',
                  ),
                ],
              ),
              const SizedBox(height: 10),
              LinearProgressIndicator(value: _progress == 0 ? null : _progress),
              const SizedBox(height: 16),
            ],
            FilledButton.icon(
              onPressed: _working || _inputPath == null ? null : _process,
              icon: _working
                  ? const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Icon(
                      _restore
                          ? Icons.settings_backup_restore_rounded
                          : Icons.movie_filter_outlined,
                    ),
              label: Text(
                _working
                    ? _t('正在处理', '正在處理')
                    : _restore
                    ? _t('一键还原并导出', '一鍵還原並匯出')
                    : _t('生成混淆视频并导出', '生成混淆影片並匯出'),
              ),
            ),
            if (_cachedOutputPath != null) ...[
              const SizedBox(height: 10),
              OutlinedButton.icon(
                onPressed: _working ? null : _exportCached,
                icon: const Icon(Icons.save_alt_rounded),
                label: Text(_t('继续导出已生成结果', '繼續匯出已生成結果')),
              ),
            ],
            if (_lastSavedLocation != null) ...[
              const SizedBox(height: 10),
              OutlinedButton.icon(
                onPressed: _working
                    ? null
                    : () => _fileIo.openSavedLocation(_lastSavedLocation!),
                icon: const Icon(Icons.folder_open_rounded),
                label: Text(_t('打开导出位置', '開啟匯出位置')),
              ),
            ],
            const SizedBox(height: 10),
            Text(
              '提示：逐帧处理需要临时磁盘空间。本地文件可精确还原；平台重新编码会删除内嵌数据，只能近似还原。',
              style: TextStyle(
                fontSize: 11.5,
                height: 1.5,
                color: scheme.onSurface.withValues(alpha: .58),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _messageCard() {
    final scheme = Theme.of(context).colorScheme;
    final color = _error ? scheme.error : scheme.secondary;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: .25)),
      ),
      child: Row(
        children: [
          Icon(
            _error
                ? Icons.error_outline_rounded
                : Icons.check_circle_outline_rounded,
            color: color,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              _message!,
              style: const TextStyle(height: 1.45, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _pickVideo() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['mp4', 'mkv', 'webm', 'mov', 'm4v', 'avi'],
      allowMultiple: false,
      withReadStream: Platform.isAndroid,
    );
    final selected = result?.files.singleOrNull;
    if (selected == null) return;
    var selectedPath = selected.path;
    if (selectedPath == null && selected.readStream != null) {
      final imported = File(
        path.join(
          Directory.systemTemp.path,
          'langbai-video-import-${DateTime.now().microsecondsSinceEpoch}-${path.basename(selected.name)}',
        ),
      );
      await imported.parent.create(recursive: true);
      final sink = imported.openWrite();
      try {
        await selected.readStream!.pipe(sink);
      } catch (_) {
        await sink.close();
        if (await imported.exists()) await imported.delete();
        rethrow;
      }
      selectedPath = imported.path;
    }
    if (selectedPath == null) {
      _showError('文件提供器未返回可读取内容，请换用系统“文件”或本机存储后重试');
      return;
    }
    await _setInput(selectedPath, selected.name);
  }

  Future<void> _pasteLink() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text?.trim();
    if (text == null || text.isEmpty) {
      _showError('剪贴板中没有链接');
      return;
    }
    _linkController.text = text;
  }

  Future<void> _resolveLink() async {
    if (_linkController.text.trim().isEmpty) {
      _showError('请先粘贴视频链接');
      return;
    }
    _beginWork('正在解析视频链接');
    try {
      final resolved = await _resolver.resolveAndDownload(
        _linkController.text,
        onProgress: _updateProgress,
      );
      await _setInput(resolved, path.basename(resolved), notify: false);
      _message = '视频解析并下载完成，已自动加入还原流程';
      _error = false;
    } catch (error) {
      _message = error.toString();
      _error = true;
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  Future<void> _setInput(
    String inputPath,
    String name, {
    bool notify = true,
  }) async {
    _discardCachedOutput();
    _inputPath = inputPath;
    _inputName = name;
    _inspection = _restore ? await _processor.inspect(inputPath) : null;
    _message = null;
    _error = false;
    if (notify && mounted) setState(() {});
  }

  Future<void> _process() async {
    final input = _inputPath;
    if (input == null) return;
    if ((_passwordEnabled || (_inspection?.passwordProtected ?? false)) &&
        _passwordController.text.isEmpty) {
      _showError('请输入密码后再开始处理');
      return;
    }
    _beginWork(_restore ? '正在检测视频' : '正在准备视频混淆');
    final temporary = await Directory.systemTemp.createTemp(
      'langbai-video-result-',
    );
    final outputName = _restore && _inspection?.originalName != null
        ? _inspection!.originalName!
        : _inputName ?? 'video.mp4';
    final outputPath = path.join(temporary.path, outputName);
    try {
      final result = _restore
          ? await _processor.restore(
              inputPath: input,
              outputPath: outputPath,
              requestedAlgorithm: _activeAlgorithm,
              requestedAudioMode: _activeAudioMode,
              manualSeed: int.tryParse(_seedController.text),
              password: _passwordController.text,
              onProgress: _updateProgress,
            )
          : await _processor.scramble(
              inputPath: input,
              outputPath: outputPath,
              algorithm: _activeAlgorithm,
              audioMode: _activeAudioMode,
              password: _passwordEnabled ? _passwordController.text : null,
              onProgress: _updateProgress,
            );
      _cachedOutputPath = result.path;
      _cachedOutputName = result.outputName;
      final saved = await _exportCached();
      _message = saved == null
          ? '处理已完成，结果已缓存；点击“继续导出已生成结果”即可选择路径，无需重新处理。'
          : result.exact
          ? '已导出；精确还原数据与 SHA-256 校验均已就绪。'
          : '已导出平台转码近似还原版本。';
      _error = false;
    } catch (error) {
      _message = error.toString();
      _error = true;
      if (await temporary.exists()) await temporary.delete(recursive: true);
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  Future<String?> _exportCached() async {
    final source = _cachedOutputPath;
    final name = _cachedOutputName;
    if (source == null || name == null) return null;
    final saved = await _fileIo.saveSource(
      sourcePath: source,
      suggestedName: name,
      mimeType: 'video/mp4',
    );
    if (saved != null && mounted) {
      final controller = context.read<AppController?>();
      if (controller != null) {
        final file = File(source);
        final digest = await sha256.bind(file.openRead()).first;
        await controller.recordExternalExport(
          kind: _restore
              ? ExportHistoryKind.videoRestore
              : ExportHistoryKind.videoScramble,
          mode: _restore ? ProcessMode.restore : ProcessMode.scramble,
          location: saved,
          displayName: name,
          sha256: digest.toString(),
          sizeBytes: await file.length(),
        );
      }
      setState(() {
        _lastSavedLocation = saved;
        _message = '已导出到 $saved';
        _error = false;
      });
    }
    return saved;
  }

  void _beginWork(String stage) {
    setState(() {
      _working = true;
      _progress = 0;
      _stage = stage;
      _message = null;
      _error = false;
    });
  }

  void _updateProgress(double progress, String stage) {
    if (!mounted) return;
    setState(() {
      _progress = progress.clamp(0, 1);
      _stage = stage;
    });
  }

  void _showError(Object message) {
    if (!mounted) return;
    setState(() {
      _message = message.toString();
      _error = true;
    });
  }

  void _discardCachedOutput() {
    final cached = _cachedOutputPath;
    _cachedOutputPath = null;
    _cachedOutputName = null;
    if (cached != null) {
      final parent = File(cached).parent;
      if (parent.path.contains('langbai-video-result-')) {
        parent.delete(recursive: true).ignore();
      }
    }
  }

  VideoAlgorithm get _activeAlgorithm =>
      _restore ? _restoreAlgorithm : _scrambleAlgorithm;

  set _activeAlgorithm(VideoAlgorithm value) {
    if (_restore) {
      _restoreAlgorithm = value;
    } else {
      _scrambleAlgorithm = value;
    }
  }

  VideoAudioMode get _activeAudioMode =>
      _restore ? _restoreAudioMode : _scrambleAudioMode;

  set _activeAudioMode(VideoAudioMode value) {
    if (_restore) {
      _restoreAudioMode = value;
    } else {
      _scrambleAudioMode = value;
    }
  }

  Future<void> _restoreSettings() async {
    final preferences = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      _restore = preferences.getBool('video_mode_restore') ?? false;
      _scrambleAlgorithm = VideoAlgorithmX.fromId(
        preferences.getString('video_scramble_algorithm') ??
            preferences.getString('video_algorithm'),
      );
      if (_scrambleAlgorithm == VideoAlgorithm.auto) {
        _scrambleAlgorithm = VideoAlgorithm.gilbert;
      }
      _restoreAlgorithm = VideoAlgorithmX.fromId(
        preferences.getString('video_restore_algorithm'),
      );
      _scrambleAudioMode = VideoAudioModeX.fromId(
        preferences.getString('video_scramble_audio_mode') ??
            preferences.getString('video_audio_mode'),
      );
      _restoreAudioMode = VideoAudioModeX.fromId(
        preferences.getString('video_restore_audio_mode'),
      );
      _passwordEnabled = preferences.getBool('video_password_enabled') ?? false;
    });
  }

  Future<void> _saveSettings() async {
    final preferences = await SharedPreferences.getInstance();
    await Future.wait([
      preferences.setBool('video_mode_restore', _restore),
      preferences.setString('video_scramble_algorithm', _scrambleAlgorithm.id),
      preferences.setString('video_restore_algorithm', _restoreAlgorithm.id),
      preferences.setString('video_scramble_audio_mode', _scrambleAudioMode.id),
      preferences.setString('video_restore_audio_mode', _restoreAudioMode.id),
      preferences.setBool('video_password_enabled', _passwordEnabled),
    ]);
  }

  String _t(String simplified, String traditional) =>
      widget.traditional ? traditional : simplified;
}

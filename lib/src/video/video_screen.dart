import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as path;
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../app_controller.dart';
import '../archive_service.dart';
import '../export_history.dart';
import '../file_service.dart';
import '../fun_tools/tool_file_io.dart';
import '../models.dart';
import '../password_vault.dart';
import 'video_link_resolver.dart';
import 'video_login.dart';
import 'video_batch.dart';
import 'video_models.dart';
import 'video_processor.dart';

class VideoScreen extends StatefulWidget {
  const VideoScreen({super.key, this.traditional = false});

  final bool traditional;

  @override
  State<VideoScreen> createState() => _VideoScreenState();
}

class _VideoBatchExportTarget {
  const _VideoBatchExportTarget({
    this.windowsRoots = const {},
    this.androidRoots = const {},
  });

  final Map<String, String> windowsRoots;
  final Map<String, String> androidRoots;
}

class _VideoScreenState extends State<VideoScreen> {
  final _processor = VideoProcessor();
  final _resolver = VideoLinkResolver();
  final _loginStore = const VideoLoginStore();
  final _fileIo = const ToolFileIo();
  final _fileService = FileService();
  final _archiveService = ArchiveService();
  static const _channel = MethodChannel('com.langbai.imagescrambler/saf');
  final _linkController = TextEditingController();
  final _passwordController = TextEditingController();
  final _seedController = TextEditingController();
  bool _restore = false;
  VideoAlgorithm _scrambleAlgorithm = VideoAlgorithm.gilbert;
  VideoAlgorithm _restoreAlgorithm = VideoAlgorithm.auto;
  VideoAudioMode _scrambleAudioMode = VideoAudioMode.keep;
  VideoAudioMode _restoreAudioMode = VideoAudioMode.keep;
  VideoPerformanceMode _scramblePerformance = VideoPerformanceMode.normal;
  VideoPerformanceMode _restorePerformance = VideoPerformanceMode.normal;
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
  final List<VideoBatchInput> _inputs = [];
  bool _compressionEnabled = false;
  CompressionArchiveFormat _compressionFormat = CompressionArchiveFormat.zip;
  CompressionGrouping _compressionGrouping = CompressionGrouping.perFolder;
  String? _archivePasswordProfileId;
  bool _bilibiliLoggedIn = false;
  bool _douyinLoggedIn = false;

  @override
  void initState() {
    super.initState();
    _restoreSettings();
    _refreshLoginStatus();
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
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                OutlinedButton.icon(
                  onPressed: _working ? null : _pickVideo,
                  icon: const Icon(Icons.video_file_outlined),
                  label: Text(_t('选择视频', '選擇影片')),
                ),
                OutlinedButton.icon(
                  onPressed: _working ? null : _pickVideoFolder,
                  icon: const Icon(Icons.create_new_folder_outlined),
                  label: Text(_t('导入文件夹', '匯入資料夾')),
                ),
                if (_inputs.isNotEmpty)
                  TextButton.icon(
                    onPressed: _working ? null : _clearInputs,
                    icon: const Icon(Icons.clear_all_rounded),
                    label: Text(_t('清空', '清空')),
                  ),
              ],
            ),
            if (_inputs.isNotEmpty) ...[
              const SizedBox(height: 12),
              Container(
                decoration: BoxDecoration(
                  color: scheme.primary.withValues(alpha: .07),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: scheme.primary.withValues(alpha: .2),
                  ),
                ),
                child: ExpansionTile(
                  initiallyExpanded: false,
                  leading: const Icon(Icons.video_library_outlined),
                  title: Text(
                    _t(
                      '已导入 ${_inputs.length} 个视频',
                      '已匯入 ${_inputs.length} 個影片',
                    ),
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                  subtitle: Text(
                    _inputs
                            .map((item) => item.sourceRootName)
                            .where((name) => name.isNotEmpty)
                            .toSet()
                            .isEmpty
                        ? (_inputName ?? '')
                        : _t(
                            '${_inputs.map((item) => item.sourceRootId).where((id) => id.isNotEmpty).toSet().length} 个文件夹 · 默认收起',
                            '${_inputs.map((item) => item.sourceRootId).where((id) => id.isNotEmpty).toSet().length} 個資料夾 · 預設收合',
                          ),
                  ),
                  children: [
                    for (final item in _inputs.take(12))
                      ListTile(
                        dense: true,
                        leading: const Icon(Icons.movie_outlined, size: 19),
                        title: Text(item.name),
                        subtitle: item.relativeDirectory.isEmpty
                            ? null
                            : Text(item.relativeDirectory),
                      ),
                    if (_inputs.length > 12)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                        child: Text(
                          _t(
                            '其余 ${_inputs.length - 12} 个视频已折叠',
                            '其餘 ${_inputs.length - 12} 個影片已收合',
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ],
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
            const SizedBox(height: 10),
            Text(
              _t('需要账号的视频', '需要帳號的影片'),
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                _loginButton(VideoLoginProvider.bilibili, _bilibiliLoggedIn),
                _loginButton(VideoLoginProvider.douyin, _douyinLoggedIn),
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
            const SizedBox(height: 16),
            Text(
              _t('性能档位', '效能檔位'),
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 8),
            SegmentedButton<VideoPerformanceMode>(
              segments: [
                ButtonSegment(
                  value: VideoPerformanceMode.normal,
                  icon: const Icon(Icons.balance_rounded),
                  label: Text(_t('普通', '普通')),
                ),
                ButtonSegment(
                  value: VideoPerformanceMode.fullPower,
                  icon: const Icon(Icons.bolt_rounded),
                  label: Text(_t('全功率', '全功率')),
                ),
              ],
              selected: {_activePerformanceMode},
              showSelectedIcon: false,
              expandedInsets: EdgeInsets.zero,
              style: const ButtonStyle(
                minimumSize: WidgetStatePropertyAll(Size(0, 48)),
              ),
              onSelectionChanged: _working
                  ? null
                  : (selection) => setState(() {
                      _activePerformanceMode = selection.first;
                      _saveSettings();
                    }),
            ),
            const SizedBox(height: 8),
            Text(
              _activePerformanceMode.descriptionFor(widget.traditional),
              style: TextStyle(
                fontSize: 12,
                height: 1.45,
                color: scheme.onSurface.withValues(alpha: .62),
              ),
            ),
            if (!_restore) ...[
              const SizedBox(height: 14),
              SwitchListTile.adaptive(
                contentPadding: EdgeInsets.zero,
                title: Text(
                  _t('压缩输出', '壓縮輸出'),
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
                subtitle: Text(_t('与图片混淆一致：导出后只保留压缩包', '與圖片混淆一致：匯出後只保留壓縮檔')),
                value: _compressionEnabled,
                onChanged: _working
                    ? null
                    : (value) => setState(() {
                        _compressionEnabled = value;
                        _saveSettings();
                      }),
              ),
              if (_compressionEnabled) ...[
                const SizedBox(height: 8),
                SegmentedButton<CompressionArchiveFormat>(
                  segments: const [
                    ButtonSegment(
                      value: CompressionArchiveFormat.zip,
                      icon: Icon(Icons.folder_zip_outlined),
                      label: Text('ZIP'),
                    ),
                    ButtonSegment(
                      value: CompressionArchiveFormat.sevenZip,
                      icon: Icon(Icons.archive_outlined),
                      label: Text('7Z'),
                    ),
                  ],
                  selected: {_compressionFormat},
                  showSelectedIcon: false,
                  expandedInsets: EdgeInsets.zero,
                  onSelectionChanged: _working
                      ? null
                      : (selection) => setState(() {
                          _compressionFormat = selection.first;
                          _saveSettings();
                        }),
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final grouping in CompressionGrouping.values)
                      ChoiceChip(
                        selected: _compressionGrouping == grouping,
                        onSelected: _working
                            ? null
                            : (_) => setState(() {
                                _compressionGrouping = grouping;
                                _saveSettings();
                              }),
                        label: Text(switch (grouping) {
                          CompressionGrouping.perFolder => _t('每个文件夹', '每個資料夾'),
                          CompressionGrouping.perFile => _t('每个文件', '每個檔案'),
                          CompressionGrouping.combined => _t(
                            '全部压到一起',
                            '全部壓到一起',
                          ),
                        }),
                      ),
                  ],
                ),
                const SizedBox(height: 10),
                DropdownButtonFormField<String>(
                  initialValue:
                      _archiveProfiles.any(
                        (item) => item.id == _archivePasswordProfileId,
                      )
                      ? _archivePasswordProfileId
                      : '',
                  decoration: InputDecoration(
                    labelText: _t('本次压缩密码', '本次壓縮密碼'),
                    prefixIcon: const Icon(Icons.password_rounded),
                  ),
                  items: [
                    DropdownMenuItem(value: '', child: Text(_t('不加密', '不加密'))),
                    for (final profile in _archiveProfiles)
                      DropdownMenuItem(
                        value: profile.id,
                        child: Text(profile.name),
                      ),
                  ],
                  onChanged: _working
                      ? null
                      : (value) => setState(() {
                          _archivePasswordProfileId = value?.isEmpty == true
                              ? null
                              : value;
                          _saveSettings();
                        }),
                ),
              ],
            ],
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
              onPressed: _working || _inputs.isEmpty ? null : _process,
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
      allowMultiple: true,
      withReadStream: Platform.isAndroid,
    );
    if (result == null || result.files.isEmpty) return;
    final additions = <VideoBatchInput>[];
    final stamp = DateTime.now().microsecondsSinceEpoch;
    for (var index = 0; index < result.files.length; index++) {
      final selected = result.files[index];
      var selectedPath = selected.path;
      if (selectedPath == null && selected.readStream != null) {
        final imported = File(
          path.join(
            Directory.systemTemp.path,
            'langbai-video-import-$stamp-$index-${path.basename(selected.name)}',
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
      if (selectedPath == null) continue;
      additions.add(
        VideoBatchInput(
          id: '$stamp-$index',
          name: selected.name,
          sourcePath: selectedPath,
          sizeBytes: selected.size,
        ),
      );
    }
    if (additions.isEmpty) {
      _showError('文件提供器未返回可读取内容，请换用系统“文件”或本机存储后重试');
      return;
    }
    await _setInputs(additions);
  }

  Future<void> _pickVideoFolder() async {
    final additions = <VideoBatchInput>[];
    final stamp = DateTime.now().microsecondsSinceEpoch;
    if (Platform.isAndroid) {
      final tree = await _channel.invokeMapMethod<String, dynamic>('pickTree');
      if (tree == null) return;
      final treeUri = tree['uri'] as String?;
      final rootName = tree['name'] as String? ?? _t('视频文件夹', '影片資料夾');
      if (treeUri == null) return;
      final listed = await _channel.invokeMapMethod<String, dynamic>(
        'listTree',
        {'treeUri': treeUri},
      );
      final items = listed?['items'] as List<dynamic>? ?? const [];
      for (var index = 0; index < items.length; index++) {
        final item = Map<String, dynamic>.from(items[index] as Map);
        final name = item['name'] as String? ?? '';
        if (!isSupportedVideoName(name)) continue;
        additions.add(
          VideoBatchInput(
            id: '$stamp-$index',
            name: name,
            sourceUri: item['uri'] as String?,
            relativeDirectory: item['relativeDirectory'] as String? ?? '',
            sourceRootName: rootName,
            sourceRootId: treeUri,
            sizeBytes: (item['size'] as num?)?.toInt() ?? 0,
          ),
        );
      }
    } else {
      final selected = await FilePicker.platform.getDirectoryPath(
        dialogTitle: _t('选择视频文件夹', '選擇影片資料夾'),
      );
      if (selected == null) return;
      final root = Directory(selected);
      final rootName = path.basename(root.path);
      var index = 0;
      await for (final entity in root.list(
        recursive: true,
        followLinks: false,
      )) {
        if (entity is! File || !isSupportedVideoName(entity.path)) continue;
        final relative = path.relative(
          path.dirname(entity.path),
          from: root.path,
        );
        additions.add(
          VideoBatchInput(
            id: '$stamp-${index++}',
            name: path.basename(entity.path),
            sourcePath: entity.path,
            relativeDirectory: relative == '.' ? '' : relative,
            sourceRootName: rootName,
            sourceRootId: root.absolute.path,
            sizeBytes: await entity.length(),
          ),
        );
      }
    }
    if (additions.isEmpty) {
      _showError(_t('文件夹中没有支持的视频', '資料夾中沒有支援的影片'));
      return;
    }
    await _setInputs(additions, append: true);
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
        netscapeCookies: await _loginStore.cookiesForSource(
          _linkController.text,
        ),
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

  Widget _loginButton(VideoLoginProvider provider, bool loggedIn) {
    return OutlinedButton.icon(
      onPressed: _working ? null : () => _login(provider),
      icon: Icon(
        loggedIn ? Icons.verified_user_rounded : Icons.login_rounded,
        size: 19,
      ),
      label: Text(
        loggedIn
            ? '${provider.title} · ${_t('已登录', '已登入')}'
            : '${provider.title} · ${_t('登录', '登入')}',
      ),
    );
  }

  Future<void> _login(VideoLoginProvider provider) async {
    await showVideoLoginDialog(
      context: context,
      provider: provider,
      traditional: widget.traditional,
      store: _loginStore,
    );
    await _refreshLoginStatus();
  }

  Future<void> _refreshLoginStatus() async {
    final states = await Future.wait([
      _loginStore.hasSession(VideoLoginProvider.bilibili),
      _loginStore.hasSession(VideoLoginProvider.douyin),
    ]);
    if (!mounted) return;
    setState(() {
      _bilibiliLoggedIn = states[0];
      _douyinLoggedIn = states[1];
    });
  }

  Future<void> _setInput(
    String inputPath,
    String name, {
    bool notify = true,
  }) async {
    await _setInputs([
      VideoBatchInput(
        id: DateTime.now().microsecondsSinceEpoch.toString(),
        name: name,
        sourcePath: inputPath,
        sizeBytes: await File(inputPath).length(),
      ),
    ], notify: notify);
  }

  Future<void> _setInputs(
    List<VideoBatchInput> additions, {
    bool append = false,
    bool notify = true,
  }) async {
    _discardCachedOutput();
    if (!append) _inputs.clear();
    final known = _inputs
        .map((item) => item.sourcePath ?? item.sourceUri)
        .toSet();
    _inputs.addAll(
      additions.where((item) => known.add(item.sourcePath ?? item.sourceUri)),
    );
    final first = _inputs.firstOrNull;
    _inputPath = _inputs.length == 1 ? first?.sourcePath : null;
    _inputName = first?.name;
    _inspection = _restore && _inputPath != null
        ? await _processor.inspect(_inputPath!)
        : null;
    _message = null;
    _error = false;
    if (notify && mounted) setState(() {});
  }

  void _clearInputs() {
    _discardCachedOutput();
    setState(() {
      _inputs.clear();
      _inputPath = null;
      _inputName = null;
      _inspection = null;
      _message = null;
      _error = false;
    });
  }

  Future<void> _process() async {
    final directSingle =
        _inputs.length == 1 &&
        _inputs.single.sourceRootId.isEmpty &&
        !_compressionEnabled;
    if (!directSingle) {
      await _processBatch();
      return;
    }
    await _processSingle();
  }

  Future<void> _processSingle() async {
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
              performanceMode: _activePerformanceMode,
              onProgress: _updateProgress,
            )
          : await _processor.scramble(
              inputPath: input,
              outputPath: outputPath,
              algorithm: _activeAlgorithm,
              audioMode: _activeAudioMode,
              password: _passwordEnabled ? _passwordController.text : null,
              performanceMode: _activePerformanceMode,
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

  Future<void> _processBatch() async {
    if (_inputs.isEmpty) return;
    if ((_passwordEnabled || (_inspection?.passwordProtected ?? false)) &&
        _passwordController.text.isEmpty) {
      _showError('请输入密码后再开始处理');
      return;
    }
    final controller = context.read<AppController>();
    final placeholderOutputs = [
      for (final input in _inputs)
        VideoBatchOutput(input: input, path: '', outputName: input.name),
    ];
    ExportTarget? archiveTarget;
    _VideoBatchExportTarget? videoTarget;
    if (_compressionEnabled && !_restore) {
      final plannedGroups = planVideoArchives(
        outputs: placeholderOutputs,
        grouping: _compressionGrouping,
      );
      archiveTarget = await _fileService.chooseArchiveExportTarget(
        fileNames: [
          for (final group in plannedGroups)
            '${group.baseName}.${_compressionFormat.extension}',
        ],
        settings: controller.settings,
      );
      if (archiveTarget == null) return;
    } else {
      videoTarget = await _chooseVideoBatchExportTarget(controller);
      if (videoTarget == null) return;
    }

    _beginWork(_restore ? '正在批量还原视频' : '正在批量生成混淆视频');
    final root = await Directory.systemTemp.createTemp('langbai-video-batch-');
    final outputs = <VideoBatchOutput>[];
    final copiedInputs = <String>[];
    try {
      for (var index = 0; index < _inputs.length; index++) {
        final item = _inputs[index];
        final inputPath = await _materializeInput(item);
        if (item.sourcePath == null) copiedInputs.add(inputPath);
        final outputPath = path.join(
          root.path,
          '${index.toString().padLeft(6, '0')}-${sanitizeFileName(item.name)}',
        );
        final result = _restore
            ? await _processor.restore(
                inputPath: inputPath,
                outputPath: outputPath,
                requestedAlgorithm: _activeAlgorithm,
                requestedAudioMode: _activeAudioMode,
                manualSeed: int.tryParse(_seedController.text),
                password: _passwordController.text,
                performanceMode: _activePerformanceMode,
                onProgress: (value, stage) => _updateProgress(
                  (index + value * .88) / _inputs.length,
                  '${item.name} · $stage',
                ),
              )
            : await _processor.scramble(
                inputPath: inputPath,
                outputPath: outputPath,
                algorithm: _activeAlgorithm,
                audioMode: _activeAudioMode,
                password: _passwordEnabled ? _passwordController.text : null,
                performanceMode: _activePerformanceMode,
                onProgress: (value, stage) => _updateProgress(
                  (index + value * .88) / _inputs.length,
                  '${item.name} · $stage',
                ),
              );
        outputs.add(
          VideoBatchOutput(
            input: item,
            path: result.path,
            outputName: result.outputName,
          ),
        );
      }

      if (_compressionEnabled && !_restore) {
        _updateProgress(.9, '正在生成视频压缩包');
        final groups = planVideoArchives(
          outputs: outputs,
          grouping: _compressionGrouping,
        );
        final selectedProfile = controller.archivePasswordProfiles
            .where((item) => item.id == _archivePasswordProfileId)
            .firstOrNull;
        final archives = await _archiveService.create(
          groups: groups,
          format: _compressionFormat,
          password: selectedProfile?.password,
        );
        try {
          for (final archive in archives) {
            final saved = await _fileService.savePreparedArchive(
              sourcePath: archive.path,
              fileName: archive.fileName,
              target: archiveTarget!,
            );
            await controller.recordExternalExport(
              kind: ExportHistoryKind.videoScramble,
              mode: ProcessMode.scramble,
              location: saved.location,
              displayName: saved.displayName,
              sha256: saved.sha256Digest,
              sizeBytes: saved.sizeBytes,
            );
            _lastSavedLocation = saved.location;
          }
        } finally {
          await _archiveService.cleanup(archives);
        }
      } else {
        _updateProgress(.9, '正在按原文件夹结构导出视频');
        for (final output in outputs) {
          final saved = await _saveBatchVideo(output, videoTarget!);
          await controller.recordExternalExport(
            kind: _restore
                ? ExportHistoryKind.videoRestore
                : ExportHistoryKind.videoScramble,
            mode: _restore ? ProcessMode.restore : ProcessMode.scramble,
            location: saved.$1,
            displayName: saved.$2,
            sha256: saved.$3,
            sizeBytes: saved.$4,
          );
          _lastSavedLocation = saved.$1;
        }
      }
      _updateProgress(1, '批量处理与导出完成');
      _message = _compressionEnabled && !_restore
          ? '已完成 ${outputs.length} 个视频；原始导出文件已清理，仅保留压缩包。'
          : '已按原文件夹名称和目录结构导出 ${outputs.length} 个视频。';
      _error = false;
    } catch (error) {
      _message = error.toString();
      _error = true;
    } finally {
      for (final item in copiedInputs) {
        File(item).delete().ignore();
      }
      if (await root.exists()) await root.delete(recursive: true);
      if (mounted) setState(() => _working = false);
    }
  }

  Future<String> _materializeInput(VideoBatchInput input) async {
    if (input.sourcePath != null) return input.sourcePath!;
    final uri = input.sourceUri;
    if (uri == null) throw const VideoProcessException('视频来源不可读取');
    final copied = await _channel.invokeMethod<String>('copyUriToCache', {
      'uri': uri,
      'name': input.name,
    });
    if (copied == null || copied.isEmpty) {
      throw const VideoProcessException('Android 视频复制到缓存失败');
    }
    return copied;
  }

  Future<_VideoBatchExportTarget?> _chooseVideoBatchExportTarget(
    AppController controller,
  ) async {
    final settings = controller.settings;
    final roots = <String, String>{};
    for (final item in _inputs) {
      final key = item.sourceRootId.isEmpty ? 'standalone' : item.sourceRootId;
      roots.putIfAbsent(
        key,
        () => item.sourceRootName.isEmpty
            ? _videoBatchFolderName()
            : item.sourceRootName,
      );
    }
    if (Platform.isAndroid) {
      var treeUri = settings.askExportEveryTime
          ? null
          : settings.defaultExportTreeUri;
      if (treeUri == null) {
        final tree = await _channel.invokeMapMethod<String, dynamic>(
          'pickTree',
        );
        if (tree == null) return null;
        treeUri = tree['uri'] as String?;
        if (treeUri == null) return null;
        if (!settings.askExportEveryTime) {
          await settings.setDefaultExport(
            treeUri: treeUri,
            label: tree['name'] as String? ?? '',
          );
        }
      }
      final androidRoots = <String, String>{};
      for (final entry in roots.entries) {
        final reserved = await _channel.invokeMapMethod<String, dynamic>(
          'createUniqueDirectory',
          {'treeUri': treeUri, 'desiredName': entry.value},
        );
        final uri = reserved?['uri'] as String?;
        if (uri == null) throw const VideoProcessException('建立视频导出文件夹失败');
        androidRoots[entry.key] = uri;
      }
      return _VideoBatchExportTarget(androidRoots: androidRoots);
    }

    var selected = settings.askExportEveryTime
        ? null
        : settings.defaultExportPath;
    selected ??= await FilePicker.platform.getDirectoryPath(
      dialogTitle: _t('选择批量视频导出位置', '選擇批次影片匯出位置'),
    );
    if (selected == null) return null;
    if (!settings.askExportEveryTime && settings.defaultExportPath == null) {
      await settings.setDefaultExport(path: selected, label: selected);
    }
    final windowsRoots = <String, String>{};
    for (final entry in roots.entries) {
      windowsRoots[entry.key] = (await _createUniqueDirectory(
        path.join(selected, sanitizeFileName(entry.value)),
      )).path;
    }
    return _VideoBatchExportTarget(windowsRoots: windowsRoots);
  }

  Future<(String, String, String, int)> _saveBatchVideo(
    VideoBatchOutput output,
    _VideoBatchExportTarget target,
  ) async {
    final key = output.input.sourceRootId.isEmpty
        ? 'standalone'
        : output.input.sourceRootId;
    if (Platform.isAndroid) {
      final treeUri = target.androidRoots[key];
      if (treeUri == null) throw const VideoProcessException('视频导出目录无效');
      final saved = await _channel
          .invokeMapMethod<String, dynamic>('writeFileToTree', {
            'treeUri': treeUri,
            'relativeFolder': output.input.relativeDirectory,
            'fileName': output.outputName,
            'sourcePath': output.path,
            'mimeType': 'video/mp4',
          });
      final location = saved?['uri'] as String?;
      if (location == null) throw const VideoProcessException('Android 视频导出失败');
      final file = File(output.path);
      final digest = await sha256.bind(file.openRead()).first;
      return (
        location,
        saved?['name'] as String? ?? output.outputName,
        digest.toString(),
        await file.length(),
      );
    }
    final root = target.windowsRoots[key];
    if (root == null) throw const VideoProcessException('视频导出目录无效');
    final folder = Directory(path.join(root, output.input.relativeDirectory));
    await folder.create(recursive: true);
    final destination = await _uniqueFilePath(
      path.join(folder.path, output.outputName),
    );
    final saved = await File(output.path).copy(destination);
    final digest = await sha256.bind(saved.openRead()).first;
    return (
      saved.path,
      path.basename(saved.path),
      digest.toString(),
      await saved.length(),
    );
  }

  Future<Directory> _createUniqueDirectory(String desired) async {
    var candidate = desired;
    var suffix = 1;
    while (await Directory(candidate).exists() ||
        await File(candidate).exists()) {
      candidate = '$desired（$suffix）';
      suffix++;
    }
    final directory = Directory(candidate);
    await directory.create(recursive: true);
    return directory;
  }

  Future<String> _uniqueFilePath(String desired) async {
    if (!await File(desired).exists() && !await Directory(desired).exists()) {
      return desired;
    }
    final extension = path.extension(desired);
    final base = desired.substring(0, desired.length - extension.length);
    var suffix = 1;
    while (true) {
      final candidate = '$base（$suffix）$extension';
      if (!await File(candidate).exists() &&
          !await Directory(candidate).exists()) {
        return candidate;
      }
      suffix++;
    }
  }

  String _videoBatchFolderName() {
    final now = DateTime.now();
    String two(int value) => value.toString().padLeft(2, '0');
    return 'Langbai_${_restore ? '视频还原' : '视频混淆'}_'
        '${now.year}${two(now.month)}${two(now.day)}_'
        '${two(now.hour)}${two(now.minute)}${two(now.second)}';
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

  VideoPerformanceMode get _activePerformanceMode =>
      _restore ? _restorePerformance : _scramblePerformance;

  set _activePerformanceMode(VideoPerformanceMode value) {
    if (_restore) {
      _restorePerformance = value;
    } else {
      _scramblePerformance = value;
    }
  }

  List<PasswordProfile> get _archiveProfiles =>
      context.read<AppController?>()?.archivePasswordProfiles ?? const [];

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
      _scramblePerformance = VideoPerformanceModeX.fromId(
        preferences.getString('video_scramble_performance'),
      );
      _restorePerformance = VideoPerformanceModeX.fromId(
        preferences.getString('video_restore_performance'),
      );
      _compressionEnabled =
          preferences.getBool('video_compression_enabled') ?? false;
      _compressionFormat =
          preferences.getString('video_compression_format') == '7z'
          ? CompressionArchiveFormat.sevenZip
          : CompressionArchiveFormat.zip;
      _compressionGrouping = switch (preferences.getString(
        'video_compression_grouping',
      )) {
        'per_file' => CompressionGrouping.perFile,
        'combined' => CompressionGrouping.combined,
        _ => CompressionGrouping.perFolder,
      };
      _archivePasswordProfileId = preferences.getString(
        'video_archive_password_profile',
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
      preferences.setString(
        'video_scramble_performance',
        _scramblePerformance.id,
      ),
      preferences.setString(
        'video_restore_performance',
        _restorePerformance.id,
      ),
      preferences.setBool('video_password_enabled', _passwordEnabled),
      preferences.setBool('video_compression_enabled', _compressionEnabled),
      preferences.setString(
        'video_compression_format',
        _compressionFormat == CompressionArchiveFormat.sevenZip ? '7z' : 'zip',
      ),
      preferences.setString(
        'video_compression_grouping',
        switch (_compressionGrouping) {
          CompressionGrouping.perFolder => 'per_folder',
          CompressionGrouping.perFile => 'per_file',
          CompressionGrouping.combined => 'combined',
        },
      ),
      if (_archivePasswordProfileId == null)
        preferences.remove('video_archive_password_profile')
      else
        preferences.setString(
          'video_archive_password_profile',
          _archivePasswordProfileId!,
        ),
    ]);
  }

  String _t(String simplified, String traditional) =>
      widget.traditional ? traditional : simplified;
}

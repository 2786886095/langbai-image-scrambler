import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../app_controller.dart';
import '../export_history.dart';
import '../models.dart';
import 'fun_tools_models.dart';
import 'fun_tools_processor.dart';
import 'tool_file_io.dart';

class FunToolsScreen extends StatefulWidget {
  const FunToolsScreen({super.key, this.traditional = false});

  final bool traditional;

  @override
  State<FunToolsScreen> createState() => _FunToolsScreenState();
}

class _FunToolsScreenState extends State<FunToolsScreen> {
  final _processor = const FunToolsProcessor();
  final _files = const ToolFileIo();
  FunToolType _tool = FunToolType.prism;
  bool _restore = false;
  CloakVersion _version = CloakVersion.v5;
  PickedToolFile? _inner;
  PickedToolFile? _cover;
  PickedToolFile? _payload;
  PickedToolFile? _encoded;
  Uint8List? _result;
  String? _resultName;
  String? _lastSavedLocation;
  String? _message;
  bool _error = false;
  bool _working = false;
  double _difference = 24;

  @override
  void initState() {
    super.initState();
    _restoreSettings();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SafeArea(
      top: false,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final desktop = constraints.maxWidth >= 920;
          return SingleChildScrollView(
            padding: EdgeInsets.fromLTRB(
              desktop ? 36 : 16,
              desktop ? 30 : 16,
              desktop ? 36 : 16,
              96,
            ),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1180),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      _t('趣味工具', '趣味工具'),
                      style: Theme.of(context).textTheme.headlineMedium
                          ?.copyWith(fontWeight: FontWeight.w900),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _t(
                        '用两张图片制作视觉错觉，或把文件隐藏在可打开的 PNG 中。所有处理均在本机完成。',
                        '用兩張圖片製作視覺錯覺，或把檔案隱藏在可開啟的 PNG 中。所有處理均在本機完成。',
                      ),
                      style: TextStyle(
                        height: 1.55,
                        color: scheme.onSurface.withValues(alpha: .67),
                      ),
                    ),
                    const SizedBox(height: 22),
                    SegmentedButton<FunToolType>(
                      segments: [
                        ButtonSegment(
                          value: FunToolType.prism,
                          icon: const Icon(Icons.blur_on_rounded),
                          label: Text(_t('光棱坦克', '光稜坦克')),
                        ),
                        ButtonSegment(
                          value: FunToolType.cloak,
                          icon: const Icon(Icons.layers_outlined),
                          label: Text(_t('幻影坦克', '幻影坦克')),
                        ),
                      ],
                      selected: {_tool},
                      showSelectedIcon: false,
                      onSelectionChanged: _working
                          ? null
                          : (value) => setState(() {
                              _tool = value.first;
                              _restore = false;
                              _resetResult();
                              _saveSettings();
                            }),
                      style: const ButtonStyle(
                        minimumSize: WidgetStatePropertyAll(Size(150, 50)),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Card(
                      child: Padding(
                        padding: EdgeInsets.all(desktop ? 24 : 16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            _toolHeader(),
                            const SizedBox(height: 20),
                            if (_tool == FunToolType.cloak)
                              _cloakVersionPicker(),
                            if (_tool == FunToolType.cloak)
                              const SizedBox(height: 18),
                            if (_restore)
                              _inputTile(
                                title: _tool == FunToolType.prism
                                    ? _t('选择光棱图片', '選擇光稜圖片')
                                    : _t('选择幻影 PNG', '選擇幻影 PNG'),
                                subtitle:
                                    _encoded?.name ??
                                    _t('用于识别版本并提取隐藏文件', '用於識別版本並提取隱藏檔案'),
                                icon: Icons.image_search_outlined,
                                selected: _encoded != null,
                                onTap: () =>
                                    _pickImage((file) => _encoded = file),
                              )
                            else
                              _buildGenerationInputs(desktop),
                            if (!_restore &&
                                _tool == FunToolType.cloak &&
                                _version.carriesFile) ...[
                              const SizedBox(height: 14),
                              _inputTile(
                                title: _t('选择要隐藏的文件', '選擇要隱藏的檔案'),
                                subtitle:
                                    _payload?.name ??
                                    _t(
                                      '支持图片、TXT、压缩包及其他文件',
                                      '支援圖片、TXT、壓縮檔及其他檔案',
                                    ),
                                icon: Icons.attach_file_rounded,
                                selected: _payload != null,
                                onTap: () =>
                                    _pickAny((file) => _payload = file),
                              ),
                            ],
                            if (!_restore &&
                                _tool == FunToolType.cloak &&
                                _version.carriesFile) ...[
                              const SizedBox(height: 18),
                              Text(
                                '${_t('数据色差', '資料色差')} ${_difference.round()}',
                              ),
                              Slider(
                                value: _difference,
                                min: 10,
                                max: 70,
                                divisions: 12,
                                label: _difference.round().toString(),
                                onChanged: _working
                                    ? null
                                    : (value) =>
                                          setState(() => _difference = value),
                                onChangeEnd: (_) => _saveSettings(),
                              ),
                            ],
                            const SizedBox(height: 20),
                            FilledButton.icon(
                              onPressed: _working ? null : _run,
                              icon: _working
                                  ? const SizedBox.square(
                                      dimension: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                      ),
                                    )
                                  : Icon(
                                      _restore
                                          ? Icons.unarchive_outlined
                                          : Icons.auto_awesome_outlined,
                                    ),
                              label: Text(
                                _working
                                    ? _t('正在处理', '正在處理')
                                    : _restore
                                    ? (_tool == FunToolType.prism
                                          ? _t('还原里图', '還原裡圖')
                                          : _t('识别并提取文件', '識別並提取檔案'))
                                    : _t('立即生成 PNG', '立即生成 PNG'),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    if (_message != null) ...[
                      const SizedBox(height: 14),
                      _messageCard(),
                    ],
                    if (_result != null) ...[
                      const SizedBox(height: 16),
                      _resultCard(),
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

  Widget _toolHeader() {
    final scheme = Theme.of(context).colorScheme;
    final description = _tool == FunToolType.prism
        ? _t(
            '在里图与表图之间交错像素和亮度区间，生成一张视觉混淆图；解码得到的是近似里图。',
            '在裡圖與表圖之間交錯像素和亮度區間，生成一張視覺混淆圖；解碼得到的是近似裡圖。',
          )
        : _t(
            'v0–v3 可把文件写入 PNG 并自动识别提取；v4–v5 用透明度与颜色制造双图视觉效果。',
            'v0–v3 可把檔案寫入 PNG 並自動識別提取；v4–v5 用透明度與顏色製造雙圖視覺效果。',
          );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 16,
          runSpacing: 12,
          children: [
            Text(
              _tool == FunToolType.prism
                  ? _t('光棱坦克', '光稜坦克')
                  : _t('幻影坦克', '幻影坦克'),
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900),
            ),
            SegmentedButton<bool>(
              segments: [
                ButtonSegment(value: false, label: Text(_t('生成', '生成'))),
                ButtonSegment(value: true, label: Text(_t('还原/提取', '還原/提取'))),
              ],
              selected: {_restore},
              showSelectedIcon: false,
              onSelectionChanged: _working
                  ? null
                  : (value) => setState(() {
                      _restore = value.first;
                      _resetResult();
                      _saveSettings();
                    }),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Text(
          description,
          style: TextStyle(
            height: 1.55,
            color: scheme.onSurface.withValues(alpha: .68),
          ),
        ),
      ],
    );
  }

  Widget _cloakVersionPicker() {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        DropdownButtonFormField<CloakVersion>(
          initialValue: _version,
          decoration: InputDecoration(
            labelText: _t('幻影版本', '幻影版本'),
            prefixIcon: const Icon(Icons.tune_rounded),
          ),
          items: [
            for (final version in CloakVersion.values)
              DropdownMenuItem(
                value: version,
                child: Text(version.titleFor(widget.traditional)),
              ),
          ],
          onChanged: _working
              ? null
              : (value) => setState(() {
                  _version = value ?? _version;
                  _resetResult();
                  _saveSettings();
                }),
        ),
        const SizedBox(height: 10),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: scheme.primary.withValues(alpha: .07),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: scheme.primary.withValues(alpha: .18)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _version.descriptionFor(widget.traditional),
                style: const TextStyle(
                  height: 1.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                _version.noticeFor(widget.traditional),
                style: TextStyle(
                  fontSize: 12,
                  height: 1.45,
                  color: scheme.onSurface.withValues(alpha: .62),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildGenerationInputs(bool desktop) {
    final inner = _inputTile(
      title: _t('选择里图', '選擇裡圖'),
      subtitle: _inner?.name ?? _t('隐藏画面或主要画面', '隱藏畫面或主要畫面'),
      icon: Icons.filter_1_outlined,
      selected: _inner != null,
      onTap: () => _pickImage((file) => _inner = file),
    );
    final needsCover = _tool == FunToolType.prism || _version.needsCover;
    final cover = _inputTile(
      title: _t('选择表图', '選擇表圖'),
      subtitle: _cover?.name ?? _t('正常查看时显示的画面', '正常檢視時顯示的畫面'),
      icon: Icons.filter_2_outlined,
      selected: _cover != null,
      onTap: () => _pickImage((file) => _cover = file),
    );
    if (desktop) {
      return Row(
        children: [
          Expanded(child: inner),
          if (needsCover) ...[
            const SizedBox(width: 14),
            Expanded(child: cover),
          ],
        ],
      );
    }
    return Column(
      children: [
        inner,
        if (needsCover) ...[const SizedBox(height: 14), cover],
      ],
    );
  }

  Widget _inputTile({
    required String title,
    required String subtitle,
    required IconData icon,
    required bool selected,
    required VoidCallback onTap,
  }) {
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      button: true,
      label: title,
      child: InkWell(
        onTap: _working ? null : onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          constraints: const BoxConstraints(minHeight: 92),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: selected
                ? scheme.primary.withValues(alpha: .08)
                : scheme.surfaceContainerHighest.withValues(alpha: .45),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: selected
                  ? scheme.primary.withValues(alpha: .35)
                  : scheme.outlineVariant,
            ),
          ),
          child: Row(
            children: [
              Icon(
                icon,
                color: selected
                    ? scheme.primary
                    : scheme.onSurface.withValues(alpha: .6),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      subtitle,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12,
                        color: scheme.onSurface.withValues(alpha: .62),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Icon(
                selected
                    ? Icons.check_circle_rounded
                    : Icons.add_circle_outline_rounded,
                color: selected ? scheme.secondary : scheme.primary,
              ),
            ],
          ),
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

  Widget _resultCard() {
    final isImage = _resultName?.toLowerCase().endsWith('.png') == true;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              _t('处理结果', '處理結果'),
              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w900),
            ),
            if (isImage) ...[
              const SizedBox(height: 14),
              ClipRRect(
                borderRadius: BorderRadius.circular(14),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 420),
                  child: Image.memory(
                    _result!,
                    fit: BoxFit.contain,
                    gaplessPlayback: true,
                  ),
                ),
              ),
            ],
            const SizedBox(height: 14),
            OutlinedButton.icon(
              onPressed: _saveResult,
              icon: const Icon(Icons.save_alt_rounded),
              label: Text('${_t('导出', '匯出')} ${_resultName ?? _t('结果', '結果')}'),
            ),
            if (_lastSavedLocation != null) ...[
              const SizedBox(height: 10),
              TextButton.icon(
                onPressed: () => _files.openSavedLocation(_lastSavedLocation!),
                icon: const Icon(Icons.folder_open_rounded),
                label: Text(_t('打开导出位置', '開啟匯出位置')),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _pickImage(void Function(PickedToolFile file) assign) async {
    try {
      final file = await _files.pickImage();
      if (file == null || !mounted) return;
      setState(() {
        assign(file);
        _resetResult();
      });
    } catch (error) {
      _showError(error);
    }
  }

  Future<void> _pickAny(void Function(PickedToolFile file) assign) async {
    try {
      final file = await _files.pickAny();
      if (file == null || !mounted) return;
      setState(() {
        assign(file);
        _resetResult();
      });
    } catch (error) {
      _showError(error);
    }
  }

  Future<void> _run() async {
    setState(() {
      _working = true;
      _message = null;
      _error = false;
      _result = null;
    });
    try {
      if (_restore) {
        final encoded = _encoded;
        if (encoded == null) throw const FunToolException('请先选择要还原或提取的 PNG');
        if (_tool == FunToolType.prism) {
          _result = await _processor.restorePrism(inputBytes: encoded.bytes);
          _resultName = '${_stem(encoded.name)}-里图.png';
          _message = '光棱里图已近似还原；缺失的交错像素由邻域插值补全。';
        } else {
          final decoded = await _processor.decodeCloak(encoded.bytes);
          _result = Uint8List.fromList(decoded.bytes);
          _resultName = '${_stem(encoded.name)}-隐藏文件.${decoded.extension}';
          _message = '已自动识别 ${decoded.version.title}，隐藏文件校验通过。';
        }
      } else {
        final inner = _inner;
        if (inner == null) throw const FunToolException('请先选择里图');
        final cover = _cover;
        if ((_tool == FunToolType.prism || _version.needsCover) &&
            cover == null) {
          throw const FunToolException('当前模式需要选择表图');
        }
        if (_tool == FunToolType.prism) {
          _result = await _processor.createPrism(
            innerBytes: inner.bytes,
            coverBytes: cover!.bytes,
          );
          _resultName = '${_stem(inner.name)}.png';
          _message = '光棱坦克已生成。请保留 PNG 原文件以获得较好的还原效果。';
        } else {
          _result = await _processor.createCloak(
            innerBytes: inner.bytes,
            coverBytes: cover?.bytes,
            payloadBytes: _payload?.bytes,
            payloadExtension: _payload?.extension ?? 'bin',
            config: CloakConfig(
              version: _version,
              difference: _difference.round(),
            ),
          );
          _resultName = '${_stem(inner.name)}.png';
          _message = '${_version.title} 已生成。${_version.notice}';
        }
      }
    } catch (error) {
      _message = error.toString();
      _error = true;
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  Future<void> _saveResult() async {
    final bytes = _result;
    final name = _resultName;
    if (bytes == null || name == null) return;
    try {
      final saved = await _files.saveBytes(
        bytes: bytes,
        suggestedName: name,
        mimeType: name.toLowerCase().endsWith('.png')
            ? 'image/png'
            : 'application/octet-stream',
      );
      if (!mounted || saved == null) return;
      final controller = context.read<AppController?>();
      if (controller != null) {
        final kind = switch ((_tool, _restore)) {
          (FunToolType.prism, false) => ExportHistoryKind.prismGenerate,
          (FunToolType.prism, true) => ExportHistoryKind.prismRestore,
          (FunToolType.cloak, false) => ExportHistoryKind.cloakGenerate,
          (FunToolType.cloak, true) => ExportHistoryKind.cloakExtract,
        };
        await controller.recordExternalExport(
          kind: kind,
          mode: _restore ? ProcessMode.restore : ProcessMode.scramble,
          location: saved,
          displayName: name,
          sha256: sha256.convert(bytes).toString(),
          sizeBytes: bytes.length,
        );
      }
      setState(() {
        _lastSavedLocation = saved;
        _message = '已导出到 $saved';
        _error = false;
      });
    } catch (error) {
      _showError(error);
    }
  }

  void _resetResult() {
    _result = null;
    _resultName = null;
    _message = null;
    _error = false;
  }

  void _showError(Object error) {
    if (!mounted) return;
    setState(() {
      _message = error.toString();
      _error = true;
    });
  }

  String _stem(String name) {
    final dot = name.lastIndexOf('.');
    return dot > 0 ? name.substring(0, dot) : name;
  }

  Future<void> _restoreSettings() async {
    final preferences = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      _tool = FunToolType.values.firstWhere(
        (value) => value.name == preferences.getString('fun_tool_type'),
        orElse: () => FunToolType.prism,
      );
      _restore = preferences.getBool('fun_tool_restore') ?? false;
      _version = CloakVersion.values.firstWhere(
        (value) => value.name == preferences.getString('fun_cloak_version'),
        orElse: () => CloakVersion.v5,
      );
      _difference = (preferences.getDouble('fun_cloak_difference') ?? 24).clamp(
        10,
        70,
      );
    });
  }

  Future<void> _saveSettings() async {
    final preferences = await SharedPreferences.getInstance();
    await Future.wait([
      preferences.setString('fun_tool_type', _tool.name),
      preferences.setBool('fun_tool_restore', _restore),
      preferences.setString('fun_cloak_version', _version.name),
      preferences.setDouble('fun_cloak_difference', _difference),
    ]);
  }

  String _t(String simplified, String traditional) =>
      widget.traditional ? traditional : simplified;
}

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'app_controller.dart';
import 'app_settings.dart';
import 'app_strings.dart';
import 'file_service.dart';
import 'models.dart';

Future<void> showSharedImportDialog(
  BuildContext context,
  SharedImportRequest request,
) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    barrierColor: Colors.black.withValues(alpha: 0.58),
    builder: (_) => _SharedImportSheet(request: request),
  );
}

class _SharedImportSheet extends StatefulWidget {
  const _SharedImportSheet({required this.request});

  final SharedImportRequest request;

  @override
  State<_SharedImportSheet> createState() => _SharedImportSheetState();
}

class _SharedImportSheetState extends State<_SharedImportSheet> {
  final Map<String, TextEditingController> _passwordControllers = {};
  late ProcessMode _mode;
  bool _busy = false;
  bool _passwordsVisible = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _mode = context.read<AppController>().mode;
    for (final archive in widget.request.archives) {
      _passwordControllers[_sourceKey(archive)] = TextEditingController();
    }
  }

  @override
  void dispose() {
    for (final controller in _passwordControllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<AppSettings>();
    final strings = AppStrings(settings.language);
    final scheme = Theme.of(context).colorScheme;
    final media = MediaQuery.of(context);
    final maxHeight = media.size.height * 0.9;
    final archives = widget.request.archives;
    return Padding(
      padding: EdgeInsets.only(bottom: media.viewInsets.bottom),
      child: Align(
        alignment: Alignment.bottomCenter,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: 640, maxHeight: maxHeight),
          child: Material(
            color: scheme.surface,
            clipBehavior: Clip.antiAlias,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(height: 10),
                Container(
                  width: 42,
                  height: 4,
                  decoration: BoxDecoration(
                    color: scheme.onSurface.withValues(alpha: 0.18),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                Flexible(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(20, 18, 20, 12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Container(
                              width: 48,
                              height: 48,
                              decoration: BoxDecoration(
                                color: scheme.primary.withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(15),
                              ),
                              child: Icon(
                                Icons.folder_zip_outlined,
                                color: scheme.primary,
                              ),
                            ),
                            const SizedBox(width: 13),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    strings['shareImportTitle'],
                                    style: const TextStyle(
                                      fontSize: 19,
                                      fontWeight: FontWeight.w900,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    strings['shareImportSubtitle'],
                                    style: TextStyle(
                                      fontSize: 12,
                                      height: 1.5,
                                      color: scheme.onSurface.withValues(
                                        alpha: 0.65,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            IconButton(
                              tooltip: strings['cancelAction'],
                              onPressed: _busy
                                  ? null
                                  : () => Navigator.of(context).pop(),
                              icon: const Icon(Icons.close_rounded),
                            ),
                          ],
                        ),
                        const SizedBox(height: 22),
                        _Label(text: strings['shareSources']),
                        const SizedBox(height: 9),
                        _SourceList(
                          items: widget.request.items,
                          strings: strings,
                        ),
                        const SizedBox(height: 20),
                        _Label(text: strings['shareMode']),
                        const SizedBox(height: 9),
                        SizedBox(
                          width: double.infinity,
                          child: SegmentedButton<ProcessMode>(
                            segments: [
                              ButtonSegment(
                                value: ProcessMode.scramble,
                                icon: const Icon(Icons.grid_view_rounded),
                                label: Text(strings['shareScramble']),
                              ),
                              ButtonSegment(
                                value: ProcessMode.restore,
                                icon: const Icon(Icons.auto_fix_high_outlined),
                                label: Text(strings['shareRestore']),
                              ),
                            ],
                            selected: {_mode},
                            onSelectionChanged: _busy
                                ? null
                                : (selection) =>
                                      setState(() => _mode = selection.first),
                            showSelectedIcon: false,
                            style: const ButtonStyle(
                              minimumSize: WidgetStatePropertyAll(
                                Size(150, 50),
                              ),
                            ),
                          ),
                        ),
                        if (archives.isNotEmpty) ...[
                          const SizedBox(height: 20),
                          _Label(text: strings['archivePasswords']),
                          const SizedBox(height: 5),
                          Text(
                            strings['archivePasswordOptional'],
                            style: TextStyle(
                              fontSize: 11.5,
                              height: 1.45,
                              color: scheme.onSurface.withValues(alpha: 0.62),
                            ),
                          ),
                          const SizedBox(height: 10),
                          for (final archive in archives) ...[
                            TextField(
                              controller:
                                  _passwordControllers[_sourceKey(archive)],
                              enabled: !_busy,
                              obscureText: !_passwordsVisible,
                              enableSuggestions: false,
                              autocorrect: false,
                              decoration: InputDecoration(
                                labelText: archive.name,
                                hintText: strings['archivePasswordHint'],
                                prefixIcon: const Icon(Icons.lock_outline),
                                suffixIcon: IconButton(
                                  tooltip: _passwordsVisible
                                      ? strings['hidePassword']
                                      : strings['showPassword'],
                                  onPressed: _busy
                                      ? null
                                      : () => setState(
                                          () => _passwordsVisible =
                                              !_passwordsVisible,
                                        ),
                                  icon: Icon(
                                    _passwordsVisible
                                        ? Icons.visibility_off_outlined
                                        : Icons.visibility_outlined,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(height: 10),
                          ],
                        ],
                        Container(
                          margin: const EdgeInsets.only(top: 10),
                          padding: const EdgeInsets.all(13),
                          decoration: BoxDecoration(
                            color: scheme.primary.withValues(alpha: 0.08),
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(
                              color: scheme.primary.withValues(alpha: 0.18),
                            ),
                          ),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Icon(
                                Icons.account_tree_outlined,
                                size: 19,
                                color: scheme.primary,
                              ),
                              const SizedBox(width: 9),
                              Expanded(
                                child: Text(
                                  '${strings['archiveStructure']}\n${strings['archivePrivacy']}',
                                  style: const TextStyle(
                                    fontSize: 11.5,
                                    height: 1.5,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        if (_error != null) ...[
                          const SizedBox(height: 12),
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: scheme.error.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: scheme.error.withValues(alpha: 0.25),
                              ),
                            ),
                            child: Row(
                              children: [
                                Icon(
                                  Icons.error_outline_rounded,
                                  size: 19,
                                  color: scheme.error,
                                ),
                                const SizedBox(width: 9),
                                Expanded(
                                  child: Text(
                                    _error!,
                                    style: TextStyle(
                                      color: scheme.error,
                                      fontSize: 12,
                                      height: 1.4,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
                const Divider(height: 1),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
                  child: Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: _busy
                              ? null
                              : () => Navigator.of(context).pop(),
                          child: Text(strings['cancelAction']),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        flex: 2,
                        child: FilledButton.icon(
                          onPressed: _busy ? null : _submit,
                          icon: _busy
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                              : const Icon(Icons.add_task_rounded),
                          label: Text(
                            _busy
                                ? strings['importingShare']
                                : archives.isEmpty
                                ? strings['addShareToQueue']
                                : strings['addToQueue'],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _submit() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await context.read<AppController>().acceptSharedImport(
        widget.request,
        selectedMode: _mode,
        archivePasswords: {
          for (final entry in _passwordControllers.entries)
            entry.key: entry.value.text,
        },
      );
      if (mounted) Navigator.of(context).pop();
    } catch (error) {
      if (!mounted) return;
      final strings = AppStrings(context.read<AppSettings>().language);
      final message = error is SharedImportException
          ? [
              if (error.sourceName != null) error.sourceName,
              error.isPasswordError
                  ? strings['archivePasswordError']
                  : error.message,
            ].join('：')
          : error.toString().replaceFirst('Exception: ', '');
      setState(() {
        _busy = false;
        _error = message;
      });
    }
  }

  String _sourceKey(SharedImportItem item) =>
      item.uri ?? item.sourcePath ?? item.name;
}

class _Label extends StatelessWidget {
  const _Label({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) => Text(
    text,
    style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w900),
  );
}

class _SourceList extends StatelessWidget {
  const _SourceList({required this.items, required this.strings});

  final List<SharedImportItem> items;
  final AppStrings strings;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final visible = items.take(4).toList(growable: false);
    return Container(
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.28),
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Column(
        children: [
          for (var index = 0; index < visible.length; index++) ...[
            ListTile(
              dense: true,
              minTileHeight: 50,
              leading: Icon(_icon(visible[index]), color: scheme.primary),
              title: Text(
                visible[index].name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                ),
              ),
              subtitle: Text(
                _kindLabel(visible[index]),
                style: TextStyle(
                  fontSize: 10.5,
                  color: scheme.onSurface.withValues(alpha: 0.58),
                ),
              ),
            ),
            if (index != visible.length - 1)
              Divider(height: 1, indent: 52, color: scheme.outlineVariant),
          ],
          if (items.length > visible.length)
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 8, 14, 10),
              child: Text(
                '+${items.length - visible.length} ${strings['moreSources']}',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: scheme.primary,
                ),
              ),
            ),
        ],
      ),
    );
  }

  IconData _icon(SharedImportItem item) {
    if (item.isDirectory) return Icons.folder_outlined;
    if (item.isArchive) return Icons.folder_zip_outlined;
    if (item.isText) return Icons.description_outlined;
    if (item.isImage) return Icons.image_outlined;
    return Icons.insert_drive_file_outlined;
  }

  String _kindLabel(SharedImportItem item) {
    if (item.isDirectory) return strings['sourceFolder'];
    if (item.isArchive) return item.extension.toUpperCase();
    if (item.isText) return 'TXT';
    if (item.isImage) return strings['sourceImage'];
    return strings['sourceFile'];
  }
}

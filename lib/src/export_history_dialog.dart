import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'app_controller.dart';
import 'app_settings.dart';
import 'app_strings.dart';
import 'export_history.dart';
import 'models.dart';

Future<void> showExportHistoryDialog(BuildContext context) async {
  await context.read<AppController>().cleanupExportHistory();
  if (!context.mounted) return;
  return showDialog<void>(
    context: context,
    barrierColor: Colors.black.withValues(alpha: 0.58),
    builder: (_) => const _ExportHistoryDialog(),
  );
}

class _ExportHistoryDialog extends StatelessWidget {
  const _ExportHistoryDialog();

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<AppController>();
    final settings = context.watch<AppSettings>();
    final strings = AppStrings(settings.language);
    final scheme = Theme.of(context).colorScheme;
    final size = MediaQuery.sizeOf(context);
    final availableHeight = size.height - (size.height < 700 ? 24 : 64);
    final desiredHeight = controller.exportHistory.isEmpty
        ? 430.0
        : 250.0 + math.min(3, controller.exportHistory.length) * 180;
    final dialogHeight = math.min(availableHeight, desiredHeight);
    return Dialog(
      insetPadding: EdgeInsets.symmetric(
        horizontal: size.width < 600 ? 12 : 32,
        vertical: size.height < 700 ? 12 : 32,
      ),
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: 780, maxHeight: availableHeight),
        child: SizedBox(
          height: dialogHeight,
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(22, 18, 12, 14),
                child: Row(
                  children: [
                    Container(
                      width: 42,
                      height: 42,
                      decoration: BoxDecoration(
                        color: scheme.primary.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Icon(Icons.history_rounded, color: scheme.primary),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            strings['historyTitle'],
                            style: const TextStyle(
                              fontSize: 19,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            strings['historySubtitle'],
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 11.5,
                              color: scheme.onSurface.withValues(alpha: 0.65),
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      tooltip: strings['close'],
                      onPressed: () => Navigator.of(context).pop(),
                      icon: const Icon(Icons.close_rounded),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              Expanded(
                child: controller.exportHistory.isEmpty
                    ? _EmptyHistory(strings: strings)
                    : ListView.separated(
                        padding: const EdgeInsets.all(18),
                        itemCount: controller.exportHistory.length,
                        separatorBuilder: (_, _) => const SizedBox(height: 10),
                        itemBuilder: (context, index) => _HistoryCard(
                          entry: controller.exportHistory[index],
                          strings: strings,
                        ),
                      ),
              ),
              const Divider(height: 1),
              Padding(
                padding: const EdgeInsets.all(14),
                child: Align(
                  alignment: Alignment.centerRight,
                  child: FilledButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: Text(strings['close']),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _EmptyHistory extends StatelessWidget {
  const _EmptyHistory({required this.strings});
  final AppStrings strings;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.history_toggle_off_rounded,
              size: 48,
              color: scheme.onSurface.withValues(alpha: 0.35),
            ),
            const SizedBox(height: 14),
            Text(
              strings['historyEmpty'],
              style: const TextStyle(fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 6),
            Text(
              strings['historyEmptyDesc'],
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 12,
                color: scheme.onSurface.withValues(alpha: 0.65),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _HistoryCard extends StatelessWidget {
  const _HistoryCard({required this.entry, required this.strings});
  final ExportHistoryEntry entry;
  final AppStrings strings;

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<AppController>();
    final scheme = Theme.of(context).colorScheme;
    final undoing = controller.undoingHistoryId == entry.id;
    final opening = controller.openingLocationId == 'history:${entry.id}';
    return Material(
      color: scheme.surfaceContainerHighest.withValues(alpha: 0.22),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: scheme.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.all(15),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: scheme.primary.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(_icon, color: scheme.primary),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _title,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        '${_formatTime(entry.createdAt)} · '
                        '${entry.artifacts.length} ${strings['folderItems']}',
                        style: TextStyle(
                          fontSize: 11,
                          color: scheme.onSurface.withValues(alpha: 0.65),
                        ),
                      ),
                    ],
                  ),
                ),
                if (entry.undoneAt != null)
                  _StatusChip(
                    label: strings['undone'],
                    color: scheme.secondary,
                  ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.drive_file_move_outline,
                  size: 18,
                  color: scheme.onSurface.withValues(alpha: 0.55),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    entry.targetLabel,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 11.5,
                      height: 1.4,
                      color: scheme.onSurface.withValues(alpha: 0.68),
                    ),
                  ),
                ),
              ],
            ),
            if (entry.undoneAt != null) ...[
              const SizedBox(height: 10),
              Text(
                '${strings['undoDeleted']} ${entry.deletedCount} · '
                '${strings['undoModified']} ${entry.modifiedSkippedCount} · '
                '${strings['undoMissing']} ${entry.missingCount} · '
                '${strings['undoFailed']} ${entry.failedCount}',
                style: TextStyle(
                  fontSize: 11,
                  color: scheme.onSurface.withValues(alpha: 0.65),
                ),
              ),
            ],
            if (entry.locationToReveal != null || entry.canUndo) ...[
              const SizedBox(height: 13),
              Align(
                alignment: Alignment.centerRight,
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  alignment: WrapAlignment.end,
                  children: [
                    if (entry.locationToReveal != null)
                      OutlinedButton.icon(
                        onPressed:
                            opening || controller.openingLocationId != null
                            ? null
                            : () => _openLocation(context),
                        icon: opening
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.folder_open_outlined),
                        label: Text(
                          opening
                              ? strings['openingOutputLocation']
                              : strings['openOutputLocation'],
                        ),
                      ),
                    if (entry.canUndo)
                      FilledButton.tonalIcon(
                        onPressed: undoing || controller.isProcessing
                            ? null
                            : () => _confirmUndo(context),
                        icon: undoing
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.undo_rounded),
                        label: Text(
                          undoing ? strings['undoing'] : strings['undo'],
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  IconData get _icon => switch (entry.kind) {
    ExportHistoryKind.videoScramble ||
    ExportHistoryKind.videoRestore => Icons.video_file_outlined,
    ExportHistoryKind.prismGenerate ||
    ExportHistoryKind.prismRestore => Icons.blur_on_rounded,
    ExportHistoryKind.cloakGenerate ||
    ExportHistoryKind.cloakExtract => Icons.layers_outlined,
    null =>
      entry.workspaceType == WorkspaceType.mixed
          ? Icons.folder_zip_outlined
          : entry.workspaceType == WorkspaceType.text
          ? Icons.description_outlined
          : entry.mode == ProcessMode.restore
          ? Icons.auto_fix_high_outlined
          : Icons.grid_view_rounded,
  };

  String get _title => switch (entry.kind) {
    ExportHistoryKind.videoScramble => strings['historyVideoScramble'],
    ExportHistoryKind.videoRestore => strings['historyVideoRestore'],
    ExportHistoryKind.prismGenerate => strings['historyPrismGenerate'],
    ExportHistoryKind.prismRestore => strings['historyPrismRestore'],
    ExportHistoryKind.cloakGenerate => strings['historyCloakGenerate'],
    ExportHistoryKind.cloakExtract => strings['historyCloakExtract'],
    null => switch ((entry.workspaceType, entry.mode)) {
      (WorkspaceType.image, ProcessMode.scramble) =>
        strings['historyImageScramble'],
      (WorkspaceType.image, ProcessMode.restore) =>
        strings['historyImageRestore'],
      (WorkspaceType.text, ProcessMode.scramble) =>
        strings['historyTextEncode'],
      (WorkspaceType.text, ProcessMode.restore) =>
        strings['historyTextRestore'],
      (WorkspaceType.mixed, ProcessMode.scramble) =>
        strings['historyMixedScramble'],
      (WorkspaceType.mixed, ProcessMode.restore) =>
        strings['historyMixedRestore'],
    },
  };

  String _formatTime(DateTime time) {
    String two(int value) => value.toString().padLeft(2, '0');
    return '${time.year}-${two(time.month)}-${two(time.day)} '
        '${two(time.hour)}:${two(time.minute)}';
  }

  Future<void> _confirmUndo(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(strings['undoConfirmTitle']),
        content: Text(strings['undoConfirmDesc']),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(strings['cancelAction']),
          ),
          FilledButton.icon(
            onPressed: () => Navigator.of(context).pop(true),
            icon: const Icon(Icons.undo_rounded),
            label: Text(strings['undo']),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    final result = await context.read<AppController>().undoExport(entry);
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          '${strings['undoDeleted']} ${result.deleted} · '
          '${strings['undoModified']} ${result.modified} · '
          '${strings['undoMissing']} ${result.missing} · '
          '${strings['undoFailed']} ${result.failed}',
        ),
      ),
    );
  }

  Future<void> _openLocation(BuildContext context) async {
    final opened = await context.read<AppController>().openExportLocation(
      entry,
    );
    if (!opened && context.mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(strings['outputLocationFailed'])));
    }
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.label, required this.color});
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.12),
      borderRadius: BorderRadius.circular(10),
    ),
    child: Text(
      label,
      style: TextStyle(
        fontSize: 10.5,
        fontWeight: FontWeight.w800,
        color: color,
      ),
    ),
  );
}

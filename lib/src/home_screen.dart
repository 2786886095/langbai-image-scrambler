import 'dart:math' as math;

import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'app_controller.dart';
import 'app_settings.dart';
import 'app_strings.dart';
import 'models.dart';
import 'settings_dialog.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  bool _dragging = false;
  bool _updateScheduled = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_updateScheduled) return;
    _updateScheduled = true;
    final settings = context.read<AppSettings>();
    if (settings.checkUpdates) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) context.read<AppController>().checkForUpdates();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<AppSettings>();
    final strings = AppStrings(settings.language);
    final width = MediaQuery.sizeOf(context).width;
    final desktop = width >= 960;

    return Scaffold(
      appBar: desktop
          ? null
          : AppBar(
              toolbarHeight: 68,
              backgroundColor: Theme.of(context).scaffoldBackgroundColor,
              surfaceTintColor: Colors.transparent,
              titleSpacing: 16,
              title: Row(
                children: [
                  const LogoMark(size: 38),
                  const SizedBox(width: 12),
                  Flexible(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          strings['appName'],
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        Text(
                          strings['appSubtitle'],
                          style: TextStyle(
                            fontSize: 11,
                            color: Theme.of(
                              context,
                            ).colorScheme.onSurface.withValues(alpha: 0.65),
                            letterSpacing: 0.6,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              actions: [
                IconButton(
                  tooltip: strings['settings'],
                  onPressed: () => showSettingsDialog(context),
                  icon: const Icon(Icons.tune_rounded),
                ),
                const SizedBox(width: 8),
              ],
            ),
      body: Row(
        children: [
          if (desktop) _Sidebar(strings: strings),
          Expanded(
            child: DropTarget(
              enable: desktop,
              onDragEntered: (_) => setState(() => _dragging = true),
              onDragExited: (_) => setState(() => _dragging = false),
              onDragDone: (details) async {
                setState(() => _dragging = false);
                await context.read<AppController>().importDropped(
                  details.files,
                );
              },
              child: _Workspace(
                strings: strings,
                dragging: _dragging,
                desktop: desktop,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Sidebar extends StatelessWidget {
  const _Sidebar({required this.strings});

  final AppStrings strings;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: 244,
      decoration: BoxDecoration(
        color: scheme.surface.withValues(alpha: 0.66),
        border: Border(right: BorderSide(color: scheme.outlineVariant)),
      ),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 24, 20, 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const LogoMark(size: 44),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          strings['appName'],
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          strings['appSubtitle'],
                          style: TextStyle(
                            fontSize: 10,
                            letterSpacing: 0.7,
                            color: scheme.onSurface.withValues(alpha: 0.65),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 32),
              _SidebarItem(
                icon: Icons.dashboard_customize_outlined,
                label: strings['workspace'],
                selected: true,
                onTap: () {},
              ),
              const SizedBox(height: 8),
              _SidebarItem(
                icon: Icons.tune_rounded,
                label: strings['settings'],
                selected: false,
                onTap: () => showSettingsDialog(context),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: scheme.secondary.withValues(alpha: 0.09),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: scheme.secondary.withValues(alpha: 0.22),
                  ),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      Icons.shield_outlined,
                      size: 20,
                      color: scheme.secondary,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            strings['offline'],
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            strings['privacyDesc'],
                            maxLines: 3,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 10.5,
                              height: 1.45,
                              color: scheme.onSurface.withValues(alpha: 0.65),
                            ),
                          ),
                        ],
                      ),
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
}

class _SidebarItem extends StatelessWidget {
  const _SidebarItem({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: selected
          ? scheme.primary.withValues(alpha: 0.12)
          : Colors.transparent,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: SizedBox(
          height: 50,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            child: Row(
              children: [
                Icon(
                  icon,
                  size: 21,
                  color: selected
                      ? scheme.primary
                      : scheme.onSurface.withValues(alpha: 0.62),
                ),
                const SizedBox(width: 12),
                Text(
                  label,
                  style: TextStyle(
                    fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                    color: selected
                        ? scheme.primary
                        : scheme.onSurface.withValues(alpha: 0.76),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Workspace extends StatelessWidget {
  const _Workspace({
    required this.strings,
    required this.dragging,
    required this.desktop,
  });

  final AppStrings strings;
  final bool dragging;
  final bool desktop;

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<AppController>();
    final scheme = Theme.of(context).colorScheme;
    final horizontalPadding = desktop ? 36.0 : 16.0;
    return Stack(
      children: [
        SafeArea(
          top: desktop,
          child: SingleChildScrollView(
            padding: EdgeInsets.fromLTRB(
              horizontalPadding,
              desktop ? 30 : 18,
              horizontalPadding,
              32,
            ),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1420),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _Header(strings: strings),
                    if (controller.availableUpdate != null) ...[
                      const SizedBox(height: 18),
                      _UpdateBanner(strings: strings),
                    ],
                    const SizedBox(height: 22),
                    _WorkspaceTypeSelector(strings: strings),
                    const SizedBox(height: 12),
                    _ModeSelector(strings: strings),
                    const SizedBox(height: 20),
                    LayoutBuilder(
                      builder: (context, constraints) {
                        if (constraints.maxWidth >= 980) {
                          return Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                flex: 4,
                                child: Column(
                                  children: [
                                    _ImportCard(
                                      strings: strings,
                                      dragging: dragging,
                                    ),
                                    if (controller.workspaceType ==
                                        WorkspaceType.image) ...[
                                      const SizedBox(height: 18),
                                      _ConfigurationCard(strings: strings),
                                    ],
                                  ],
                                ),
                              ),
                              const SizedBox(width: 20),
                              Expanded(
                                flex: 6,
                                child: _QueueCard(strings: strings),
                              ),
                            ],
                          );
                        }
                        return Column(
                          children: [
                            _ImportCard(strings: strings, dragging: dragging),
                            if (controller.workspaceType ==
                                WorkspaceType.image) ...[
                              const SizedBox(height: 16),
                              _ConfigurationCard(strings: strings),
                            ],
                            const SizedBox(height: 16),
                            _QueueCard(strings: strings),
                          ],
                        );
                      },
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        if (dragging)
          Positioned.fill(
            child: IgnorePointer(
              child: Container(
                color: scheme.primary.withValues(alpha: 0.08),
                alignment: Alignment.center,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 28,
                    vertical: 20,
                  ),
                  decoration: BoxDecoration(
                    color: scheme.surface,
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: scheme.primary, width: 1.5),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.18),
                        blurRadius: 32,
                        offset: const Offset(0, 14),
                      ),
                    ],
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.file_download_outlined, color: scheme.primary),
                      const SizedBox(width: 12),
                      Text(
                        strings['dropTitle'],
                        style: const TextStyle(fontWeight: FontWeight.w800),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.strings});

  final AppStrings strings;

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<AppController>();
    final scheme = Theme.of(context).colorScheme;
    final textMode = controller.workspaceType == WorkspaceType.text;
    final heroTitle = textMode
        ? (controller.mode == ProcessMode.scramble
              ? strings['heroTextEncode']
              : strings['heroTextRestore'])
        : (controller.mode == ProcessMode.scramble
              ? strings['heroScramble']
              : strings['heroRestore']);
    return Wrap(
      alignment: WrapAlignment.spaceBetween,
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 24,
      runSpacing: 16,
      children: [
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: scheme.secondary,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    strings['offline'],
                    style: TextStyle(
                      color: scheme.secondary,
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.5,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                heroTitle,
                style: const TextStyle(
                  fontSize: 28,
                  height: 1.2,
                  fontWeight: FontWeight.w900,
                  letterSpacing: -0.5,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                textMode ? strings['heroTextDesc'] : strings['heroDesc'],
                style: TextStyle(
                  height: 1.6,
                  color: scheme.onSurface.withValues(alpha: 0.65),
                ),
              ),
            ],
          ),
        ),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _FeaturePill(
              icon: Icons.verified_outlined,
              label: textMode ? strings['byteExact'] : strings['pixelExact'],
            ),
            _FeaturePill(
              icon: textMode ? Icons.code_rounded : Icons.image_outlined,
              label: textMode
                  ? strings['base64Standard']
                  : strings['pngOutput'],
            ),
            _FeaturePill(
              icon: Icons.account_tree_outlined,
              label: strings['folderPreserved'],
            ),
          ],
        ),
      ],
    );
  }
}

class _FeaturePill extends StatelessWidget {
  const _FeaturePill({required this.icon, required this.label});
  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      height: 36,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: scheme.primary),
          const SizedBox(width: 7),
          Text(
            label,
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }
}

class _WorkspaceTypeSelector extends StatelessWidget {
  const _WorkspaceTypeSelector({required this.strings});

  final AppStrings strings;

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<AppController>();
    return Align(
      alignment: Alignment.centerLeft,
      child: SegmentedButton<WorkspaceType>(
        segments: [
          ButtonSegment(
            value: WorkspaceType.image,
            icon: const Icon(Icons.image_outlined),
            label: Text(strings['workspaceImage']),
          ),
          ButtonSegment(
            value: WorkspaceType.text,
            icon: const Icon(Icons.description_outlined),
            label: Text(strings['workspaceText']),
          ),
        ],
        selected: {controller.workspaceType},
        onSelectionChanged: controller.isProcessing
            ? null
            : (selection) => controller.setWorkspaceType(selection.first),
        showSelectedIcon: false,
        style: ButtonStyle(
          minimumSize: const WidgetStatePropertyAll(Size(132, 44)),
          shape: WidgetStatePropertyAll(
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(13)),
          ),
        ),
      ),
    );
  }
}

class _ModeSelector extends StatelessWidget {
  const _ModeSelector({required this.strings});
  final AppStrings strings;

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<AppController>();
    final textMode = controller.workspaceType == WorkspaceType.text;
    return Align(
      alignment: Alignment.centerLeft,
      child: SegmentedButton<ProcessMode>(
        segments: [
          ButtonSegment(
            value: ProcessMode.scramble,
            icon: Icon(textMode ? Icons.code_rounded : Icons.grid_view_rounded),
            label: Text(textMode ? strings['textEncode'] : strings['scramble']),
          ),
          ButtonSegment(
            value: ProcessMode.restore,
            icon: Icon(
              textMode
                  ? Icons.settings_backup_restore_rounded
                  : Icons.auto_fix_high_outlined,
            ),
            label: Text(textMode ? strings['textRestore'] : strings['restore']),
          ),
        ],
        selected: {controller.mode},
        onSelectionChanged: controller.isProcessing
            ? null
            : (selection) => controller.setMode(selection.first),
        showSelectedIcon: false,
        style: ButtonStyle(
          minimumSize: const WidgetStatePropertyAll(Size(142, 48)),
          shape: WidgetStatePropertyAll(
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          ),
        ),
      ),
    );
  }
}

class _ImportCard extends StatelessWidget {
  const _ImportCard({required this.strings, required this.dragging});
  final AppStrings strings;
  final bool dragging;

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<AppController>();
    final scheme = Theme.of(context).colorScheme;
    final textMode = controller.workspaceType == WorkspaceType.text;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _SectionTitle(
              icon: textMode
                  ? Icons.note_add_outlined
                  : Icons.add_photo_alternate_outlined,
              title: textMode
                  ? strings['importTextTitle']
                  : strings['importTitle'],
            ),
            const SizedBox(height: 14),
            AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              curve: Curves.easeOut,
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 28),
              decoration: BoxDecoration(
                color: dragging
                    ? scheme.primary.withValues(alpha: 0.1)
                    : scheme.surfaceContainerHighest.withValues(alpha: 0.28),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: dragging ? scheme.primary : scheme.outlineVariant,
                  width: dragging ? 1.5 : 1,
                ),
              ),
              child: Column(
                children: [
                  Container(
                    width: 56,
                    height: 56,
                    decoration: BoxDecoration(
                      color: scheme.primary.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(18),
                    ),
                    alignment: Alignment.center,
                    child: Icon(
                      Icons.cloud_upload_outlined,
                      size: 27,
                      color: scheme.primary,
                      semanticLabel: textMode
                          ? strings['dropTextTitle']
                          : strings['dropTitle'],
                    ),
                  ),
                  const SizedBox(height: 14),
                  Text(
                    textMode ? strings['dropTextTitle'] : strings['dropTitle'],
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    textMode ? strings['dropTextDesc'] : strings['dropDesc'],
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 12,
                      height: 1.5,
                      color: scheme.onSurface.withValues(alpha: 0.65),
                    ),
                  ),
                  const SizedBox(height: 18),
                  Wrap(
                    alignment: WrapAlignment.center,
                    spacing: 10,
                    runSpacing: 10,
                    children: [
                      FilledButton.icon(
                        onPressed: controller.isProcessing
                            ? null
                            : controller.pickFiles,
                        icon: Icon(
                          textMode
                              ? Icons.description_outlined
                              : Icons.image_outlined,
                          size: 19,
                        ),
                        label: Text(
                          textMode
                              ? strings['chooseText']
                              : strings['chooseImages'],
                        ),
                      ),
                      OutlinedButton.icon(
                        onPressed: controller.isProcessing
                            ? null
                            : controller.pickFolder,
                        icon: const Icon(Icons.folder_open_outlined, size: 19),
                        label: Text(strings['chooseFolder']),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ConfigurationCard extends StatelessWidget {
  const _ConfigurationCard({required this.strings});
  final AppStrings strings;

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<AppController>();
    final availableAlgorithms = controller.mode == ProcessMode.restore
        ? ScrambleAlgorithm.values
        : ScrambleAlgorithm.values.where((item) => !item.isAutomatic).toList();
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _SectionTitle(
              icon: Icons.tune_rounded,
              title: strings['configuration'],
            ),
            const SizedBox(height: 16),
            _AlgorithmPickerField(
              strings: strings,
              selected: controller.algorithm,
              algorithms: availableAlgorithms,
              enabled: !controller.isProcessing,
            ),
            const SizedBox(height: 16),
            if (controller.mode == ProcessMode.scramble)
              SwitchListTile(
                value: controller.passwordEnabled,
                onChanged:
                    controller.algorithm.isCompatibility ||
                        controller.isProcessing
                    ? null
                    : controller.setPasswordEnabled,
                contentPadding: EdgeInsets.zero,
                title: Text(
                  strings['passwordProtection'],
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                subtitle: Text(
                  controller.algorithm.isCompatibility
                      ? strings['passwordUnsupported']
                      : strings['passwordProtectionDesc'],
                  style: const TextStyle(fontSize: 11.5, height: 1.45),
                ),
                secondary: const Icon(Icons.lock_outline_rounded),
              ),
            if ((controller.mode == ProcessMode.scramble &&
                    controller.passwordEnabled) ||
                (controller.mode == ProcessMode.restore &&
                    !controller.algorithm.isCompatibility)) ...[
              const SizedBox(height: 8),
              _PasswordField(strings: strings),
            ],
            if (controller.mode == ProcessMode.restore &&
                controller.algorithm.needsSeed) ...[
              const SizedBox(height: 12),
              TextField(
                enabled: !controller.isProcessing,
                keyboardType: TextInputType.number,
                onChanged: controller.setManualSeed,
                decoration: InputDecoration(
                  labelText: strings['manualSeed'],
                  helperText: strings['manualSeedHint'],
                  prefixIcon: const Icon(Icons.numbers_rounded),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _AlgorithmPickerField extends StatelessWidget {
  const _AlgorithmPickerField({
    required this.strings,
    required this.selected,
    required this.algorithms,
    required this.enabled,
  });

  final AppStrings strings;
  final ScrambleAlgorithm selected;
  final Iterable<ScrambleAlgorithm> algorithms;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      button: true,
      enabled: enabled,
      label: '${strings['algorithm']}：${strings.algorithmName(selected)}',
      hint: strings['tapToChange'],
      child: Material(
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.28),
        borderRadius: BorderRadius.circular(15),
        child: InkWell(
          key: const ValueKey('algorithm-picker-field'),
          onTap: enabled
              ? () => _showAlgorithmPicker(
                  context,
                  strings: strings,
                  algorithms: algorithms.toList(growable: false),
                  selected: selected,
                )
              : null,
          borderRadius: BorderRadius.circular(15),
          child: Container(
            constraints: const BoxConstraints(minHeight: 88),
            padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(15),
              border: Border.all(color: scheme.outlineVariant),
            ),
            child: Row(
              children: [
                _AlgorithmIcon(algorithm: selected, size: 46),
                const SizedBox(width: 13),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        strings['algorithm'],
                        style: TextStyle(
                          fontSize: 10.5,
                          fontWeight: FontWeight.w700,
                          color: scheme.onSurface.withValues(alpha: 0.65),
                        ),
                      ),
                      const SizedBox(height: 3),
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              strings.algorithmName(selected),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                          ),
                          if (selected.isCompatibility) ...[
                            const SizedBox(width: 7),
                            _CompatibilityBadge(strings: strings),
                          ],
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        strings.algorithmDescription(selected),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 11,
                          color: scheme.onSurface.withValues(alpha: 0.65),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.unfold_more_rounded,
                      size: 21,
                      color: enabled
                          ? scheme.primary
                          : scheme.onSurface.withValues(alpha: 0.28),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      strings['tapToChange'],
                      style: TextStyle(
                        fontSize: 9.5,
                        color: scheme.onSurface.withValues(alpha: 0.65),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

Future<void> _showAlgorithmPicker(
  BuildContext context, {
  required AppStrings strings,
  required List<ScrambleAlgorithm> algorithms,
  required ScrambleAlgorithm selected,
}) {
  final compact =
      Theme.of(context).platform == TargetPlatform.android ||
      MediaQuery.sizeOf(context).width < 600;
  if (compact) {
    return showModalBottomSheet<void>(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: 0.58),
      builder: (context) => FractionallySizedBox(
        heightFactor: 0.92,
        child: _AlgorithmPickerPanel(
          strings: strings,
          algorithms: algorithms,
          selected: selected,
          compact: true,
        ),
      ),
    );
  }
  return showDialog<void>(
    context: context,
    barrierColor: Colors.black.withValues(alpha: 0.58),
    builder: (context) => Dialog(
      insetPadding: const EdgeInsets.all(32),
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 820, maxHeight: 760),
        child: _AlgorithmPickerPanel(
          strings: strings,
          algorithms: algorithms,
          selected: selected,
          compact: false,
        ),
      ),
    ),
  );
}

class _AlgorithmPickerPanel extends StatelessWidget {
  const _AlgorithmPickerPanel({
    required this.strings,
    required this.algorithms,
    required this.selected,
    required this.compact,
  });

  final AppStrings strings;
  final List<ScrambleAlgorithm> algorithms;
  final ScrambleAlgorithm selected;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.surface,
      borderRadius: compact
          ? const BorderRadius.vertical(top: Radius.circular(26))
          : BorderRadius.circular(24),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          if (compact) ...[
            const SizedBox(height: 10),
            Container(
              width: 42,
              height: 4,
              decoration: BoxDecoration(
                color: scheme.outline.withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ],
          Padding(
            padding: EdgeInsets.fromLTRB(22, compact ? 16 : 22, 12, 18),
            child: Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: scheme.primary.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Icon(Icons.hub_outlined, color: scheme.primary),
                ),
                const SizedBox(width: 13),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        strings['chooseAlgorithm'],
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        strings['chooseAlgorithmDesc'],
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
          Divider(height: 1, color: scheme.outlineVariant),
          Expanded(
            child: compact
                ? ListView.separated(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
                    itemCount: algorithms.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 10),
                    itemBuilder: (context, index) => _AlgorithmChoiceCard(
                      algorithm: algorithms[index],
                      selected: algorithms[index] == selected,
                      strings: strings,
                      compact: true,
                    ),
                  )
                : GridView.builder(
                    padding: const EdgeInsets.all(20),
                    gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 2,
                          crossAxisSpacing: 12,
                          mainAxisSpacing: 12,
                          mainAxisExtent: 136,
                        ),
                    itemCount: algorithms.length,
                    itemBuilder: (context, index) => _AlgorithmChoiceCard(
                      algorithm: algorithms[index],
                      selected: algorithms[index] == selected,
                      strings: strings,
                      compact: false,
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

class _AlgorithmChoiceCard extends StatelessWidget {
  const _AlgorithmChoiceCard({
    required this.algorithm,
    required this.selected,
    required this.strings,
    required this.compact,
  });

  final ScrambleAlgorithm algorithm;
  final bool selected;
  final AppStrings strings;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      button: true,
      selected: selected,
      label: strings.algorithmName(algorithm),
      child: Material(
        color: selected
            ? scheme.primary.withValues(alpha: 0.11)
            : scheme.surfaceContainerHighest.withValues(alpha: 0.24),
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          key: ValueKey('algorithm-choice-${algorithm.id}'),
          onTap: () {
            context.read<AppController>().setAlgorithm(algorithm);
            Navigator.of(context).pop();
          },
          borderRadius: BorderRadius.circular(16),
          child: Container(
            padding: EdgeInsets.all(compact ? 14 : 15),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: selected ? scheme.primary : scheme.outlineVariant,
                width: selected ? 1.5 : 1,
              ),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _AlgorithmIcon(algorithm: algorithm, size: compact ? 44 : 46),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              strings.algorithmName(algorithm),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 13.5,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                          ),
                          if (selected)
                            Icon(
                              Icons.check_circle_rounded,
                              size: 20,
                              color: scheme.primary,
                              semanticLabel: strings['selected'],
                            ),
                        ],
                      ),
                      if (algorithm.isCompatibility) ...[
                        const SizedBox(height: 5),
                        _CompatibilityBadge(strings: strings),
                      ],
                      const SizedBox(height: 6),
                      Text(
                        strings.algorithmDescription(algorithm),
                        maxLines: algorithm.isCompatibility ? 2 : 3,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 11,
                          height: 1.42,
                          color: scheme.onSurface.withValues(alpha: 0.65),
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
}

class _AlgorithmIcon extends StatelessWidget {
  const _AlgorithmIcon({required this.algorithm, required this.size});

  final ScrambleAlgorithm algorithm;
  final double size;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final icon = switch (algorithm) {
      ScrambleAlgorithm.auto => Icons.auto_awesome_rounded,
      ScrambleAlgorithm.blockShuffle => Icons.grid_4x4_rounded,
      ScrambleAlgorithm.rowShift => Icons.view_stream_outlined,
      ScrambleAlgorithm.columnShift => Icons.view_column_outlined,
      ScrambleAlgorithm.pixelPermutation => Icons.grain_rounded,
      ScrambleAlgorithm.channelDisturbance => Icons.palette_outlined,
      ScrambleAlgorithm.composite => Icons.hub_outlined,
      ScrambleAlgorithm.cherryTomato => Icons.route_outlined,
    };
    final color = algorithm.isCompatibility
        ? const Color(0xffff6b78)
        : scheme.primary;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(size * 0.3),
      ),
      alignment: Alignment.center,
      child: Icon(icon, size: size * 0.48, color: color),
    );
  }
}

class _CompatibilityBadge extends StatelessWidget {
  const _CompatibilityBadge({required this.strings});

  final AppStrings strings;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: const Color(0xffff5f6d).withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(7),
      ),
      child: Text(
        strings['compatibility'],
        style: const TextStyle(
          color: Color(0xffff6b78),
          fontSize: 9.5,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

class _PasswordField extends StatefulWidget {
  const _PasswordField({required this.strings});
  final AppStrings strings;

  @override
  State<_PasswordField> createState() => _PasswordFieldState();
}

class _PasswordFieldState extends State<_PasswordField> {
  bool _visible = false;

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<AppController>();
    return TextField(
      enabled: !controller.isProcessing,
      obscureText: !_visible,
      enableSuggestions: false,
      autocorrect: false,
      onChanged: controller.setPassword,
      decoration: InputDecoration(
        labelText: widget.strings['password'],
        prefixIcon: const Icon(Icons.password_rounded),
        suffixIcon: IconButton(
          tooltip: _visible ? '隐藏密码' : '显示密码',
          onPressed: () => setState(() => _visible = !_visible),
          icon: Icon(
            _visible
                ? Icons.visibility_off_outlined
                : Icons.visibility_outlined,
          ),
        ),
      ),
    );
  }
}

class _QueueCard extends StatelessWidget {
  const _QueueCard({required this.strings});
  final AppStrings strings;

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<AppController>();
    final scheme = Theme.of(context).colorScheme;
    final textMode = controller.workspaceType == WorkspaceType.text;
    final listHeight = controller.tasks.isEmpty
        ? 260.0
        : math.min(470.0, 82.0 * controller.tasks.length + 16);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: _SectionTitle(
                    icon: textMode
                        ? Icons.library_books_outlined
                        : Icons.photo_library_outlined,
                    title: textMode ? strings['textQueue'] : strings['queue'],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    color: scheme.primary.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    '${controller.tasks.length} '
                    '${textMode ? strings['textFiles'] : strings['files']}',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      color: scheme.primary,
                    ),
                  ),
                ),
                if (controller.tasks.isNotEmpty &&
                    !controller.isProcessing) ...[
                  const SizedBox(width: 4),
                  IconButton(
                    tooltip: strings['clear'],
                    onPressed: controller.clear,
                    icon: const Icon(Icons.delete_outline_rounded),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 14),
            SizedBox(
              height: listHeight,
              child: controller.tasks.isEmpty
                  ? _EmptyQueue(strings: strings, textMode: textMode)
                  : Scrollbar(
                      child: ListView.separated(
                        padding: const EdgeInsets.only(right: 4),
                        itemCount: controller.tasks.length,
                        separatorBuilder: (_, _) => const SizedBox(height: 8),
                        itemBuilder: (context, index) => _TaskRow(
                          task: controller.tasks[index],
                          strings: strings,
                          textMode: textMode,
                        ),
                      ),
                    ),
            ),
            const SizedBox(height: 16),
            if (controller.tasks.isNotEmpty) ...[
              Row(
                children: [
                  Expanded(
                    child: Text(
                      controller.detailMessage ?? strings[controller.statusKey],
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12,
                        height: 1.4,
                        color:
                            controller.failedCount > 0 ||
                                controller.detailMessage != null
                            ? scheme.error
                            : scheme.onSurface.withValues(alpha: 0.65),
                      ),
                    ),
                  ),
                  if (controller.isProcessing)
                    Text(
                      '${(controller.progress * 100).round()}%',
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: controller.isProcessing || controller.progress > 0
                      ? controller.progress
                      : 0,
                  minHeight: 6,
                  backgroundColor: scheme.surfaceContainerHighest,
                ),
              ),
              const SizedBox(height: 16),
            ],
            if (controller.hasFailed && !controller.isProcessing) ...[
              OutlinedButton.icon(
                onPressed: controller.retryFailed,
                icon: const Icon(Icons.refresh_rounded),
                label: Text(strings['retryFailed']),
              ),
              const SizedBox(height: 10),
            ],
            FilledButton.icon(
              onPressed: controller.isProcessing
                  ? controller.requestStop
                  : controller.tasks.isEmpty
                  ? null
                  : controller.process,
              icon: Icon(
                controller.isProcessing
                    ? Icons.stop_circle_outlined
                    : textMode
                    ? (controller.mode == ProcessMode.scramble
                          ? Icons.code_rounded
                          : Icons.settings_backup_restore_rounded)
                    : controller.mode == ProcessMode.scramble
                    ? Icons.grid_view_rounded
                    : Icons.auto_fix_high_outlined,
              ),
              label: Text(
                controller.isProcessing
                    ? strings['cancel']
                    : textMode
                    ? (controller.mode == ProcessMode.scramble
                          ? strings['startTextEncode']
                          : strings['startTextRestore'])
                    : controller.mode == ProcessMode.scramble
                    ? strings['startScramble']
                    : strings['startRestore'],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyQueue extends StatelessWidget {
  const _EmptyQueue({required this.strings, required this.textMode});
  final AppStrings strings;
  final bool textMode;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(16),
      ),
      alignment: Alignment.center,
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            textMode
                ? Icons.description_outlined
                : Icons.photo_size_select_actual_outlined,
            size: 38,
            color: scheme.onSurface.withValues(alpha: 0.28),
          ),
          const SizedBox(height: 12),
          Text(
            textMode ? strings['emptyTextQueue'] : strings['emptyQueue'],
            style: const TextStyle(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 6),
          Text(
            textMode
                ? strings['emptyTextQueueDesc']
                : strings['emptyQueueDesc'],
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 12,
              height: 1.5,
              color: scheme.onSurface.withValues(alpha: 0.65),
            ),
          ),
        ],
      ),
    );
  }
}

class _TaskRow extends StatelessWidget {
  const _TaskRow({
    required this.task,
    required this.strings,
    required this.textMode,
  });
  final ImageTask task;
  final AppStrings strings;
  final bool textMode;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final (icon, color, label) = switch (task.status) {
      TaskStatus.queued => (
        Icons.schedule_rounded,
        scheme.onSurface.withValues(alpha: 0.65),
        strings['queued'],
      ),
      TaskStatus.processing => (
        Icons.sync_rounded,
        scheme.primary,
        strings['processing'],
      ),
      TaskStatus.completed => (
        Icons.check_circle_outline_rounded,
        scheme.secondary,
        strings['completed'],
      ),
      TaskStatus.failed => (
        Icons.error_outline_rounded,
        scheme.error,
        strings['failed'],
      ),
    };
    final location = task.relativeDirectory.isEmpty
        ? task.originalName
        : '${task.relativeDirectory}/${task.originalName}';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 11),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.24),
        borderRadius: BorderRadius.circular(13),
        border: Border.all(
          color: task.status == TaskStatus.failed
              ? scheme.error.withValues(alpha: 0.35)
              : scheme.outlineVariant,
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: scheme.primary.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(11),
            ),
            child: Icon(
              textMode ? Icons.description_outlined : Icons.image_outlined,
              size: 20,
              color: scheme.primary,
            ),
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  location,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  task.error ?? _formatBytes(task.sizeBytes),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 10.5,
                    color: task.error == null
                        ? scheme.onSurface.withValues(alpha: 0.65)
                        : scheme.error,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Tooltip(
            message: label,
            child: Icon(icon, color: color, size: 21, semanticLabel: label),
          ),
        ],
      ),
    );
  }

  String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
}

class _UpdateBanner extends StatelessWidget {
  const _UpdateBanner({required this.strings});
  final AppStrings strings;

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<AppController>();
    final update = controller.availableUpdate!;
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: scheme.primary.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: scheme.primary.withValues(alpha: 0.25)),
      ),
      child: Row(
        children: [
          Icon(Icons.system_update_alt_rounded, color: scheme.primary),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              '${strings['updateAvailable']} v${update.latestVersion}',
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
          ),
          TextButton(
            onPressed: controller.openUpdate,
            child: Text(strings['downloadUpdate']),
          ),
          IconButton(
            tooltip: strings['dismiss'],
            onPressed: controller.dismissUpdate,
            icon: const Icon(Icons.close_rounded),
          ),
        ],
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({required this.icon, required this.title});
  final IconData icon;
  final String title;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 19, color: scheme.primary),
        const SizedBox(width: 9),
        Flexible(
          child: Text(
            title,
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w900),
          ),
        ),
      ],
    );
  }
}

class LogoMark extends StatelessWidget {
  const LogoMark({super.key, this.size = 44});
  final double size;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Langbai Image Scrambler',
      image: true,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xff6d8bff), Color(0xff3f5ee8)],
          ),
          borderRadius: BorderRadius.circular(size * 0.3),
          boxShadow: [
            BoxShadow(
              color: const Color(0xff5277ff).withValues(alpha: 0.28),
              blurRadius: 18,
              offset: const Offset(0, 7),
            ),
          ],
        ),
        alignment: Alignment.center,
        child: Icon(
          Icons.auto_awesome_mosaic_rounded,
          size: size * 0.52,
          color: Colors.white,
        ),
      ),
    );
  }
}

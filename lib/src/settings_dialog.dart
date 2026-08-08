import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'app_controller.dart';
import 'app_settings.dart';
import 'app_strings.dart';
import 'app_version.dart';

Future<void> showSettingsDialog(BuildContext context) {
  return showDialog<void>(
    context: context,
    barrierDismissible: true,
    builder: (_) => const _SettingsDialog(),
  );
}

class _SettingsDialog extends StatelessWidget {
  const _SettingsDialog();

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<AppSettings>();
    final controller = context.watch<AppController>();
    final strings = AppStrings(settings.language);
    final scheme = Theme.of(context).colorScheme;
    final size = MediaQuery.sizeOf(context);
    return Dialog(
      insetPadding: EdgeInsets.symmetric(
        horizontal: size.width < 600 ? 12 : 32,
        vertical: size.height < 700 ? 12 : 32,
      ),
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 720,
          maxHeight: mathMin(size.height - 24, 820),
        ),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(22, 18, 12, 14),
              child: Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: scheme.primary.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(13),
                    ),
                    child: Icon(Icons.tune_rounded, color: scheme.primary),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      strings['settings'],
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w900,
                      ),
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
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(22),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _SettingsSection(
                      icon: Icons.translate_rounded,
                      title: strings['language'],
                      child: SegmentedButton<AppLanguage>(
                        segments: [
                          ButtonSegment(
                            value: AppLanguage.simplified,
                            label: Text(strings['simplifiedChinese']),
                          ),
                          ButtonSegment(
                            value: AppLanguage.traditional,
                            label: Text(strings['traditionalChinese']),
                          ),
                        ],
                        selected: {settings.language},
                        onSelectionChanged: (value) =>
                            settings.setLanguage(value.first),
                        showSelectedIcon: false,
                        style: const ButtonStyle(
                          minimumSize: WidgetStatePropertyAll(Size(130, 48)),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    _SettingsSection(
                      icon: Icons.palette_outlined,
                      title: strings['appearance'],
                      child: Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          _ThemeChoice(
                            value: AppThemePreference.system,
                            icon: Icons.brightness_auto_outlined,
                            label: strings['systemTheme'],
                          ),
                          _ThemeChoice(
                            value: AppThemePreference.light,
                            icon: Icons.light_mode_outlined,
                            label: strings['lightTheme'],
                          ),
                          _ThemeChoice(
                            value: AppThemePreference.dark,
                            icon: Icons.dark_mode_outlined,
                            label: strings['darkTheme'],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    _SettingsSection(
                      icon: Icons.drive_folder_upload_outlined,
                      title: strings['exportSettings'],
                      child: Column(
                        children: [
                          SwitchListTile(
                            contentPadding: EdgeInsets.zero,
                            value: settings.askExportEveryTime,
                            onChanged: settings.setAskExportEveryTime,
                            title: Text(
                              strings['askEveryTime'],
                              style: const TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            subtitle: Text(
                              strings['askEveryTimeDesc'],
                              style: const TextStyle(fontSize: 12),
                            ),
                          ),
                          if (!settings.askExportEveryTime)
                            Container(
                              margin: const EdgeInsets.only(top: 8),
                              padding: const EdgeInsets.fromLTRB(14, 10, 8, 10),
                              decoration: BoxDecoration(
                                color: scheme.surfaceContainerHighest
                                    .withValues(alpha: 0.35),
                                borderRadius: BorderRadius.circular(14),
                                border: Border.all(
                                  color: scheme.outlineVariant,
                                ),
                              ),
                              child: Row(
                                children: [
                                  const Icon(Icons.folder_outlined, size: 21),
                                  const SizedBox(width: 11),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          strings['defaultExport'],
                                          style: const TextStyle(
                                            fontSize: 12,
                                            fontWeight: FontWeight.w800,
                                          ),
                                        ),
                                        const SizedBox(height: 3),
                                        Text(
                                          settings.defaultExportLabel ??
                                              strings['notSelected'],
                                          maxLines: 2,
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(
                                            fontSize: 11,
                                            color: scheme.onSurface.withValues(
                                              alpha: 0.58,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  TextButton(
                                    onPressed: () async {
                                      final selection = await controller
                                          .fileService
                                          .chooseDefaultExport();
                                      if (selection != null) {
                                        await settings.setDefaultExport(
                                          path: selection.path,
                                          treeUri: selection.treeUri,
                                          label: selection.label,
                                        );
                                      }
                                    },
                                    child: Text(strings['choose']),
                                  ),
                                ],
                              ),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    _SettingsSection(
                      icon: Icons.history_toggle_off_rounded,
                      title: strings['historySettings'],
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          DropdownButtonFormField<int>(
                            initialValue: settings.historyRetentionDays,
                            decoration: InputDecoration(
                              labelText: strings['historyRetention'],
                              prefixIcon: const Icon(Icons.schedule_rounded),
                            ),
                            items: [
                              DropdownMenuItem(
                                value: 1,
                                child: Text(strings['retention1']),
                              ),
                              DropdownMenuItem(
                                value: 7,
                                child: Text(strings['retention7']),
                              ),
                              DropdownMenuItem(
                                value: 30,
                                child: Text(strings['retention30']),
                              ),
                              DropdownMenuItem(
                                value: 90,
                                child: Text(strings['retention90']),
                              ),
                              DropdownMenuItem(
                                value: 0,
                                child: Text(strings['retentionForever']),
                              ),
                            ],
                            onChanged: (value) {
                              if (value != null) {
                                controller.setHistoryRetentionDays(value);
                              }
                            },
                          ),
                          const SizedBox(height: 8),
                          Text(
                            strings['historyRetentionDesc'],
                            style: TextStyle(
                              fontSize: 11.5,
                              height: 1.5,
                              color: scheme.onSurface.withValues(alpha: 0.65),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    _SettingsSection(
                      icon: Icons.speed_rounded,
                      title: strings['performance'],
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          DropdownButtonFormField<int>(
                            initialValue: settings.processingConcurrency,
                            decoration: InputDecoration(
                              labelText: strings['concurrency'],
                              prefixIcon: const Icon(
                                Icons.dynamic_feed_rounded,
                              ),
                            ),
                            items: [
                              DropdownMenuItem(
                                value: 0,
                                child: Text(strings['concurrencyAuto']),
                              ),
                              DropdownMenuItem(
                                value: 1,
                                child: Text(strings['concurrency1']),
                              ),
                              DropdownMenuItem(
                                value: 2,
                                child: Text(strings['concurrency2']),
                              ),
                              DropdownMenuItem(
                                value: 4,
                                child: Text(strings['concurrency4']),
                              ),
                              DropdownMenuItem(
                                value: 8,
                                child: Text(strings['concurrency8']),
                              ),
                            ],
                            onChanged: (value) {
                              if (value != null) {
                                controller.setProcessingConcurrency(value);
                              }
                            },
                          ),
                          const SizedBox(height: 8),
                          Text(
                            '${strings['concurrencyDesc']}\n'
                            '${strings['concurrencyNow']}：'
                            '${controller.effectiveProcessingConcurrency}',
                            style: TextStyle(
                              fontSize: 11.5,
                              height: 1.5,
                              color: scheme.onSurface.withValues(alpha: 0.65),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    _SettingsSection(
                      icon: Icons.system_update_alt_rounded,
                      title: strings['updates'],
                      child: Column(
                        children: [
                          SwitchListTile(
                            contentPadding: EdgeInsets.zero,
                            value: settings.checkUpdates,
                            onChanged: settings.setCheckUpdates,
                            title: Text(
                              strings['checkUpdates'],
                              style: const TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            subtitle: Text(
                              '${strings['currentVersion']} ${AppVersion.current}',
                              style: const TextStyle(fontSize: 12),
                            ),
                          ),
                          const SizedBox(height: 8),
                          Align(
                            alignment: Alignment.centerLeft,
                            child: OutlinedButton.icon(
                              onPressed: controller.checkingUpdate
                                  ? null
                                  : () async {
                                      final found = await controller
                                          .checkForUpdates();
                                      if (!context.mounted) return;
                                      ScaffoldMessenger.of(
                                        context,
                                      ).showSnackBar(
                                        SnackBar(
                                          content: Text(
                                            found
                                                ? strings['updateAvailable']
                                                : strings[controller.statusKey],
                                          ),
                                        ),
                                      );
                                    },
                              icon: controller.checkingUpdate
                                  ? const SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                      ),
                                    )
                                  : const Icon(Icons.refresh_rounded),
                              label: Text(strings['checkNow']),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    _SettingsSection(
                      icon: Icons.shield_outlined,
                      title: strings['privacyTitle'],
                      child: Text(
                        strings['privacyDesc'],
                        style: TextStyle(
                          fontSize: 13,
                          height: 1.65,
                          color: scheme.onSurface.withValues(alpha: 0.65),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.all(16),
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
    );
  }

  double mathMin(double left, double right) => left < right ? left : right;
}

class _SettingsSection extends StatelessWidget {
  const _SettingsSection({
    required this.icon,
    required this.title,
    required this.child,
  });

  final IconData icon;
  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.surfaceContainerHighest.withValues(alpha: 0.18),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(17),
        side: BorderSide(color: scheme.outlineVariant),
      ),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(icon, size: 19, color: scheme.primary),
                const SizedBox(width: 9),
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            child,
          ],
        ),
      ),
    );
  }
}

class _ThemeChoice extends StatelessWidget {
  const _ThemeChoice({
    required this.value,
    required this.icon,
    required this.label,
  });

  final AppThemePreference value;
  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<AppSettings>();
    final selected = settings.theme == value;
    final scheme = Theme.of(context).colorScheme;
    return ChoiceChip(
      selected: selected,
      onSelected: (_) => settings.setTheme(value),
      avatar: Icon(
        icon,
        size: 18,
        color: selected
            ? scheme.onPrimary
            : scheme.onSurface.withValues(alpha: 0.65),
      ),
      label: Text(label),
      labelStyle: TextStyle(
        fontWeight: FontWeight.w700,
        color: selected ? scheme.onPrimary : null,
      ),
      selectedColor: scheme.primary,
      showCheckmark: false,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      side: BorderSide(
        color: selected ? scheme.primary : scheme.outlineVariant,
      ),
    );
  }
}

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:langbai_image_scrambler/src/app.dart';
import 'package:langbai_image_scrambler/src/app_controller.dart';
import 'package:langbai_image_scrambler/src/app_settings.dart';
import 'package:langbai_image_scrambler/src/export_history.dart';
import 'package:langbai_image_scrambler/src/models.dart';
import 'package:langbai_image_scrambler/src/password_vault.dart';
import 'package:langbai_image_scrambler/src/shared_import_dialog.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _runGoldens = bool.fromEnvironment('RUN_GOLDENS');

void main() {
  setUpAll(() async {
    final loader = FontLoader('NotoSansCJKSC')
      ..addFont(rootBundle.load('assets/fonts/NotoSansCJKsc-Regular.otf'));
    final traditionalLoader = FontLoader('NotoSansCJKTC')
      ..addFont(rootBundle.load('assets/fonts/NotoSansCJKtc-Regular.otf'));
    final iconLoader = FontLoader('MaterialIcons')
      ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
    await Future.wait([
      loader.load(),
      traditionalLoader.load(),
      iconLoader.load(),
    ]);
  });

  Future<void> render(
    WidgetTester tester,
    Size size,
    String output, {
    bool openAlgorithmPicker = false,
    bool textWorkspace = false,
    bool restoreMode = false,
    bool passwordEnabled = false,
    bool openSettings = false,
    bool scrollSettingsToBottom = false,
    bool openHistory = false,
    bool populatedHistory = false,
    bool multiFolderQueue = false,
    bool openSharedImport = false,
    bool compressionEnabled = false,
    bool openPasswordVault = false,
    String theme = 'dark',
    String language = 'simplified',
    double textScaleFactor = 1,
  }) async {
    SharedPreferences.setMockInitialValues({
      'check_updates': false,
      'theme': theme,
      'language': language,
      'compression_enabled': compressionEnabled,
    });
    final settings = await AppSettings.load();
    final passwordVault = await PasswordVault.load(
      storage: MemoryPasswordStorage(),
    );
    if (compressionEnabled || openPasswordVault) {
      await passwordVault.add(name: '常用密码', password: 'golden-one');
      await passwordVault.add(name: '投稿压缩包', password: 'golden-two');
    }
    final history = ExportHistoryStore.memory();
    if (populatedHistory) {
      await history.add(
        ExportHistoryEntry(
          id: 'golden-history',
          createdAt: DateTime(2026, 8, 8, 20, 30),
          workspaceType: WorkspaceType.image,
          mode: ProcessMode.scramble,
          targetLabel: r'D:\图片输出\画集（1）',
          artifacts: const [
            ExportArtifact(
              location: r'D:\图片输出\画集（1）\封面.png',
              displayName: '封面.png',
              sha256: 'golden',
              sizeBytes: 1024,
            ),
            ExportArtifact(
              location: r'D:\图片输出\画集（1）\插图.png',
              displayName: '插图.png',
              sha256: 'golden',
              sizeBytes: 2048,
            ),
          ],
          createdDirectories: const [],
        ),
      );
    }
    final controller = AppController(
      settings,
      historyStore: history,
      passwordVault: passwordVault,
    );
    if (textWorkspace) controller.setWorkspaceType(WorkspaceType.text);
    if (restoreMode) controller.setMode(ProcessMode.restore);
    if (passwordEnabled) controller.setPasswordEnabled(true);
    if (multiFolderQueue) {
      controller.batch = ImportBatch(
        tasks: [
          _folderTask('a', '封面.png', '画集A', 'root-a'),
          _folderTask('b', '插图.png', '画集A', 'root-a'),
          _folderTask('c', '第一章.png', '画集B', 'root-b'),
        ],
        isFolder: true,
        rootName: '画集A',
      );
    }
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = size;
    tester.platformDispatcher.textScaleFactorTestValue = textScaleFactor;
    addTearDown(() {
      tester.view.resetDevicePixelRatio();
      tester.view.resetPhysicalSize();
      tester.platformDispatcher.clearTextScaleFactorTestValue();
    });
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider.value(value: settings),
          ChangeNotifierProvider.value(value: controller),
          ChangeNotifierProvider.value(value: passwordVault),
        ],
        child: RepaintBoundary(
          child: LangbaiApp(
            platformOverride: size.width < 600
                ? TargetPlatform.android
                : TargetPlatform.windows,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.getSize(find.byType(Scaffold)), size);
    expect(MediaQuery.sizeOf(tester.element(find.byType(Scaffold))), size);
    if (openSharedImport) {
      final request = SharedImportRequest(
        id: 'golden-share',
        items: const [
          SharedImportItem(
            name: '小说图片合集.zip',
            uri: 'content://golden/archive-1',
            sizeBytes: 1024 * 1024 * 18,
          ),
          SharedImportItem(
            name: '插图补充.rar',
            uri: 'content://golden/archive-2',
            sizeBytes: 1024 * 1024 * 6,
          ),
          SharedImportItem(
            name: '番外章节',
            uri: 'content://golden/folder',
            isDirectory: true,
          ),
        ],
      );
      unawaited(
        showSharedImportDialog(tester.element(find.byType(Scaffold)), request),
      );
      await tester.pumpAndSettle();
    }
    if (openAlgorithmPicker) {
      final field = find.byKey(const ValueKey('algorithm-picker-field'));
      await tester.ensureVisible(field);
      await tester.pumpAndSettle();
      await tester.tap(field);
      await tester.pumpAndSettle();
    }
    if (compressionEnabled) {
      final compression = find.text('压缩输出');
      await tester.ensureVisible(compression);
      await tester.pumpAndSettle();
    }
    if (openPasswordVault) {
      await tester.tap(find.text('管理密码'));
      await tester.pumpAndSettle();
    }
    if (openSettings) {
      if (size.width < 960) {
        final label = language == 'traditional' ? '設定' : '设置';
        await tester.tap(find.byTooltip(label));
      } else {
        await tester.tap(find.byIcon(Icons.tune_rounded).first);
      }
      await tester.pumpAndSettle();
      if (scrollSettingsToBottom) {
        await tester.drag(
          find.byType(SingleChildScrollView).last,
          const Offset(0, -1200),
        );
        await tester.pumpAndSettle();
      }
    }
    if (multiFolderQueue && size.width < 960) {
      await tester.ensureVisible(find.text('画集A'));
      await tester.pumpAndSettle();
    }
    if (openHistory) {
      final label = language == 'traditional' ? '匯出記錄' : '导出记录';
      if (size.width < 960) {
        await tester.tap(find.byTooltip(label));
      } else {
        await tester.tap(find.text(label));
      }
      await tester.pumpAndSettle();
    }
    await expectLater(find.byType(MaterialApp), matchesGoldenFile(output));
  }

  testWidgets(
    'desktop 1440x900',
    (tester) => render(
      tester,
      const Size(1440, 900),
      'goldens/home_desktop_1440x900.png',
    ),
    skip: !_runGoldens,
  );

  testWidgets(
    'android 390x844',
    (tester) => render(
      tester,
      const Size(390, 844),
      'goldens/home_android_390x844.png',
    ),
    skip: !_runGoldens,
  );

  testWidgets(
    'desktop algorithm picker',
    (tester) => render(
      tester,
      const Size(1440, 900),
      'goldens/algorithm_picker_desktop.png',
      openAlgorithmPicker: true,
    ),
    skip: !_runGoldens,
  );

  testWidgets(
    'android algorithm picker',
    (tester) => render(
      tester,
      const Size(390, 844),
      'goldens/algorithm_picker_android.png',
      openAlgorithmPicker: true,
    ),
    skip: !_runGoldens,
  );

  testWidgets(
    'desktop TXT workspace',
    (tester) => render(
      tester,
      const Size(1440, 900),
      'goldens/text_workspace_desktop.png',
      textWorkspace: true,
    ),
    skip: !_runGoldens,
  );

  testWidgets(
    'android TXT workspace',
    (tester) => render(
      tester,
      const Size(390, 844),
      'goldens/text_workspace_android.png',
      textWorkspace: true,
    ),
    skip: !_runGoldens,
  );

  testWidgets(
    'desktop settings top',
    (tester) => render(
      tester,
      const Size(1440, 900),
      'goldens/settings_desktop_top.png',
      openSettings: true,
    ),
    skip: !_runGoldens,
  );

  testWidgets(
    'desktop settings bottom',
    (tester) => render(
      tester,
      const Size(1440, 900),
      'goldens/settings_desktop_bottom.png',
      openSettings: true,
      scrollSettingsToBottom: true,
    ),
    skip: !_runGoldens,
  );

  testWidgets(
    'android settings top',
    (tester) => render(
      tester,
      const Size(390, 844),
      'goldens/settings_android_top.png',
      openSettings: true,
    ),
    skip: !_runGoldens,
  );

  testWidgets(
    'android settings bottom',
    (tester) => render(
      tester,
      const Size(390, 844),
      'goldens/settings_android_bottom.png',
      openSettings: true,
      scrollSettingsToBottom: true,
    ),
    skip: !_runGoldens,
  );

  testWidgets(
    'android image restore workspace',
    (tester) => render(
      tester,
      const Size(390, 844),
      'goldens/image_restore_android.png',
      restoreMode: true,
    ),
    skip: !_runGoldens,
  );

  testWidgets(
    'desktop password workspace',
    (tester) => render(
      tester,
      const Size(1440, 900),
      'goldens/password_desktop.png',
      passwordEnabled: true,
    ),
    skip: !_runGoldens,
  );

  testWidgets(
    'android light theme',
    (tester) => render(
      tester,
      const Size(390, 844),
      'goldens/home_android_light.png',
      theme: 'light',
    ),
    skip: !_runGoldens,
  );

  testWidgets(
    'desktop traditional Chinese TXT workspace',
    (tester) => render(
      tester,
      const Size(1440, 900),
      'goldens/text_workspace_desktop_traditional.png',
      textWorkspace: true,
      language: 'traditional',
    ),
    skip: !_runGoldens,
  );

  testWidgets(
    'small Android portrait',
    (tester) => render(
      tester,
      const Size(360, 640),
      'goldens/home_android_360x640.png',
    ),
    skip: !_runGoldens,
  );

  testWidgets(
    'Android landscape',
    (tester) => render(
      tester,
      const Size(844, 390),
      'goldens/home_android_landscape.png',
    ),
    skip: !_runGoldens,
  );

  testWidgets(
    'Android enlarged text',
    (tester) => render(
      tester,
      const Size(390, 844),
      'goldens/home_android_large_text.png',
      textScaleFactor: 1.3,
    ),
    skip: !_runGoldens,
  );

  testWidgets(
    'desktop export history',
    (tester) => render(
      tester,
      const Size(1440, 900),
      'goldens/export_history_desktop.png',
      openHistory: true,
      populatedHistory: true,
    ),
    skip: !_runGoldens,
  );

  testWidgets(
    'Android export history',
    (tester) => render(
      tester,
      const Size(390, 844),
      'goldens/export_history_android.png',
      openHistory: true,
      populatedHistory: true,
    ),
    skip: !_runGoldens,
  );

  testWidgets(
    'desktop collapsed multi-folder queue',
    (tester) => render(
      tester,
      const Size(1440, 900),
      'goldens/multi_folder_queue_desktop.png',
      multiFolderQueue: true,
    ),
    skip: !_runGoldens,
  );

  testWidgets(
    'Android collapsed multi-folder queue',
    (tester) => render(
      tester,
      const Size(390, 844),
      'goldens/multi_folder_queue_android.png',
      multiFolderQueue: true,
    ),
    skip: !_runGoldens,
  );

  testWidgets(
    'Android shared archive import',
    (tester) => render(
      tester,
      const Size(390, 844),
      'goldens/shared_import_android.png',
      openSharedImport: true,
    ),
    skip: !_runGoldens,
  );

  testWidgets(
    'small Android shared archive import',
    (tester) => render(
      tester,
      const Size(360, 640),
      'goldens/shared_import_android_360x640.png',
      openSharedImport: true,
    ),
    skip: !_runGoldens,
  );

  testWidgets(
    'Android compression output settings',
    (tester) => render(
      tester,
      const Size(390, 844),
      'goldens/compression_android.png',
      compressionEnabled: true,
    ),
    skip: !_runGoldens,
  );

  testWidgets(
    'small Android compression output settings',
    (tester) => render(
      tester,
      const Size(360, 640),
      'goldens/compression_android_360x640.png',
      compressionEnabled: true,
    ),
    skip: !_runGoldens,
  );

  testWidgets(
    'desktop compression output settings',
    (tester) => render(
      tester,
      const Size(1440, 900),
      'goldens/compression_desktop.png',
      compressionEnabled: true,
    ),
    skip: !_runGoldens,
  );

  testWidgets(
    'Android password vault',
    (tester) => render(
      tester,
      const Size(390, 844),
      'goldens/password_vault_android.png',
      compressionEnabled: true,
      openPasswordVault: true,
    ),
    skip: !_runGoldens,
  );
}

ImageTask _folderTask(String id, String name, String rootName, String rootId) =>
    ImageTask(
      id: id,
      originalName: name,
      relativeDirectory: '',
      sourceRootName: rootName,
      sourceRootId: rootId,
    );

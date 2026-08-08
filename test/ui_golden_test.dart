import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:langbai_image_scrambler/src/app.dart';
import 'package:langbai_image_scrambler/src/app_controller.dart';
import 'package:langbai_image_scrambler/src/app_settings.dart';
import 'package:langbai_image_scrambler/src/models.dart';
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
    String theme = 'dark',
    String language = 'simplified',
    double textScaleFactor = 1,
  }) async {
    SharedPreferences.setMockInitialValues({
      'check_updates': false,
      'theme': theme,
      'language': language,
    });
    final settings = await AppSettings.load();
    final controller = AppController(settings);
    if (textWorkspace) controller.setWorkspaceType(WorkspaceType.text);
    if (restoreMode) controller.setMode(ProcessMode.restore);
    if (passwordEnabled) controller.setPasswordEnabled(true);
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
    if (openAlgorithmPicker) {
      final field = find.byKey(const ValueKey('algorithm-picker-field'));
      await tester.ensureVisible(field);
      await tester.pumpAndSettle();
      await tester.tap(field);
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
          const Offset(0, -720),
        );
        await tester.pumpAndSettle();
      }
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
}

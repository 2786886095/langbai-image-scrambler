import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:langbai_image_scrambler/src/app.dart';
import 'package:langbai_image_scrambler/src/app_controller.dart';
import 'package:langbai_image_scrambler/src/app_settings.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _runGoldens = bool.fromEnvironment('RUN_GOLDENS');

void main() {
  setUpAll(() async {
    final loader = FontLoader('NotoSansCJKSC')
      ..addFont(rootBundle.load('assets/fonts/NotoSansCJKsc-Regular.otf'));
    final iconLoader = FontLoader('MaterialIcons')
      ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
    await Future.wait([loader.load(), iconLoader.load()]);
  });

  Future<void> render(WidgetTester tester, Size size, String output) async {
    SharedPreferences.setMockInitialValues({
      'check_updates': false,
      'theme': 'dark',
      'language': 'simplified',
    });
    final settings = await AppSettings.load();
    final controller = AppController(settings);
    await tester.binding.setSurfaceSize(size);
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider.value(value: settings),
          ChangeNotifierProvider.value(value: controller),
        ],
        child: const RepaintBoundary(child: LangbaiApp()),
      ),
    );
    await tester.pumpAndSettle();
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
}

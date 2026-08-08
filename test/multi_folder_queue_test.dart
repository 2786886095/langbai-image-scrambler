import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:langbai_image_scrambler/src/app.dart';
import 'package:langbai_image_scrambler/src/app_controller.dart';
import 'package:langbai_image_scrambler/src/app_settings.dart';
import 'package:langbai_image_scrambler/src/models.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('multiple imported folders are collapsed by default', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      'check_updates': false,
      'theme': 'dark',
      'language': 'simplified',
    });
    final settings = await AppSettings.load();
    final controller = AppController(settings)
      ..batch = ImportBatch(
        tasks: [
          _task('a', '第一张.png', '画集A', 'root-a'),
          _task('b', '第二张.png', '画集A', 'root-a'),
          _task('c', '第三张.png', '画集B', 'root-b'),
        ],
        isFolder: true,
        rootName: '画集A',
      );
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1280, 820);
    addTearDown(() {
      tester.view.resetDevicePixelRatio();
      tester.view.resetPhysicalSize();
    });
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider.value(value: settings),
          ChangeNotifierProvider.value(value: controller),
        ],
        child: const LangbaiApp(platformOverride: TargetPlatform.windows),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('画集A'), findsOneWidget);
    expect(find.text('画集B'), findsOneWidget);
    expect(find.text('第一张.png'), findsNothing);
    expect(find.text('第三张.png'), findsNothing);

    await tester.ensureVisible(find.text('画集A'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('画集A'));
    await tester.pumpAndSettle();
    expect(find.text('第一张.png'), findsOneWidget);
    expect(find.text('第二张.png'), findsOneWidget);
    expect(find.text('第三张.png'), findsNothing);
  });
}

ImageTask _task(String id, String name, String rootName, String rootId) =>
    ImageTask(
      id: id,
      originalName: name,
      relativeDirectory: '',
      sourceRootName: rootName,
      sourceRootId: rootId,
    );

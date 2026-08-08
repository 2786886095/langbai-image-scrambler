import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:langbai_image_scrambler/src/app.dart';
import 'package:langbai_image_scrambler/src/app_controller.dart';
import 'package:langbai_image_scrambler/src/app_settings.dart';
import 'package:langbai_image_scrambler/src/models.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('TXT workspace hides image settings and exposes Base64 modes', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      'check_updates': false,
      'theme': 'dark',
      'language': 'simplified',
    });
    final settings = await AppSettings.load();
    final controller = AppController(settings);
    await tester.binding.setSurfaceSize(const Size(1280, 820));
    addTearDown(() => tester.binding.setSurfaceSize(null));
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

    await tester.tap(find.text('小说 TXT'));
    await tester.pumpAndSettle();
    expect(controller.workspaceType, WorkspaceType.text);
    expect(find.text('Base64 转码'), findsOneWidget);
    expect(find.text('Base64 恢复'), findsOneWidget);
    expect(find.text('选择 TXT'), findsOneWidget);
    expect(find.byKey(const ValueKey('algorithm-picker-field')), findsNothing);

    await tester.tap(find.text('Base64 恢复'));
    await tester.pumpAndSettle();
    expect(controller.mode, ProcessMode.restore);
    expect(find.text('批量恢复 Base64，原始字节完整不变'), findsOneWidget);
  });
}

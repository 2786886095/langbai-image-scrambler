import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:langbai_image_scrambler/src/app.dart';
import 'package:langbai_image_scrambler/src/app_controller.dart';
import 'package:langbai_image_scrambler/src/app_settings.dart';
import 'package:langbai_image_scrambler/src/models.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  Future<AppController> pumpApp(WidgetTester tester, Size size) async {
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
        child: LangbaiApp(
          platformOverride: size.width < 600
              ? TargetPlatform.android
              : TargetPlatform.windows,
        ),
      ),
    );
    await tester.pumpAndSettle();
    return controller;
  }

  testWidgets('desktop opens a bounded two-column algorithm dialog', (
    tester,
  ) async {
    final controller = await pumpApp(tester, const Size(1280, 820));
    await tester.tap(find.byKey(const ValueKey('algorithm-picker-field')));
    await tester.pumpAndSettle();

    expect(find.byType(Dialog), findsOneWidget);
    expect(find.text('选择混淆算法'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('algorithm-choice-composite')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('algorithm-choice-row_shift')),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const ValueKey('algorithm-choice-row_shift')));
    await tester.pumpAndSettle();
    expect(controller.algorithm, ScrambleAlgorithm.rowShift);
    expect(find.byType(Dialog), findsNothing);
    expect(find.text('行循环位移'), findsOneWidget);
  });

  testWidgets(
    'mobile opens a scrollable bottom sheet and selects an algorithm',
    (tester) async {
      final controller = await pumpApp(tester, const Size(390, 844));
      final field = find.byKey(const ValueKey('algorithm-picker-field'));
      await tester.ensureVisible(field);
      await tester.pumpAndSettle();
      await tester.tap(field);
      await tester.pumpAndSettle();

      expect(find.byType(Dialog), findsNothing);
      expect(find.text('选择混淆算法'), findsOneWidget);
      await tester.tap(
        find.byKey(const ValueKey('algorithm-choice-block_shuffle')),
      );
      await tester.pumpAndSettle();
      expect(controller.algorithm, ScrambleAlgorithm.blockShuffle);
      expect(find.text('选择混淆算法'), findsNothing);
      expect(find.text('网格块打乱'), findsOneWidget);
    },
  );
}

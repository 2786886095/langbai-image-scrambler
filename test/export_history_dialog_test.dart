import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:langbai_image_scrambler/src/app.dart';
import 'package:langbai_image_scrambler/src/app_controller.dart';
import 'package:langbai_image_scrambler/src/app_settings.dart';
import 'package:langbai_image_scrambler/src/export_history.dart';
import 'package:langbai_image_scrambler/src/models.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('history dialog shows export batches and undo confirmation', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      'check_updates': false,
      'theme': 'dark',
      'language': 'simplified',
    });
    final settings = await AppSettings.load();
    final history = ExportHistoryStore.memory();
    await history.add(
      ExportHistoryEntry(
        id: 'history-1',
        createdAt: DateTime(2026, 8, 8, 20, 30),
        workspaceType: WorkspaceType.image,
        mode: ProcessMode.scramble,
        targetLabel: r'D:\输出\画集（1）',
        artifacts: const [
          ExportArtifact(
            location: r'D:\输出\画集（1）\封面.png',
            displayName: '封面.png',
            sha256: 'hash',
            sizeBytes: 100,
          ),
        ],
        createdDirectories: const [],
      ),
    );
    final controller = AppController(settings, historyStore: history);
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

    await tester.tap(find.text('导出记录'));
    await tester.pumpAndSettle();
    expect(find.text('导出与撤回记录'), findsOneWidget);
    expect(find.text(r'D:\输出\画集（1）'), findsOneWidget);
    expect(find.text('打开输出位置'), findsOneWidget);
    expect(find.text('撤回导出'), findsOneWidget);

    await tester.tap(find.text('撤回导出'));
    await tester.pumpAndSettle();
    expect(find.text('撤回这次导出？'), findsOneWidget);
    expect(find.text('取消'), findsOneWidget);
  });
}

import 'package:flutter_test/flutter_test.dart';
import 'package:langbai_image_scrambler/src/app_controller.dart';
import 'package:langbai_image_scrambler/src/app_settings.dart';
import 'package:langbai_image_scrambler/src/models.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('processing configuration is restored after reopening', () async {
    SharedPreferences.setMockInitialValues({'check_updates': false});
    final firstSettings = await AppSettings.load();
    final firstController = AppController(firstSettings);
    firstController.setAlgorithm(ScrambleAlgorithm.pixelPermutation);
    firstController.setPasswordEnabled(true);
    await Future<void>.delayed(Duration.zero);

    final reopenedSettings = await AppSettings.load();
    final reopenedController = AppController(reopenedSettings);
    expect(reopenedController.workspaceType, WorkspaceType.image);
    expect(reopenedController.mode, ProcessMode.scramble);
    expect(reopenedController.algorithm, ScrambleAlgorithm.pixelPermutation);
    expect(reopenedController.passwordEnabled, isTrue);
    expect(reopenedController.password, isEmpty);
    expect(reopenedController.manualSeed, isEmpty);
    expect(reopenedController.tasks, isEmpty);
  });

  test(
    'TXT workspace and restore mode persist without sensitive values',
    () async {
      SharedPreferences.setMockInitialValues({'check_updates': false});
      final settings = await AppSettings.load();
      final controller = AppController(settings);
      controller.setWorkspaceType(WorkspaceType.text);
      controller.setMode(ProcessMode.restore);
      await Future<void>.delayed(Duration.zero);

      final reopened = AppController(await AppSettings.load());
      expect(reopened.workspaceType, WorkspaceType.text);
      expect(reopened.mode, ProcessMode.restore);
      expect(reopened.password, isEmpty);
      expect(reopened.batch, isNull);
    },
  );
}

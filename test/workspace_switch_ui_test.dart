import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:langbai_image_scrambler/src/app.dart';
import 'package:langbai_image_scrambler/src/app_controller.dart';
import 'package:langbai_image_scrambler/src/app_settings.dart';
import 'package:langbai_image_scrambler/src/models.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets(
    'switching TXT and image workspaces restores image field values',
    (tester) async {
      SharedPreferences.setMockInitialValues({
        'check_updates': false,
        'theme': 'dark',
        'language': 'simplified',
      });
      final settings = await AppSettings.load();
      final controller = AppController(settings);
      controller.setAlgorithm(ScrambleAlgorithm.pixelPermutation);
      controller.setPasswordEnabled(true);
      controller.setPassword('remember-me');
      await tester.binding.setSurfaceSize(const Size(1280, 900));
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

      controller.setWorkspaceType(WorkspaceType.text);
      controller.setMode(ProcessMode.restore);
      await tester.pumpAndSettle();
      controller.setWorkspaceType(WorkspaceType.image);
      await tester.pumpAndSettle();

      expect(controller.mode, ProcessMode.scramble);
      expect(controller.algorithm, ScrambleAlgorithm.pixelPermutation);
      expect(controller.passwordEnabled, isTrue);
      final passwordField = tester.widget<TextField>(
        find.byKey(const ValueKey('image-password-field')),
      );
      expect(passwordField.controller?.text, 'remember-me');
    },
  );
}

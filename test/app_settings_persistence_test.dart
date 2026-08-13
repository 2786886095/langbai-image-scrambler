import 'package:flutter_test/flutter_test.dart';
import 'package:langbai_image_scrambler/src/app_controller.dart';
import 'package:langbai_image_scrambler/src/app_settings.dart';
import 'package:langbai_image_scrambler/src/models.dart';
import 'package:langbai_image_scrambler/src/password_vault.dart';
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
    'restore round trip keeps the image scramble algorithm and password toggle',
    () async {
      SharedPreferences.setMockInitialValues({'check_updates': false});
      final controller = AppController(await AppSettings.load());
      controller.setAlgorithm(ScrambleAlgorithm.pixelPermutation);
      controller.setPasswordEnabled(true);

      controller.setMode(ProcessMode.restore);
      expect(controller.algorithm, ScrambleAlgorithm.auto);
      expect(controller.passwordEnabled, isFalse);
      controller.setMode(ProcessMode.scramble);
      expect(controller.algorithm, ScrambleAlgorithm.pixelPermutation);
      expect(controller.passwordEnabled, isTrue);
      await Future<void>.delayed(Duration.zero);

      final reopened = AppController(await AppSettings.load());
      expect(reopened.mode, ProcessMode.scramble);
      expect(reopened.algorithm, ScrambleAlgorithm.pixelPermutation);
      expect(reopened.passwordEnabled, isTrue);
    },
  );

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

  test('compression choices and selected password profile persist', () async {
    SharedPreferences.setMockInitialValues({'check_updates': false});
    final settings = await AppSettings.load();
    await settings.setCompressionEnabled(true);
    await settings.setCompressionFormat(CompressionArchiveFormat.sevenZip);
    await settings.setCompressionGrouping(CompressionGrouping.combined);
    await settings.setSelectedArchivePasswordProfile('profile-a');

    final reopened = await AppSettings.load();
    expect(reopened.compressionEnabled, isTrue);
    expect(reopened.compressionFormat, CompressionArchiveFormat.sevenZip);
    expect(reopened.compressionGrouping, CompressionGrouping.combined);
    expect(reopened.selectedArchivePasswordProfileId, 'profile-a');
  });
  test(
    'image and TXT keep independent complete profiles across switches and reopening',
    () async {
      SharedPreferences.setMockInitialValues({'check_updates': false});
      final passwordStorage = MemoryPasswordStorage();
      final passwordVault = await PasswordVault.load(storage: passwordStorage);
      final imageArchivePassword = await passwordVault.add(
        name: 'image archive',
        password: 'image-archive-secret',
      );
      final textArchivePassword = await passwordVault.add(
        name: 'text archive',
        password: 'text-archive-secret',
      );
      final settings = await AppSettings.load();
      final controller = AppController(settings, passwordVault: passwordVault);

      controller.setAlgorithm(ScrambleAlgorithm.pixelPermutation);
      controller.setPasswordEnabled(true);
      controller.setPassword('image-parameter-secret');
      controller.setManualSeed('24680');
      await controller.setCompressionEnabled(true);
      await controller.setCompressionFormat(CompressionArchiveFormat.sevenZip);
      await controller.setCompressionGrouping(CompressionGrouping.combined);
      await controller.setArchivePasswordProfile(imageArchivePassword.id);

      controller.setWorkspaceType(WorkspaceType.text);
      expect(controller.mode, ProcessMode.scramble);
      expect(controller.compressionEnabled, isFalse);
      await controller.setCompressionEnabled(true);
      await controller.setCompressionGrouping(CompressionGrouping.perFile);
      await controller.setArchivePasswordProfile(textArchivePassword.id);
      controller.setMode(ProcessMode.restore);
      await Future<void>.delayed(Duration.zero);

      controller.setWorkspaceType(WorkspaceType.image);
      expect(controller.mode, ProcessMode.scramble);
      expect(controller.algorithm, ScrambleAlgorithm.pixelPermutation);
      expect(controller.passwordEnabled, isTrue);
      expect(controller.password, 'image-parameter-secret');
      expect(controller.manualSeed, '24680');
      expect(controller.compressionEnabled, isTrue);
      expect(controller.compressionFormat, CompressionArchiveFormat.sevenZip);
      expect(controller.compressionGrouping, CompressionGrouping.combined);
      expect(
        controller.selectedArchivePasswordProfile?.id,
        imageArchivePassword.id,
      );

      controller.setWorkspaceType(WorkspaceType.text);
      expect(controller.mode, ProcessMode.restore);
      expect(controller.compressionEnabled, isTrue);
      expect(controller.compressionFormat, CompressionArchiveFormat.zip);
      expect(controller.compressionGrouping, CompressionGrouping.perFile);
      expect(
        controller.selectedArchivePasswordProfile?.id,
        textArchivePassword.id,
      );
      await Future<void>.delayed(Duration.zero);

      final reopenedVault = await PasswordVault.load(storage: passwordStorage);
      final reopened = AppController(
        await AppSettings.load(),
        passwordVault: reopenedVault,
      );
      expect(reopened.workspaceType, WorkspaceType.text);
      expect(reopened.mode, ProcessMode.restore);
      expect(reopened.compressionGrouping, CompressionGrouping.perFile);
      expect(
        reopened.selectedArchivePasswordProfile?.id,
        textArchivePassword.id,
      );

      reopened.setWorkspaceType(WorkspaceType.image);
      expect(reopened.mode, ProcessMode.scramble);
      expect(reopened.algorithm, ScrambleAlgorithm.pixelPermutation);
      expect(reopened.passwordEnabled, isTrue);
      expect(reopened.password, 'image-parameter-secret');
      expect(reopened.manualSeed, '24680');
      expect(reopened.compressionFormat, CompressionArchiveFormat.sevenZip);
      expect(reopened.compressionGrouping, CompressionGrouping.combined);
      expect(
        reopened.selectedArchivePasswordProfile?.id,
        imageArchivePassword.id,
      );
    },
  );

  test(
    'legacy global configuration migrates into the last workspace',
    () async {
      SharedPreferences.setMockInitialValues({
        'check_updates': false,
        'last_workspace_type': 'text',
        'last_process_mode': 'restore',
        'last_algorithm': 'row_shift',
        'compression_enabled': true,
        'compression_format': 'sevenZip',
        'compression_grouping': 'combined',
        'selected_archive_password_profile': 'legacy-profile',
      });

      final settings = await AppSettings.load();
      final textProfile = settings.profileFor(WorkspaceType.text);
      final imageProfile = settings.profileFor(WorkspaceType.image);
      expect(textProfile.mode, ProcessMode.restore);
      expect(textProfile.algorithm, ScrambleAlgorithm.rowShift);
      expect(textProfile.compressionEnabled, isTrue);
      expect(textProfile.compressionFormat, CompressionArchiveFormat.sevenZip);
      expect(textProfile.compressionGrouping, CompressionGrouping.combined);
      expect(textProfile.selectedArchivePasswordProfileId, 'legacy-profile');
      expect(imageProfile.mode, ProcessMode.scramble);
      expect(imageProfile.algorithm, ScrambleAlgorithm.composite);
      expect(imageProfile.compressionEnabled, isFalse);
    },
  );
}

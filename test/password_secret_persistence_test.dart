import 'package:flutter_test/flutter_test.dart';
import 'package:langbai_image_scrambler/src/password_vault.dart';

void main() {
  test(
    'image processing password and manual seed use secure persistence',
    () async {
      final storage = MemoryPasswordStorage();
      final vault = await PasswordVault.load(storage: storage);
      await vault.setImageProcessingPassword('parameter-secret');
      await vault.setImageManualSeed('13579');

      final reopened = await PasswordVault.load(storage: storage);
      expect(reopened.imageProcessingPassword, 'parameter-secret');
      expect(reopened.imageManualSeed, '13579');
      expect(
        storage.values[PasswordVault.imageProcessingPasswordKey],
        isNotNull,
      );
      expect(storage.values[PasswordVault.imageManualSeedKey], isNotNull);
    },
  );
}

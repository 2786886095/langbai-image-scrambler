import 'package:flutter_test/flutter_test.dart';
import 'package:langbai_image_scrambler/src/password_vault.dart';

void main() {
  test(
    'password vault persists multiple profiles without exposing a list field',
    () async {
      final storage = MemoryPasswordStorage();
      final vault = await PasswordVault.load(storage: storage);
      final first = await vault.add(name: '常用', password: 'alpha');
      final second = await vault.add(name: '投稿', password: 'beta');
      await vault.update(second.id, name: '投稿包', password: 'gamma');

      final reopened = await PasswordVault.load(storage: storage);
      expect(reopened.find(first.id)?.password, 'alpha');
      expect(reopened.find(second.id)?.name, '投稿包');
      expect(reopened.find(second.id)?.password, 'gamma');
      await reopened.delete(first.id);
      expect(reopened.find(first.id), isNull);
      expect(storage.values.keys, [PasswordVault.storageKey]);
    },
  );

  test('password profile names are unique', () async {
    final vault = await PasswordVault.load(storage: MemoryPasswordStorage());
    await vault.add(name: '常用', password: 'alpha');
    expect(() => vault.add(name: '常用', password: 'beta'), throwsArgumentError);
  });
}

import 'package:flutter_test/flutter_test.dart';
import 'package:langbai_image_scrambler/src/export_history.dart';
import 'package:langbai_image_scrambler/src/models.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('history defaults can clean records older than seven days', () async {
    final now = DateTime(2026, 8, 8, 12);
    final store = ExportHistoryStore.memory(now: () => now);
    ExportHistoryEntry entry(String id, DateTime createdAt) =>
        ExportHistoryEntry(
          id: id,
          createdAt: createdAt,
          workspaceType: WorkspaceType.image,
          mode: ProcessMode.scramble,
          targetLabel: id,
          artifacts: const [],
          createdDirectories: const [],
        );
    await store.add(entry('old', now.subtract(const Duration(days: 8))));
    await store.add(entry('recent', now.subtract(const Duration(days: 2))));

    expect(await store.cleanup(7), 1);
    expect(store.entries.map((item) => item.id), ['recent']);
  });

  test('zero-day policy keeps history forever', () async {
    final now = DateTime(2026, 8, 8, 12);
    final store = ExportHistoryStore.memory(now: () => now);
    await store.add(
      ExportHistoryEntry(
        id: 'old',
        createdAt: now.subtract(const Duration(days: 900)),
        workspaceType: WorkspaceType.text,
        mode: ProcessMode.restore,
        targetLabel: 'old',
        artifacts: const [],
        createdDirectories: const [],
      ),
    );
    expect(await store.cleanup(0), 0);
    expect(store.entries, hasLength(1));
  });

  test('history and undo status persist across app restarts', () async {
    SharedPreferences.setMockInitialValues({});
    final now = DateTime(2026, 8, 8, 12);
    final first = await ExportHistoryStore.load(
      retentionDays: 7,
      now: () => now,
    );
    await first.add(
      ExportHistoryEntry(
        id: 'saved',
        createdAt: now,
        workspaceType: WorkspaceType.image,
        mode: ProcessMode.scramble,
        targetLabel: '输出',
        artifacts: const [
          ExportArtifact(
            location: 'file.png',
            displayName: 'file.png',
            sha256: 'hash',
            sizeBytes: 12,
          ),
        ],
        createdDirectories: const ['folder'],
        revealLocation: 'folder',
        revealIsDirectory: true,
      ),
    );

    final reopened = await ExportHistoryStore.load(
      retentionDays: 7,
      now: () => now,
    );
    expect(reopened.entries.single.id, 'saved');
    expect(reopened.entries.single.locationToReveal, 'folder');
    expect(reopened.entries.single.locationIsDirectory, isTrue);
    await reopened.markUndone(
      'saved',
      const UndoResult(deleted: 1, modified: 0),
    );
    final afterUndo = await ExportHistoryStore.load(
      retentionDays: 7,
      now: () => now,
    );
    expect(afterUndo.entries.single.canUndo, isFalse);
    expect(afterUndo.entries.single.deletedCount, 1);
  });
}

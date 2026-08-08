import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:langbai_image_scrambler/src/file_service.dart';
import 'package:langbai_image_scrambler/src/models.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('com.langbai.imagescrambler/saf');

  tearDown(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test('shared request recognizes folders, archives, images, and TXT', () {
    final request = SharedImportRequest.fromMap({
      'id': 'share-1',
      'items': [
        {'uri': 'content://folder', 'name': '小说图包', 'isDirectory': true},
        {'uri': 'content://archive', 'name': '加密图包.7z'},
        {'uri': 'content://image', 'name': '封面.png'},
        {'uri': 'content://text', 'name': '正文.TXT'},
      ],
    });

    expect(request.id, 'share-1');
    expect(request.items[0].isDirectory, isTrue);
    expect(request.items[1].isArchive, isTrue);
    expect(request.items[2].isImage, isTrue);
    expect(request.items[3].isText, isTrue);
    expect(request.archives.single.name, '加密图包.7z');
  });

  test(
    'archive import creates a mixed folder batch and preserves roots',
    () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            expect(call.method, 'extractArchive');
            expect(call.arguments['password'], 'archive-secret');
            return {
              'rootName': '小说图包',
              'temporaryRoot': r'C:\cache\archive-1',
              'skippedCount': 2,
              'items': [
                {
                  'path': r'C:\cache\archive-1\小说图包\第一章\封面.png',
                  'name': '封面.png',
                  'relativeDirectory': '第一章',
                  'size': 100,
                  'kind': 'image',
                },
                {
                  'path': r'C:\cache\archive-1\小说图包\第一章\正文.txt',
                  'name': '正文.txt',
                  'relativeDirectory': '第一章',
                  'size': 200,
                  'kind': 'text',
                },
              ],
            };
          });
      final service = FileService();
      const request = SharedImportRequest(
        id: 'share-2',
        items: [
          SharedImportItem(name: '小说图包.rar', uri: 'content://archive/1'),
          SharedImportItem(name: '忽略.bin', uri: 'content://ignored'),
        ],
      );

      final batch = await service.importShared(
        request,
        archivePasswords: const {'content://archive/1': 'archive-secret'},
      );

      expect(batch.isFolder, isTrue);
      expect(batch.rootName, '小说图包');
      expect(batch.workspaceType, WorkspaceType.mixed);
      expect(batch.isMixed, isTrue);
      expect(batch.skippedCount, 3);
      expect(batch.temporaryRoots, [r'C:\cache\archive-1']);
      expect(batch.tasks.map((task) => task.workspaceType), [
        WorkspaceType.image,
        WorkspaceType.text,
      ]);
      expect(batch.tasks.map((task) => task.relativeDirectory).toSet(), {
        '第一章',
      });
    },
  );

  test('mixed batch reports image and text content independently', () {
    final batch = ImportBatch(
      tasks: [
        ImageTask(
          id: 'image',
          originalName: 'a.png',
          relativeDirectory: '',
          sourceRootName: 'root',
        ),
        ImageTask(
          id: 'text',
          originalName: 'a.txt',
          relativeDirectory: '',
          sourceRootName: 'root',
          workspaceType: WorkspaceType.text,
        ),
      ],
      isFolder: true,
      rootName: 'root',
      workspaceType: WorkspaceType.mixed,
    );

    expect(batch.containsImages, isTrue);
    expect(batch.containsText, isTrue);
    expect(batch.isMixed, isTrue);
  });
}

import 'package:flutter_test/flutter_test.dart';
import 'package:langbai_image_scrambler/src/models.dart';
import 'package:langbai_image_scrambler/src/video/video_batch.dart';

void main() {
  VideoBatchOutput output(
    String id,
    String root,
    String relative,
    String name,
  ) => VideoBatchOutput(
    input: VideoBatchInput(
      id: id,
      name: name,
      sourceRootId: root,
      sourceRootName: root,
      relativeDirectory: relative,
      sourcePath: 'C:/$id/$name',
    ),
    path: 'C:/out/$id/$name',
    outputName: name,
  );

  test(
    'per-folder video archives preserve original folder names and paths',
    () {
      final groups = planVideoArchives(
        outputs: [
          output('1', '小说视频', '第一章', '01.mp4'),
          output('2', '小说视频', '第二章', '02.mp4'),
          output('3', '漫画视频', '', '01.mp4'),
        ],
        grouping: CompressionGrouping.perFolder,
      );
      expect(groups.map((item) => item.baseName), ['小说视频', '漫画视频']);
      expect(groups.first.entries.first.archivePath, '第一章/01.mp4');
    },
  );

  test('combined video archive includes each source root', () {
    final groups = planVideoArchives(
      outputs: [
        output('1', '小说视频', '', '01.mp4'),
        output('2', '漫画视频', '', '01.mp4'),
      ],
      grouping: CompressionGrouping.combined,
      now: DateTime(2026, 8, 17, 20, 0, 1),
    );
    expect(groups.single.baseName, 'Langbai_视频混淆_20260817_200001');
    expect(groups.single.entries.map((item) => item.archivePath), [
      '小说视频/01.mp4',
      '漫画视频/01.mp4',
    ]);
  });

  test('combined standalone videos never overwrite duplicate names', () {
    final first = output('1', '', '', '同名.mp4');
    final second = output('2', '', '', '同名.mp4');
    final groups = planVideoArchives(
      outputs: [first, second],
      grouping: CompressionGrouping.combined,
      now: DateTime(2026, 8, 17),
    );
    expect(groups.single.entries.map((item) => item.archivePath), [
      '同名.mp4',
      '同名（1）.mp4',
    ]);
  });
}

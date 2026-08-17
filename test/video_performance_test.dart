import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:langbai_image_scrambler/src/video/video_models.dart';
import 'package:langbai_image_scrambler/src/video/video_processor.dart';

void main() {
  test('performance mode ids remain persistent and backwards compatible', () {
    expect(
      VideoPerformanceModeX.fromId('full'),
      VideoPerformanceMode.fullPower,
    );
    expect(VideoPerformanceModeX.fromId(null), VideoPerformanceMode.normal);
    expect(VideoPerformanceMode.fullPower.id, 'full');
  });

  test('full power uses more real frame workers for 1080p', () {
    final normal = computeVideoWorkerCount(
      performanceMode: VideoPerformanceMode.normal,
      width: 1920,
      height: 1080,
      android: false,
      logicalProcessors: 16,
    );
    final full = computeVideoWorkerCount(
      performanceMode: VideoPerformanceMode.fullPower,
      width: 1920,
      height: 1080,
      android: false,
      logicalProcessors: 16,
    );
    expect(normal, 4);
    expect(full, greaterThan(normal));
  });

  test(
    '4K Android full power remains memory bounded',
    () {
      final workers = computeVideoWorkerCount(
        performanceMode: VideoPerformanceMode.fullPower,
        width: 3840,
        height: 2160,
        android: true,
        logicalProcessors: 8,
      );
      expect(workers, inInclusiveRange(1, 4));
    },
    skip: !Platform.isWindows && !Platform.isLinux && !Platform.isMacOS,
  );
}

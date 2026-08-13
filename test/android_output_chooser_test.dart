import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'Android output navigation uses an app chooser instead of a tree picker',
    () {
      final source = File(
        'android/app/src/main/kotlin/com/langbai/langbai_image_scrambler/MainActivity.kt',
      ).readAsStringSync();
      final start = source.indexOf('private fun openOutputLocation(');
      final end = source.indexOf('private fun findChild(', start);
      final method = source.substring(start, end);

      expect(method, contains('Intent.createChooser'));
      expect(method, contains('queryIntentActivities'));
      expect(method, contains('fallbackUri'));
      expect(method, isNot(contains('ACTION_OPEN_DOCUMENT_TREE')));
      expect(method, isNot(contains('ACTION_OPEN_DOCUMENT')));
    },
  );
}

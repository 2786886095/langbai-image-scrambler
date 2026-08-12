import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Windows Setup always exposes the installation directory page', () {
    final script = File(
      'installer/langbai-image-scrambler.iss',
    ).readAsStringSync();

    expect(script, contains('DisableDirPage=no'));
    expect(
      script,
      contains(r'DefaultDirName={localappdata}\Programs\{#MyDefaultDirName}'),
    );
    expect(script, contains('PrivilegesRequired=lowest'));
  });

  test('Windows bundle installs the native update helper', () {
    final rootCmake = File('windows/CMakeLists.txt').readAsStringSync();
    final runnerCmake = File(
      'windows/runner/CMakeLists.txt',
    ).readAsStringSync();

    expect(rootCmake, contains('install(TARGETS langbai_update_helper'));
    expect(runnerCmake, contains('add_executable(langbai_update_helper'));
    expect(runnerCmake, contains('update_helper.cpp'));
  });
}

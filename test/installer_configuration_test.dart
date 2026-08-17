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

  test('Windows starts at 1302x842 and persists later window bounds', () {
    final header = File('windows/runner/window_state.h').readAsStringSync();
    final implementation = File(
      'windows/runner/window_state.cpp',
    ).readAsStringSync();
    final runner = File('windows/runner/main.cpp').readAsStringSync();

    expect(header, contains('int width = 1302'));
    expect(header, contains('int height = 842'));
    expect(runner, contains('LoadWindowState()'));
    expect(implementation, contains('GetWindowPlacement'));
    expect(implementation, contains('RegSetValueEx'));
  });

  test('Windows bundle contains the verified local yt-dlp parser', () {
    final rootCmake = File('windows/CMakeLists.txt').readAsStringSync();
    expect(rootCmake, contains('yt-dlp.exe'));
    expect(File('assets/bin/windows/yt-dlp.exe').lengthSync(), 18226085);
  });
}

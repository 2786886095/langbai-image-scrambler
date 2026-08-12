import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:langbai_image_scrambler/src/update_service.dart';

void main() {
  test('check selects the Windows setup asset and GitHub digest', () async {
    final packageBytes = utf8.encode('windows package');
    final digest = sha256.convert(packageBytes).toString();
    final client = MockClient((request) async {
      expect(request.url.path, contains('/releases/latest'));
      return http.Response(
        jsonEncode({
          'tag_name': 'v9.9.9',
          'html_url': 'https://github.test/releases/v9.9.9',
          'body': 'notes',
          'assets': [
            {
              'name': 'Langbai-v9.9.9-android.apk',
              'browser_download_url': 'https://download.test/app.apk',
            },
            {
              'name': 'Langbai-Setup-v9.9.9.exe',
              'browser_download_url': 'https://download.test/setup.exe',
              'digest': 'sha256:$digest',
            },
            {
              'name': 'SHA256SUMS.txt',
              'browser_download_url': 'https://download.test/checksums',
            },
          ],
        }),
        200,
      );
    });
    final service = UpdateService(
      client: client,
      platform: UpdatePlatform.windows,
    );

    final info = await service.check();

    expect(info, isNotNull);
    expect(info!.assetName, 'Langbai-Setup-v9.9.9.exe');
    expect(info.downloadUrl, Uri.parse('https://download.test/setup.exe'));
    expect(info.sha256Digest, digest);
    expect(info.checksumUrl, Uri.parse('https://download.test/checksums'));
  });

  test('download verifies SHA256SUMS before invoking installer', () async {
    final packageBytes = utf8.encode('verified apk package');
    final digest = sha256.convert(packageBytes).toString();
    Directory? temporaryRoot;
    var installed = false;
    final stages = <UpdateStage>[];
    final client = MockClient((request) async {
      if (request.url.path.endsWith('/app.apk')) {
        return http.Response.bytes(packageBytes, 200);
      }
      if (request.url.path.endsWith('/SHA256SUMS.txt')) {
        return http.Response('$digest  Langbai-v9.9.9-android.apk\n', 200);
      }
      return http.Response('missing', 404);
    });
    final service = UpdateService(
      client: client,
      platform: UpdatePlatform.android,
      installerOverride: (package) async {
        installed = true;
        temporaryRoot = package.parent;
        expect(await package.readAsBytes(), packageBytes);
      },
    );
    final info = UpdateInfo(
      currentVersion: '1.2.3',
      latestVersion: '9.9.9',
      releaseUrl: Uri.parse('https://github.test/releases/v9.9.9'),
      downloadUrl: Uri.parse('https://download.test/app.apk'),
      assetName: 'Langbai-v9.9.9-android.apk',
      releaseNotes: '',
      checksumUrl: Uri.parse('https://download.test/SHA256SUMS.txt'),
    );

    await service.downloadAndInstall(
      info,
      onProgress: (progress) => stages.add(progress.stage),
    );

    expect(installed, isTrue);
    expect(stages, containsAllInOrder(UpdateStage.values));
    if (temporaryRoot case final root?) {
      if (await root.exists()) await root.delete(recursive: true);
    }
  });

  test('digest mismatch blocks installation', () async {
    var installed = false;
    final client = MockClient(
      (_) async => http.Response.bytes(utf8.encode('tampered'), 200),
    );
    final service = UpdateService(
      client: client,
      platform: UpdatePlatform.windows,
      installerOverride: (_) async => installed = true,
    );
    final info = UpdateInfo(
      currentVersion: '1.2.3',
      latestVersion: '9.9.9',
      releaseUrl: Uri.parse('https://github.test/releases/v9.9.9'),
      downloadUrl: Uri.parse('https://download.test/setup.exe'),
      assetName: 'Langbai-Setup-v9.9.9.exe',
      releaseNotes: '',
      sha256Digest: List.filled(64, '0').join(),
    );

    await expectLater(
      service.downloadAndInstall(info),
      throwsA(
        isA<UpdateException>().having(
          (error) => error.message,
          'message',
          contains('校验失败'),
        ),
      ),
    );
    expect(installed, isFalse);
  });

  test('Windows update copies and launches the native helper', () async {
    final executableDirectory = File(Platform.resolvedExecutable).parent;
    final helperSource = File(
      '${executableDirectory.path}${Platform.pathSeparator}'
      'langbai_update_helper.exe',
    );
    final helperPreviouslyExisted = await helperSource.exists();
    final previousBytes = helperPreviouslyExisted
        ? await helperSource.readAsBytes()
        : null;
    await helperSource.writeAsBytes(utf8.encode('test helper'), flush: true);
    final packageBytes = utf8.encode('verified setup package');
    final digest = sha256.convert(packageBytes).toString();
    String? launchedHelper;
    List<String>? launchedArguments;
    Directory? temporaryRoot;
    try {
      final service = UpdateService(
        client: MockClient((_) async => http.Response.bytes(packageBytes, 200)),
        platform: UpdatePlatform.windows,
        windowsLauncherOverride: (helper, arguments) async {
          launchedHelper = helper;
          launchedArguments = arguments;
          temporaryRoot = File(helper).parent;
          await File(arguments[5]).writeAsString('ready\n', flush: true);
          return 2468;
        },
      );
      final info = UpdateInfo(
        currentVersion: '1.2.4',
        latestVersion: '9.9.9',
        releaseUrl: Uri.parse('https://github.test/releases/v9.9.9'),
        downloadUrl: Uri.parse('https://download.test/setup.exe'),
        assetName: 'Langbai-Setup-v9.9.9.exe',
        releaseNotes: '',
        sha256Digest: digest,
      );

      await service.downloadAndInstall(info);

      expect(launchedHelper, isNotNull);
      expect(await File(launchedHelper!).readAsString(), 'test helper');
      expect(launchedArguments, hasLength(6));
      expect(launchedArguments![0], endsWith('Langbai-Setup-v9.9.9.exe'));
      expect(launchedArguments![1], pid.toString());
      expect(launchedArguments![2], executableDirectory.path);
      expect(launchedArguments![3], Platform.resolvedExecutable);
      expect(launchedArguments![4], endsWith('update.log'));
      expect(launchedArguments![5], endsWith('helper.ready'));
    } finally {
      if (temporaryRoot case final root?) {
        if (await root.exists()) await root.delete(recursive: true);
      }
      if (previousBytes != null) {
        await helperSource.writeAsBytes(previousBytes, flush: true);
      } else if (await helperSource.exists()) {
        await helperSource.delete();
      }
    }
  });

  test(
    'older Windows build launches Setup silently without closing itself',
    () async {
      final executableDirectory = File(Platform.resolvedExecutable).parent;
      final helperSource = File(
        '${executableDirectory.path}${Platform.pathSeparator}'
        'langbai_update_helper.exe',
      );
      final helperPreviouslyExisted = await helperSource.exists();
      final previousBytes = helperPreviouslyExisted
          ? await helperSource.readAsBytes()
          : null;
      if (helperPreviouslyExisted) await helperSource.delete();
      final packageBytes = utf8.encode('legacy setup package');
      final digest = sha256.convert(packageBytes).toString();
      String? launchedInstaller;
      List<String>? launchedArguments;
      Directory? temporaryRoot;
      try {
        final service = UpdateService(
          client: MockClient(
            (_) async => http.Response.bytes(packageBytes, 200),
          ),
          platform: UpdatePlatform.windows,
          windowsLauncherOverride: (installer, arguments) async {
            launchedInstaller = installer;
            launchedArguments = arguments;
            temporaryRoot = File(installer).parent;
            return 1357;
          },
        );
        final info = UpdateInfo(
          currentVersion: '1.2.4',
          latestVersion: '9.9.9',
          releaseUrl: Uri.parse('https://github.test/releases/v9.9.9'),
          downloadUrl: Uri.parse('https://download.test/setup.exe'),
          assetName: 'Langbai-Setup-v9.9.9.exe',
          releaseNotes: '',
          sha256Digest: digest,
        );

        await service.downloadAndInstall(info);

        expect(launchedInstaller, endsWith('Langbai-Setup-v9.9.9.exe'));
        expect(launchedArguments, contains('/VERYSILENT'));
        expect(launchedArguments, contains('/SUPPRESSMSGBOXES'));
        expect(launchedArguments, contains('/CLOSEAPPLICATIONS'));
        expect(launchedArguments, contains('/RESTARTAPPLICATIONS'));
        expect(
          launchedArguments!.any((argument) => argument.startsWith('/DIR=')),
          isTrue,
        );
      } finally {
        if (temporaryRoot case final root?) {
          if (await root.exists()) await root.delete(recursive: true);
        }
        if (previousBytes != null) {
          await helperSource.writeAsBytes(previousBytes, flush: true);
        }
      }
    },
  );
}

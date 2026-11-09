import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:alice_dictation/services/apk_installer.dart';
import 'package:alice_dictation/services/app_update.dart';
import 'package:alice_dictation/services/app_update_install.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

class _TempPathProvider extends PathProviderPlatform {
  _TempPathProvider(this.root);
  final Directory root;

  @override
  Future<String?> getTemporaryPath() async => root.path;
}

void main() {
  late Directory tmp;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('alice_update_');
    PathProviderPlatform.instance = _TempPathProvider(tmp);
  });

  tearDown(() async {
    if (await tmp.exists()) await tmp.delete(recursive: true);
  });

  const info = AppUpdateInfo(
    version: '0.10.2',
    build: 2025,
    url: 'https://alice.file.wenfu.dev/alice-0.10.2.apk',
    notes: 'test',
  );

  test('下载完成后调起安装器', () async {
    final bytes = Uint8List.fromList(List<int>.generate(2048, (i) => i % 256));
    final progress = <double?>[];
    final client = MockClient((request) async {
      expect(request.url.toString(), info.url);
      return http.Response.bytes(bytes, 200, headers: {
        HttpHeaders.contentLengthHeader: '${bytes.length}',
      });
    });

    String? installedPath;
    final result = await downloadAndInstallUpdate(
      info,
      client: client,
      onProgress: progress.add,
      install: (path) async {
        installedPath = path;
        final file = File(path);
        expect(await file.exists(), isTrue);
        expect(await file.length(), bytes.length);
        return ApkInstallResult.launched;
      },
    );

    expect(result.status, AppUpdateInstallStatus.launched);
    expect(installedPath, endsWith('alice-0.10.2+2025.apk'));
    expect(progress, isNotEmpty);
    expect(progress.last, 1.0);
  });

  test('需要安装权限时保留本地 APK', () async {
    final client = MockClient(
      (_) async => http.Response.bytes(utf8.encode('apk-bytes'), 200),
    );

    final result = await downloadAndInstallUpdate(
      info,
      client: client,
      install: (_) async => ApkInstallResult.needPermission,
    );

    expect(result.status, AppUpdateInstallStatus.needPermission);
    expect(result.path, isNotNull);
    expect(await File(result.path!).exists(), isTrue);
  });

  test('HTTP 失败不留半截文件', () async {
    final client = MockClient(
      (_) async => http.Response('nope', 404),
    );

    final result = await downloadAndInstallUpdate(
      info,
      client: client,
      install: (_) async => ApkInstallResult.launched,
    );

    expect(result.status, AppUpdateInstallStatus.failed);
    final dir = Directory('${tmp.path}/alice_updates');
    if (await dir.exists()) {
      expect(dir.listSync(), isEmpty);
    }
  });
}

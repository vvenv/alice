import 'dart:convert';
import 'dart:io';

import 'package:alice_dictation/services/app_update.dart';
import 'package:alice_dictation/services/prefs.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 应用内更新提示：version.json 的解析、版本比较、「稍后 / 跳过」。
void main() {
  WidgetsFlutterBinding.ensureInitialized();

  const apk = 'https://file.wenfu.dev/alice-0.9.1-20261019-1200.apk';

  http.Client serve(Object body, {int status = 200}) => MockClient(
        (_) async => http.Response.bytes(
          utf8.encode(body is String ? body : jsonEncode(body)),
          status,
        ),
      );

  Map<String, Object> manifest({int build = 23}) =>
      {'version': '0.9.1', 'build': build, 'url': apk, 'notes': ' 修复 A '};

  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await Prefs.init();
    // Prefs 攥着第一次拿到的实例，setMockInitialValues 换掉的是新实例 ——
    // 上一条留下的「稍后 / 跳过」得经 Prefs 自己删。
    await Prefs.remove('alice_update_snoozed_at');
    await Prefs.remove('alice_update_skipped_build');
    PackageInfo.setMockInitialValues(
      appName: 'Alice',
      packageName: 'com.vvenv.alice',
      version: '0.9.0',
      buildNumber: '22',
      buildSignature: '',
    );
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
  });

  tearDown(() => debugDefaultTargetPlatformOverride = null);

  group('version.json 解析', () {
    test('合法的清单', () {
      final info = AppUpdateInfo.fromJson(manifest())!;
      expect(info.version, '0.9.1');
      expect(info.build, 23);
      expect(info.url, apk);
      expect(info.notes, '修复 A');
    });

    test('缺字段、类型不对、地址不是 https 都当作没有更新', () {
      expect(AppUpdateInfo.fromJson(null), isNull);
      expect(AppUpdateInfo.fromJson({'version': '0.9.1', 'url': apk}), isNull);
      expect(AppUpdateInfo.fromJson({...manifest(), 'build': '23'}), isNull);
      expect(
        AppUpdateInfo.fromJson(
            {...manifest(), 'url': 'http://evil.example/a.apk'}),
        isNull,
      );
    });
  });

  group('fetchAvailableUpdate', () {
    test('build 更大才算有更新', () async {
      expect(
        await fetchAvailableUpdate(currentBuild: 22, client: serve(manifest())),
        isNotNull,
      );
      expect(
        await fetchAvailableUpdate(currentBuild: 23, client: serve(manifest())),
        isNull,
      );
    });

    test('HTTP 错误要抛出来 —— 手动检查得区分「失败」和「已是最新」', () {
      expect(
        fetchAvailableUpdate(currentBuild: 22, client: serve('', status: 404)),
        throwsA(isA<http.ClientException>()),
      );
    });
  });

  group('启动时自动检查', () {
    test('有新版就返回', () async {
      final info = await checkUpdateOnLaunch(client: serve(manifest()));
      expect(info?.build, 23);
    });

    test('网络失败静默返回 null', () async {
      final info =
          await checkUpdateOnLaunch(client: serve('oops', status: 500));
      expect(info, isNull);
    });

    test('「稍后」一天内不再弹，过了一天照常', () async {
      final t = DateTime(2026, 10, 19, 9);
      await snoozeUpdate(now: t);

      expect(
        await checkUpdateOnLaunch(
            client: serve(manifest()), now: t.add(const Duration(hours: 3))),
        isNull,
      );
      expect(
        await checkUpdateOnLaunch(
            client: serve(manifest()),
            now: t.add(kUpdateSnooze + const Duration(minutes: 1))),
        isNotNull,
      );
    });

    test('「跳过此版本」只跳这一版，更新的版本照常提示', () async {
      final info = (await checkUpdateOnLaunch(client: serve(manifest())))!;
      await skipUpdate(info);

      expect(await checkUpdateOnLaunch(client: serve(manifest())), isNull);
      expect(
        await checkUpdateOnLaunch(client: serve(manifest(build: 24))),
        isNotNull,
      );
    });

    test('非 Android 不检查', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      expect(await checkUpdateOnLaunch(client: serve(manifest())), isNull);
    });
  });

  // 发版脚本写的、App 读的是同一份文件 —— 字段名对不上，提示就永远不会出现。
  test('仓库里的 version.json 能被 App 解析', () {
    final json =
        jsonDecode(File('website/public/version.json').readAsStringSync());
    expect(AppUpdateInfo.fromJson(json), isNotNull);
  });
}

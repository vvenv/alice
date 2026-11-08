import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';

import 'logger.dart';
import 'prefs.dart';

/// 应用内更新提示。
///
/// APK 不走应用商店，装上之后用户只能自己回官网看有没有新版。发版脚本
/// （scripts/release.sh）每次会把最新版本写进官网根目录的 version.json：
///
///     {"version": "0.10.1", "build": 2024, "url": "https://…/alice-0.10.1-….apk",
///      "notes": "…"}
///
/// 这里拉它、和本机的 versionCode 比较，新了就提示用户更新。下载在应用内完成，
/// 再经 FileProvider 调起系统安装器（`app_update_install.dart` /
/// `apk_installer.dart`）。需要 `REQUEST_INSTALL_PACKAGES`；用户得允许
/// 「安装未知应用」。
///
/// 只比 build（versionCode）不比 version 字符串：Android 认的就是它，
/// 它比本机小的包根本装不上。`build` 必须是 APK 里的真实 versionCode——
/// `--split-per-abi` 会给 arm64 加上 2000，不能写 pubspec 里那个裸的 +N。
const _log = Logger('AppUpdate');

const String kUpdateManifestUrl = 'https://alice.wenfu.dev/version.json';

const String _skippedBuildKey = 'alice_update_skipped_build';
const String _snoozedAtKey = 'alice_update_snoozed_at';

/// 「稍后」之后多久不再自动弹。手动检查不受影响。
const Duration kUpdateSnooze = Duration(days: 1);

const Duration _timeout = Duration(seconds: 8);

class AppUpdateInfo {
  const AppUpdateInfo({
    required this.version,
    required this.build,
    required this.url,
    this.notes = '',
  });

  final String version;
  final int build;
  final String url;
  final String notes;

  /// 字段缺失 / 类型不对 / 地址不是 https 时返回 null —— 宁可不提示，
  /// 也不要把用户带到一个奇怪的地址去。
  static AppUpdateInfo? fromJson(Object? json) {
    if (json is! Map) return null;
    final version = json['version'];
    final build = json['build'];
    final url = json['url'];
    final notes = json['notes'];
    if (version is! String || version.isEmpty) return null;
    if (build is! int || build <= 0) return null;
    if (url is! String || !url.startsWith('https://')) return null;
    return AppUpdateInfo(
      version: version,
      build: build,
      url: url,
      notes: notes is String ? notes.trim() : '',
    );
  }
}

/// 只有 Android 的 APK 需要。Web 每次打开就是最新的；iOS 还没有发版渠道。
bool get isAppUpdateSupported =>
    !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

/// 本机的 versionCode。拿不到时返回 null（测试环境、插件异常）。
Future<int?> currentBuildNumber() async {
  try {
    final info = await PackageInfo.fromPlatform();
    return int.tryParse(info.buildNumber);
  } catch (_) {
    return null;
  }
}

/// 拉一次 version.json。有比 [currentBuild] 新的版本时返回它，否则 null。
///
/// 网络失败抛异常 —— 手动检查要告诉用户「检查失败」，和「已是最新」不是
/// 一回事；自动检查由调用方吞掉。
Future<AppUpdateInfo?> fetchAvailableUpdate({
  required int currentBuild,
  http.Client? client,
}) async {
  final c = client ?? http.Client();
  try {
    final response = await c.get(Uri.parse(kUpdateManifestUrl),
        headers: const {'Cache-Control': 'no-cache'}).timeout(_timeout);
    if (response.statusCode != 200) {
      throw http.ClientException('HTTP ${response.statusCode}');
    }
    final info =
        AppUpdateInfo.fromJson(jsonDecode(utf8.decode(response.bodyBytes)));
    if (info == null) {
      _log.warn('version.json 格式不对');
      return null;
    }
    return info.build > currentBuild ? info : null;
  } finally {
    if (client == null) c.close();
  }
}

/// 启动时的自动检查：失败、被跳过、还在「稍后」期内都返回 null，不打扰。
Future<AppUpdateInfo?> checkUpdateOnLaunch({
  http.Client? client,
  DateTime? now,
}) async {
  if (!isAppUpdateSupported) return null;

  final snoozedAt = int.tryParse(await Prefs.getString(_snoozedAtKey) ?? '');
  final t = now ?? DateTime.now();
  if (snoozedAt != null) {
    final since = t.difference(DateTime.fromMillisecondsSinceEpoch(snoozedAt));
    // 时间倒着走（用户改过系统时间）就当没「稍后」过，免得一直不提示。
    if (!since.isNegative && since < kUpdateSnooze) return null;
  }

  final current = await currentBuildNumber();
  if (current == null) return null;

  AppUpdateInfo? info;
  try {
    info = await fetchAvailableUpdate(currentBuild: current, client: client);
  } catch (e) {
    _log.warn('检查更新失败: $e');
    return null;
  }
  if (info == null) return null;

  final skipped = int.tryParse(await Prefs.getString(_skippedBuildKey) ?? '');
  if (skipped != null && info.build <= skipped) return null;
  return info;
}

/// 「稍后」：一段时间内不再自动弹。
Future<void> snoozeUpdate({DateTime? now}) => Prefs.setString(
      _snoozedAtKey,
      '${(now ?? DateTime.now()).millisecondsSinceEpoch}',
    );

/// 「跳过此版本」：这一版不再自动弹，更新的版本照常提示。
Future<void> skipUpdate(AppUpdateInfo info) =>
    Prefs.setString(_skippedBuildKey, '${info.build}');

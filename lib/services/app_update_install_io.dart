import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

import 'apk_installer.dart';
import 'app_update.dart';
import 'logger.dart';

const _log = Logger('AppUpdateInstall');

/// 应用内下载 APK 并调起系统安装器。
///
/// [onProgress] 的参数是 0..1；拿不到 Content-Length 时传 null（不定进度）。
/// [install] 可注入，方便测试；默认走 [ApkInstaller.install]。
Future<AppUpdateInstallResult> downloadAndInstallUpdate(
  AppUpdateInfo info, {
  void Function(double? progress)? onProgress,
  http.Client? client,
  Future<ApkInstallResult> Function(String path)? install,
}) async {
  final ownsClient = client == null;
  final c = client ?? http.Client();
  File? apk;
  try {
    apk = await _downloadApk(info, client: c, onProgress: onProgress);
    final outcome = await (install ?? ApkInstaller.install)(apk.path);
    switch (outcome) {
      case ApkInstallResult.launched:
        return AppUpdateInstallResult(
          status: AppUpdateInstallStatus.launched,
          path: apk.path,
        );
      case ApkInstallResult.needPermission:
        return AppUpdateInstallResult(
          status: AppUpdateInstallStatus.needPermission,
          path: apk.path,
        );
      case ApkInstallResult.failed:
      case ApkInstallResult.unavailable:
        return AppUpdateInstallResult(
          status: AppUpdateInstallStatus.failed,
          path: apk.path,
          error: '无法调起系统安装器',
        );
    }
  } catch (e) {
    _log.warn('下载/安装更新失败: $e');
    // 半截文件留着只会骗下次「好像下完了」，直接删。
    try {
      await apk?.delete();
    } catch (_) {}
    return AppUpdateInstallResult(
      status: AppUpdateInstallStatus.failed,
      error: e.toString(),
    );
  } finally {
    if (ownsClient) c.close();
  }
}

Future<File> _downloadApk(
  AppUpdateInfo info, {
  required http.Client client,
  void Function(double? progress)? onProgress,
}) async {
  final dir = Directory(
      '${(await getTemporaryDirectory()).path}/alice_updates');
  if (!await dir.exists()) {
    await dir.create(recursive: true);
  }
  final target = File('${dir.path}/alice-${info.version}+${info.build}.apk');

  final request = http.Request('GET', Uri.parse(info.url));
  request.headers['Cache-Control'] = 'no-cache';
  final response = await client.send(request).timeout(const Duration(minutes: 5));
  if (response.statusCode != 200) {
    throw HttpException('HTTP ${response.statusCode}', uri: request.url);
  }

  final total = response.contentLength ?? -1;
  // 先写到 .part，成功后再 rename，避免下次误把半截包当完整包装。
  final part = File('${target.path}.part');
  if (await part.exists()) await part.delete();
  final sink = part.openWrite();
  var received = 0;
  try {
    await for (final chunk in response.stream) {
      sink.add(chunk);
      received += chunk.length;
      if (onProgress != null) {
        onProgress(total > 0 ? (received / total).clamp(0.0, 1.0) : null);
      }
    }
    await sink.flush();
  } finally {
    await sink.close();
  }

  if (received <= 0) {
    await part.delete();
    throw const HttpException('空的 APK');
  }
  if (await target.exists()) await target.delete();
  return part.rename(target.path);
}

class AppUpdateInstallResult {
  const AppUpdateInstallResult({
    required this.status,
    this.path,
    this.error,
  });

  final AppUpdateInstallStatus status;
  final String? path;
  final String? error;
}

enum AppUpdateInstallStatus {
  /// 系统安装界面已打开。
  launched,

  /// 需要用户先打开「允许安装未知应用」；APK 已下好。
  needPermission,

  /// 下载或安装失败。
  failed,

  /// 当前平台不支持（Web 等）。
  unsupported,
}

import 'package:flutter/services.dart';

import 'logger.dart';

const _log = Logger('ApkInstaller');

/// 把本地 APK 交给系统安装器。
///
/// 只有 Android。iOS / Web / 测试环境没有插件时按 [ApkInstallResult.unavailable]
/// 处理，调用方回落到复制下载地址。
enum ApkInstallResult {
  /// 已调起系统安装界面。
  launched,

  /// 还没给「安装未知应用」权限；原生侧已跳到设置页。
  needPermission,

  /// 文件有问题或调不起安装器。
  failed,

  /// 当前平台没有安装通道。
  unavailable,
}

class ApkInstaller {
  const ApkInstaller._();

  static const MethodChannel _channel = MethodChannel('alice/install');

  /// 是否已允许本应用安装 APK（Android 8+ 的「未知应用」开关）。
  static Future<bool> canInstall() async {
    try {
      return await _channel.invokeMethod<bool>('canInstall') ?? false;
    } on MissingPluginException {
      return false;
    } catch (e) {
      _log.debug('canInstall 失败：$e');
      return false;
    }
  }

  /// 打开本应用的「允许安装未知应用」设置页。
  static Future<void> openInstallSettings() async {
    try {
      await _channel.invokeMethod<void>('openInstallSettings');
    } on MissingPluginException {
      // 非 Android
    } catch (e) {
      _log.warn('打开安装权限设置失败：$e');
    }
  }

  /// 用 FileProvider 把 [path] 交给系统安装器。
  static Future<ApkInstallResult> install(String path) async {
    try {
      final raw = await _channel.invokeMethod<String>('installApk', {'path': path});
      switch (raw) {
        case 'launched':
          return ApkInstallResult.launched;
        case 'needPermission':
          return ApkInstallResult.needPermission;
        default:
          return ApkInstallResult.failed;
      }
    } on MissingPluginException {
      return ApkInstallResult.unavailable;
    } catch (e) {
      _log.warn('安装 APK 失败：$e');
      return ApkInstallResult.failed;
    }
  }
}

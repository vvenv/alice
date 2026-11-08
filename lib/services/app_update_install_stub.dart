import 'package:http/http.dart' as http;

import 'apk_installer.dart';
import 'app_update.dart';

/// Web：没有本地文件，也调不起安装器。
Future<AppUpdateInstallResult> downloadAndInstallUpdate(
  AppUpdateInfo info, {
  void Function(double? progress)? onProgress,
  http.Client? client,
  Future<ApkInstallResult> Function(String path)? install,
}) async {
  return const AppUpdateInstallResult(
    status: AppUpdateInstallStatus.unsupported,
  );
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
  launched,
  needPermission,
  failed,
  unsupported,
}

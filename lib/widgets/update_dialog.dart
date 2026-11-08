import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/apk_installer.dart';
import '../services/app_update.dart';
import '../services/app_update_install.dart';
import '../theme/theme_controller.dart';
import '../theme/tokens.dart';

/// 有新版本时的提示框。样式与 [showConfirmDialog] 一致。
///
/// [manual] 是用户在设置页主动点的「检查更新」：只给「更新 / 取消」，
/// 取消也不记「稍后」—— 用户自己来问的，不该影响之后的自动提示。
///
/// 点「下载更新」后在框内下载 APK，再调起系统安装器。返回 false 表示失败
/// 且已把下载地址复制到剪贴板，调用方据此给一句提示。
Future<bool> showAppUpdateDialog(
  BuildContext context,
  AppUpdateInfo info, {
  bool manual = false,
}) async {
  final ok = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    barrierColor: context.themeController.colors.overlay,
    builder: (_) => _UpdateDialog(info: info, manual: manual),
  );
  return ok ?? true;
}

class _UpdateDialog extends StatefulWidget {
  const _UpdateDialog({required this.info, required this.manual});

  final AppUpdateInfo info;
  final bool manual;

  @override
  State<_UpdateDialog> createState() => _UpdateDialogState();
}

class _UpdateDialogState extends State<_UpdateDialog> {
  bool _busy = false;
  double? _progress;
  String? _message;
  String? _apkPath;

  AppUpdateInfo get info => widget.info;

  Future<void> _dismissLater() async {
    if (_busy) return;
    if (!widget.manual) await snoozeUpdate();
    if (mounted) Navigator.of(context).pop(true);
  }

  Future<void> _dismissSkip() async {
    if (_busy) return;
    await skipUpdate(info);
    if (mounted) Navigator.of(context).pop(true);
  }

  Future<void> _startUpdate() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _progress = 0;
      _message = null;
    });

    // 已下过（例如刚去开了安装权限）就直接装，别再拉一次 40MB。
    if (_apkPath != null) {
      await _installExisting(_apkPath!);
      return;
    }

    final result = await downloadAndInstallUpdate(
      info,
      onProgress: (p) {
        if (!mounted) return;
        setState(() => _progress = p);
      },
    );
    if (!mounted) return;

    switch (result.status) {
      case AppUpdateInstallStatus.launched:
        Navigator.of(context).pop(true);
        return;
      case AppUpdateInstallStatus.needPermission:
        setState(() {
          _busy = false;
          _progress = null;
          _apkPath = result.path;
          _message = '请允许「安装未知应用」，然后点「继续安装」。';
        });
        return;
      case AppUpdateInstallStatus.failed:
      case AppUpdateInstallStatus.unsupported:
        await Clipboard.setData(ClipboardData(text: info.url));
        setState(() {
          _busy = false;
          _progress = null;
          _apkPath = result.path;
          _message = '更新失败，已复制下载地址。可重试或去浏览器安装。';
        });
        return;
    }
  }

  Future<void> _installExisting(String path) async {
    final outcome = await ApkInstaller.install(path);
    if (!mounted) return;
    switch (outcome) {
      case ApkInstallResult.launched:
        Navigator.of(context).pop(true);
        return;
      case ApkInstallResult.needPermission:
        setState(() {
          _busy = false;
          _progress = null;
          _message = '请允许「安装未知应用」，然后点「继续安装」。';
        });
        return;
      case ApkInstallResult.failed:
      case ApkInstallResult.unavailable:
        await Clipboard.setData(ClipboardData(text: info.url));
        setState(() {
          _busy = false;
          _progress = null;
          _message = '无法打开安装器，已复制下载地址。';
        });
        return;
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final notes = info.notes.isNotEmpty ? info.notes : '修复问题，改进体验。';
    final primaryLabel = _apkPath != null ? '继续安装' : '下载更新';

    return Dialog(
      backgroundColor: Colors.transparent,
      elevation: 0,
      insetPadding: const EdgeInsets.all(Spacing.xl),
      child: Container(
        width: double.infinity,
        constraints: const BoxConstraints(maxWidth: 320),
        padding: const EdgeInsets.all(Spacing.xl),
        decoration: BoxDecoration(
          color: colors.background,
          borderRadius: BorderRadius.circular(Radii.surface),
          border: Border.all(color: colors.border),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '发现新版本 ${info.version}',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: AppFonts.displayZh,
                fontSize: 17,
                color: colors.foreground,
              ),
            ),
            const SizedBox(height: Spacing.md),
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 200),
              child: SingleChildScrollView(
                child: Text(
                  notes,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      fontSize: 14, height: 20 / 14, color: colors.muted),
                ),
              ),
            ),
            if (_busy) ...[
              const SizedBox(height: Spacing.md),
              ClipRRect(
                borderRadius: BorderRadius.circular(Radii.control),
                child: LinearProgressIndicator(
                  value: _progress,
                  minHeight: 6,
                  backgroundColor: colors.border,
                  color: colors.primary,
                ),
              ),
              const SizedBox(height: Spacing.sm),
              Text(
                _progress == null
                    ? '正在下载…'
                    : '正在下载 ${(_progress! * 100).clamp(0, 100).toStringAsFixed(0)}%',
                style: TextStyle(fontSize: 13, color: colors.muted),
              ),
            ],
            if (_message != null) ...[
              const SizedBox(height: Spacing.md),
              Text(
                _message!,
                textAlign: TextAlign.center,
                style: TextStyle(
                    fontSize: 13, height: 18 / 13, color: colors.muted),
              ),
            ],
            const SizedBox(height: Spacing.md + Spacing.sm),
            Row(
              children: [
                Expanded(
                  child: _DialogButton(
                    label: widget.manual ? '取消' : '稍后',
                    textColor: colors.muted,
                    borderColor: colors.border,
                    onTap: _busy ? null : _dismissLater,
                  ),
                ),
                const SizedBox(width: Spacing.sm),
                Expanded(
                  child: _DialogButton(
                    label: primaryLabel,
                    textColor: colors.background,
                    backgroundColor: colors.primary,
                    onTap: _busy ? null : _startUpdate,
                  ),
                ),
              ],
            ),
            if (!widget.manual) ...[
              const SizedBox(height: Spacing.sm),
              _DialogButton(
                label: '跳过此版本',
                textColor: colors.subtle,
                fontSize: 13,
                onTap: _busy ? null : _dismissSkip,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _DialogButton extends StatelessWidget {
  const _DialogButton({
    required this.label,
    required this.textColor,
    required this.onTap,
    this.backgroundColor,
    this.borderColor,
    this.fontSize = 15,
  });

  final String label;
  final Color textColor;
  final Color? backgroundColor;
  final Color? borderColor;
  final double fontSize;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    return Semantics(
      button: true,
      enabled: enabled,
      label: label,
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Opacity(
          opacity: enabled ? 1 : 0.5,
          child: Container(
            constraints: const BoxConstraints(minHeight: 42),
            alignment: Alignment.center,
            padding: const EdgeInsets.symmetric(
              horizontal: Spacing.sm,
              vertical: Spacing.sm,
            ),
            decoration: BoxDecoration(
              color: backgroundColor,
              borderRadius: BorderRadius.circular(Radii.control),
              border: borderColor != null
                  ? Border.all(color: borderColor!, width: 1.5)
                  : null,
            ),
            child: Text(
              label,
              style: TextStyle(
                fontSize: fontSize,
                fontWeight: FontWeight.w600,
                color: textColor,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/app_update.dart';
import '../theme/theme_controller.dart';
import '../theme/tokens.dart';

enum _UpdateChoice { update, later, skip }

/// 有新版本时的提示框。样式与 [showConfirmDialog] 一致。
///
/// [manual] 是用户在设置页主动点的「检查更新」：只给「更新 / 取消」，
/// 取消也不记「稍后」—— 用户自己来问的，不该影响之后的自动提示。
///
/// 返回 false 表示用户想更新但打不开浏览器（下载地址已复制到剪贴板），
/// 调用方据此给一句提示。
Future<bool> showAppUpdateDialog(
  BuildContext context,
  AppUpdateInfo info, {
  bool manual = false,
}) async {
  final choice = await showDialog<_UpdateChoice>(
    context: context,
    barrierColor: context.themeController.colors.overlay,
    builder: (_) => _UpdateDialog(info: info, manual: manual),
  );

  switch (choice) {
    case _UpdateChoice.update:
      return _openDownload(info.url);
    case _UpdateChoice.skip:
      await skipUpdate(info);
    case _UpdateChoice.later:
    case null:
      if (!manual) await snoozeUpdate();
  }
  return true;
}

/// 交给系统浏览器下载，下载完由系统安装器接手覆盖安装。
Future<bool> _openDownload(String url) async {
  final uri = Uri.parse(url);
  try {
    if (await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      return true;
    }
  } catch (_) {
    // 落到下面的复制兜底
  }
  await Clipboard.setData(ClipboardData(text: url));
  return false;
}

class _UpdateDialog extends StatelessWidget {
  const _UpdateDialog({required this.info, required this.manual});

  final AppUpdateInfo info;
  final bool manual;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final notes = info.notes.isNotEmpty ? info.notes : '修复问题，改进体验。';

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
            // 更新说明可能有好几行，别让它把按钮挤出屏幕。
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
            const SizedBox(height: Spacing.md + Spacing.sm),
            Row(
              children: [
                Expanded(
                  child: _DialogButton(
                    label: manual ? '取消' : '稍后',
                    textColor: colors.muted,
                    borderColor: colors.border,
                    onTap: () => Navigator.of(context).pop(_UpdateChoice.later),
                  ),
                ),
                const SizedBox(width: Spacing.sm),
                Expanded(
                  child: _DialogButton(
                    label: '下载更新',
                    textColor: colors.background,
                    backgroundColor: colors.primary,
                    onTap: () =>
                        Navigator.of(context).pop(_UpdateChoice.update),
                  ),
                ),
              ],
            ),
            if (!manual) ...[
              const SizedBox(height: Spacing.sm),
              _DialogButton(
                label: '跳过此版本',
                textColor: colors.subtle,
                fontSize: 13,
                onTap: () => Navigator.of(context).pop(_UpdateChoice.skip),
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
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: label,
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
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
    );
  }
}

import 'package:flutter/material.dart';

import '../theme/theme_controller.dart';
import '../theme/tokens.dart';

/// 确认对话框。对应 RN 版 src/components/ConfirmDialog.tsx。
///
/// RN 侧是受控的 `visible` 组件；Flutter 侧改成命令式的 showDialog，
/// 调用点从「维护一个 dialog state 对象」变成 `await showConfirmDialog(...)`，
/// 少一层状态，行为一致。
Future<bool> showConfirmDialog(
  BuildContext context, {
  required String title,
  required String message,
  String confirmLabel = '确定',
  String cancelLabel = '取消',
  bool destructive = false,
}) async {
  final result = await showDialog<bool>(
    context: context,
    barrierColor: context.themeController.colors.overlay,
    builder: (dialogContext) => _ConfirmDialog(
      title: title,
      message: message,
      confirmLabel: confirmLabel,
      cancelLabel: cancelLabel,
      destructive: destructive,
    ),
  );
  return result ?? false;
}

/// 单行输入对话框。取消或点外面返回 null；确定返回去掉首尾空白的文本。
///
/// 空文本按不了确定，对话框留着，避免存下一个没名字的词表。
Future<String?> showTextPromptDialog(
  BuildContext context, {
  required String title,
  required String message,
  String initialValue = '',
  String hintText = '',
  String confirmLabel = '保存',
  String cancelLabel = '取消',
}) {
  return showDialog<String>(
    context: context,
    barrierColor: context.themeController.colors.overlay,
    builder: (dialogContext) => _TextPromptDialog(
      title: title,
      message: message,
      initialValue: initialValue,
      hintText: hintText,
      confirmLabel: confirmLabel,
      cancelLabel: cancelLabel,
    ),
  );
}

class _ConfirmDialog extends StatelessWidget {
  const _ConfirmDialog({
    required this.title,
    required this.message,
    required this.confirmLabel,
    required this.cancelLabel,
    required this.destructive,
  });

  final String title;
  final String message;
  final String confirmLabel;
  final String cancelLabel;
  final bool destructive;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

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
              title,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: AppFonts.displayZh,
                fontSize: 17,
                color: colors.foreground,
              ),
            ),
            const SizedBox(height: Spacing.md),
            Text(
              message,
              textAlign: TextAlign.center,
              style:
                  TextStyle(fontSize: 14, height: 20 / 14, color: colors.muted),
            ),
            const SizedBox(height: Spacing.md + Spacing.sm),
            Row(
              children: [
                Expanded(
                  child: _DialogButton(
                    label: cancelLabel,
                    textColor: colors.muted,
                    borderColor: colors.border,
                    onTap: () => Navigator.of(context).pop(false),
                  ),
                ),
                const SizedBox(width: Spacing.sm),
                Expanded(
                  child: _DialogButton(
                    label: confirmLabel,
                    textColor: destructive ? Colors.white : colors.background,
                    backgroundColor:
                        destructive ? colors.danger : colors.primary,
                    onTap: () => Navigator.of(context).pop(true),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _TextPromptDialog extends StatefulWidget {
  const _TextPromptDialog({
    required this.title,
    required this.message,
    required this.initialValue,
    required this.hintText,
    required this.confirmLabel,
    required this.cancelLabel,
  });

  final String title;
  final String message;
  final String initialValue;
  final String hintText;
  final String confirmLabel;
  final String cancelLabel;

  @override
  State<_TextPromptDialog> createState() => _TextPromptDialogState();
}

class _TextPromptDialogState extends State<_TextPromptDialog> {
  late final TextEditingController _controller =
      TextEditingController(text: widget.initialValue);
  bool _empty = false;

  @override
  void initState() {
    super.initState();
    _controller.selection = TextSelection(
      baseOffset: 0,
      extentOffset: _controller.text.length,
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final name = _controller.text.trim();
    if (name.isEmpty) {
      setState(() => _empty = true);
      return;
    }
    Navigator.of(context).pop(name);
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

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
              widget.title,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: AppFonts.displayZh,
                fontSize: 17,
                color: colors.foreground,
              ),
            ),
            const SizedBox(height: Spacing.md),
            Text(
              widget.message,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 14,
                height: 20 / 14,
                color: colors.muted,
              ),
            ),
            const SizedBox(height: Spacing.md),
            TextField(
              controller: _controller,
              autofocus: true,
              maxLength: 24,
              textInputAction: TextInputAction.done,
              onChanged: (_) {
                if (_empty) setState(() => _empty = false);
              },
              onSubmitted: (_) => _submit(),
              style: TextStyle(fontSize: 15, color: colors.foreground),
              decoration: InputDecoration(
                hintText: widget.hintText,
                counterText: '',
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: Spacing.md,
                  vertical: Spacing.sm,
                ),
                hintStyle: TextStyle(fontSize: 15, color: colors.subtle),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(Radii.control),
                  borderSide: BorderSide(
                    color: _empty ? colors.danger : colors.border,
                  ),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(Radii.control),
                  borderSide: BorderSide(
                    color: _empty ? colors.danger : colors.primary,
                    width: 1.5,
                  ),
                ),
              ),
            ),
            const SizedBox(height: Spacing.md + Spacing.sm),
            Row(
              children: [
                Expanded(
                  child: _DialogButton(
                    label: widget.cancelLabel,
                    textColor: colors.muted,
                    borderColor: colors.border,
                    onTap: () => Navigator.of(context).pop(),
                  ),
                ),
                const SizedBox(width: Spacing.sm),
                Expanded(
                  child: _DialogButton(
                    label: widget.confirmLabel,
                    textColor: colors.background,
                    backgroundColor: colors.primary,
                    onTap: _submit,
                  ),
                ),
              ],
            ),
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
  });

  final String label;
  final Color textColor;
  final Color? backgroundColor;
  final Color? borderColor;
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
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: textColor,
            ),
          ),
        ),
      ),
    );
  }
}

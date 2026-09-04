import 'package:flutter/material.dart';

import '../services/haptics.dart';
import '../theme/app_colors.dart';
import '../theme/theme_controller.dart';
import '../theme/tokens.dart';

/// 共享按钮基件。所有可点击的「按钮样」表面都应该走 AppButton / AppIconButton，
/// 这样按压反馈（弹性缩放 + 触感）、禁用态和无障碍标签都是免费且一致的。
///
/// 对应 RN 版 src/components/Button.tsx。
enum ButtonVariant { primary, outline, danger, ghost }

enum ButtonSize { lg, md, sm }

class _SizeSpec {
  const _SizeSpec({
    required this.minHeight,
    required this.borderRadius,
    required this.paddingHorizontal,
    required this.fontSize,
    required this.iconSize,
    required this.gap,
  });

  final double minHeight;
  final double borderRadius;
  final double paddingHorizontal;
  final double fontSize;
  final double iconSize;
  final double gap;
}

const Map<ButtonSize, _SizeSpec> _sizeSpecs = {
  ButtonSize.lg: _SizeSpec(
    minHeight: 52,
    borderRadius: Radii.button,
    paddingHorizontal: Spacing.xl,
    fontSize: 17,
    iconSize: 20,
    gap: Spacing.sm,
  ),
  ButtonSize.md: _SizeSpec(
    minHeight: 48,
    borderRadius: Radii.control,
    paddingHorizontal: Spacing.lg,
    fontSize: 14,
    iconSize: 16,
    gap: Spacing.xs,
  ),
  ButtonSize.sm: _SizeSpec(
    minHeight: 30,
    borderRadius: Radii.full,
    paddingHorizontal: Spacing.md,
    fontSize: 12,
    iconSize: 14,
    gap: Spacing.xs,
  ),
};

class _Palette {
  const _Palette({required this.bg, required this.border, required this.text});

  final Color bg;
  final Color? border;
  final Color text;
}

class AppButton extends StatefulWidget {
  const AppButton({
    super.key,
    required this.label,
    this.onPressed,
    this.variant = ButtonVariant.outline,
    this.size = ButtonSize.md,
    this.icon,
    this.leading,
    this.active = false,
    this.disabled = false,
    this.dimmed = false,
    this.haptic = true,
    this.semanticLabel,
    this.trailing,
    this.width,
  });

  final String label;
  final VoidCallback? onPressed;
  final ButtonVariant variant;
  final ButtonSize size;
  final IconData? icon;

  /// 放在文字前的自定义节点（设置后覆盖 icon）。
  final Widget? leading;

  /// 选中/开启的外观（仅 outline 变体）。
  final bool active;

  /// 阻止点击并变暗。
  final bool disabled;

  /// 看起来像禁用但仍可点击，让 onPressed 有机会解释原因。
  final bool dimmed;

  final bool haptic;
  final String? semanticLabel;

  /// 文字后面的附加内容（比如计数徽标）。
  final Widget? trailing;

  final double? width;

  @override
  State<AppButton> createState() => _AppButtonState();
}

class _AppButtonState extends State<AppButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 120),
    reverseDuration: const Duration(milliseconds: 260),
  );

  late final Animation<double> _scale = Tween<double>(begin: 1, end: 0.96)
      .animate(CurvedAnimation(
    parent: _controller,
    curve: Curves.easeOut,
    reverseCurve: Curves.elasticOut,
  ));

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  _Palette _paletteFor(AppColors colors) {
    switch (widget.variant) {
      case ButtonVariant.primary:
        return _Palette(
          bg: colors.primary,
          border: null,
          text: colors.background,
        );
      case ButtonVariant.outline:
        return widget.active
            ? _Palette(
                bg: colors.primarySoft,
                border: colors.primary,
                text: colors.primary,
              )
            : _Palette(
                bg: colors.background,
                border: colors.border,
                text: colors.secondary,
              );
      case ButtonVariant.danger:
        return _Palette(
          bg: colors.background,
          border: colors.dangerMuted,
          text: colors.danger,
        );
      case ButtonVariant.ghost:
        return _Palette(
          bg: colors.surface,
          border: null,
          text: colors.secondary,
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final spec = _sizeSpecs[widget.size]!;
    final palette = _paletteFor(colors);

    final hasBorder = widget.variant == ButtonVariant.outline ||
        widget.variant == ButtonVariant.danger;
    final inactiveLook = widget.disabled || widget.dimmed;
    final showShadow = widget.variant == ButtonVariant.primary &&
        widget.size == ButtonSize.lg &&
        !inactiveLook;

    final labelStyle = TextStyle(
      fontSize: spec.fontSize,
      color: palette.text,
      // lg 用中文标题字体；其余用系统字体 + 600 字重。
      fontFamily: widget.size == ButtonSize.lg ? AppFonts.displayZh : null,
      fontWeight: widget.size == ButtonSize.lg ? null : FontWeight.w600,
      letterSpacing: widget.size == ButtonSize.lg ? 0.5 : null,
    );

    Widget content = Container(
      width: widget.width,
      constraints: BoxConstraints(minHeight: spec.minHeight),
      padding: EdgeInsets.symmetric(
        horizontal: spec.paddingHorizontal,
        vertical: widget.size == ButtonSize.sm ? Spacing.xs : Spacing.sm,
      ),
      decoration: BoxDecoration(
        color: palette.bg,
        borderRadius: BorderRadius.circular(spec.borderRadius),
        border: hasBorder && palette.border != null
            ? Border.all(
                color: palette.border!,
                width: widget.size == ButtonSize.sm ? 1 : 1.5,
              )
            : null,
        boxShadow: showShadow
            ? [
                BoxShadow(
                  color: colors.primary.withValues(alpha: 0.35),
                  blurRadius: 8,
                  offset: const Offset(0, 4),
                ),
              ]
            : null,
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (widget.leading != null)
            widget.leading!
          else if (widget.icon != null)
            Icon(widget.icon, size: spec.iconSize, color: palette.text),
          if (widget.leading != null || widget.icon != null)
            SizedBox(width: spec.gap),
          Flexible(
            child: Text(
              widget.label,
              textAlign: TextAlign.center,
              style: labelStyle,
            ),
          ),
          if (widget.trailing != null) ...[
            SizedBox(width: spec.gap),
            widget.trailing!,
          ],
        ],
      ),
    );

    if (inactiveLook) {
      content = Opacity(opacity: 0.45, child: content);
    }

    return Semantics(
      button: true,
      enabled: !widget.disabled,
      label: widget.semanticLabel ?? widget.label,
      child: GestureDetector(
        onTapDown: widget.disabled
            ? null
            : (_) {
                if (widget.haptic) Haptics.tapLight();
                _controller.forward();
              },
        onTapUp: widget.disabled ? null : (_) => _controller.reverse(),
        onTapCancel: widget.disabled ? null : () => _controller.reverse(),
        onTap: widget.disabled ? null : widget.onPressed,
        behavior: HitTestBehavior.opaque,
        child: ScaleTransition(scale: _scale, child: content),
      ),
    );
  }
}

enum IconButtonVariant { surface, primary, danger, gold }

/// 圆形纯图标按钮（顶栏、卡片角标、播放器控件）。
class AppIconButton extends StatefulWidget {
  const AppIconButton({
    super.key,
    required this.icon,
    required this.semanticLabel,
    this.onPressed,
    this.size = 36,
    this.variant = IconButtonVariant.surface,
    this.disabled = false,
    this.haptic = true,
  });

  final IconData icon;
  final String semanticLabel;
  final VoidCallback? onPressed;
  final double size;
  final IconButtonVariant variant;
  final bool disabled;
  final bool haptic;

  @override
  State<AppIconButton> createState() => _AppIconButtonState();
}

class _AppIconButtonState extends State<AppIconButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 120),
    reverseDuration: const Duration(milliseconds: 260),
  );

  late final Animation<double> _scale = Tween<double>(begin: 1, end: 0.96)
      .animate(CurvedAnimation(
    parent: _controller,
    curve: Curves.easeOut,
    reverseCurve: Curves.elasticOut,
  ));

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  _Palette _paletteFor(AppColors colors) {
    switch (widget.variant) {
      case IconButtonVariant.surface:
        return _Palette(
          bg: colors.surface,
          border: colors.border,
          text: colors.foreground,
        );
      case IconButtonVariant.primary:
        return _Palette(
          bg: colors.primary,
          border: null,
          text: colors.background,
        );
      case IconButtonVariant.danger:
        return _Palette(
          bg: colors.background,
          border: colors.dangerMuted,
          text: colors.danger,
        );
      case IconButtonVariant.gold:
        return _Palette(bg: colors.gold, border: null, text: kGoldInk);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final palette = _paletteFor(colors);
    final isFilled = widget.variant == IconButtonVariant.primary ||
        widget.variant == IconButtonVariant.gold;

    Widget content = Container(
      width: widget.size,
      height: widget.size,
      decoration: BoxDecoration(
        color: palette.bg,
        shape: BoxShape.circle,
        border: !isFilled && palette.border != null
            ? Border.all(color: palette.border!)
            : null,
        boxShadow: isFilled
            ? [
                BoxShadow(
                  color: (widget.variant == IconButtonVariant.gold
                          ? colors.gold
                          : colors.primary)
                      .withValues(alpha: 0.35),
                  blurRadius: 8,
                  offset: const Offset(0, 4),
                ),
              ]
            : null,
      ),
      alignment: Alignment.center,
      child: Icon(widget.icon, size: widget.size / 2, color: palette.text),
    );

    if (widget.disabled) {
      content = Opacity(opacity: 0.45, child: content);
    }

    return Semantics(
      button: true,
      enabled: !widget.disabled,
      label: widget.semanticLabel,
      child: GestureDetector(
        onTapDown: widget.disabled
            ? null
            : (_) {
                if (widget.haptic) Haptics.tapLight();
                _controller.forward();
              },
        onTapUp: widget.disabled ? null : (_) => _controller.reverse(),
        onTapCancel: widget.disabled ? null : () => _controller.reverse(),
        onTap: widget.disabled ? null : widget.onPressed,
        behavior: HitTestBehavior.opaque,
        child: ScaleTransition(scale: _scale, child: content),
      ),
    );
  }
}

import 'package:flutter/material.dart';

import '../services/haptics.dart';
import '../theme/theme_controller.dart';

/// 自绘开关。浅色开启用主色铺轨；暗色 primary 是浅石板，改用金色轨才分得清。
class AppSwitch extends StatelessWidget {
  const AppSwitch({
    super.key,
    required this.value,
    required this.onChanged,
  });

  final bool value;
  final ValueChanged<bool>? onChanged;

  static const double _width = 52;
  static const double _height = 32;
  static const double _thumb = 24;
  static const double _pad = 4;
  static const Duration _duration = Duration(milliseconds: 180);

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final dark = context.themeController.isDark;
    final enabled = onChanged != null;
    // 浅色：主色铺轨、纸色滑块。暗色 primary 太浅，开启改用金色轨，滑块保持纸色。
    final track = value
        ? (dark ? colors.gold : colors.primary)
        : Color.alphaBlend(
            colors.foreground.withValues(alpha: dark ? 0.40 : 0.14),
            colors.surface,
          );
    const thumb = Color(0xFFFFFEF9);
    final outline = dark
        ? colors.foreground.withValues(alpha: 0.45)
        : colors.border;

    return Semantics(
      toggled: value,
      enabled: enabled,
      button: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: enabled
            ? () {
                Haptics.tapLight();
                onChanged!(!value);
              }
            : null,
        child: Opacity(
          opacity: enabled ? 1 : 0.5,
          child: AnimatedContainer(
            duration: _duration,
            curve: Curves.easeOut,
            width: _width,
            height: _height,
            decoration: BoxDecoration(
              color: track,
              borderRadius: BorderRadius.circular(_height / 2),
              border: value
                  ? null
                  : Border.all(color: outline, width: 1.5),
            ),
            child: AnimatedAlign(
              duration: _duration,
              curve: Curves.easeOut,
              alignment: value ? Alignment.centerRight : Alignment.centerLeft,
              child: Container(
                width: _thumb,
                height: _thumb,
                margin: const EdgeInsets.symmetric(horizontal: _pad),
                decoration: BoxDecoration(
                  color: thumb,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: colors.primary.withValues(alpha: value ? 0.35 : 0.16),
                      blurRadius: 4,
                      offset: const Offset(0, 1),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';

import '../theme/theme_controller.dart';

/// 自绘滑块。对应 Expo 版 src/components/Slider.tsx。
///
/// RN 侧要用 pageX 绕开 Android 上 locationX 参照系乱跳的 bug；Flutter 的
/// 手势坐标本来就是相对于当前 RenderBox 的，直接用 localPosition 即可。
const double _thumbSize = 24;
const double _trackHeight = 8;

class AppSlider extends StatelessWidget {
  const AppSlider({
    super.key,
    required this.min,
    required this.max,
    required this.step,
    required this.value,
    required this.onChanged,
    this.disabled = false,
    this.label,
    this.formatValue,
  });

  final double min;
  final double max;
  final double step;
  final double value;
  final ValueChanged<double> onChanged;
  final bool disabled;

  /// 读屏软件播报的名称 —— 这个滑块在调什么。
  final String? label;

  /// 播报用的数值格式化（如 `7.0s`、`0.9x`）。默认一位小数。
  final String Function(double value)? formatValue;

  String _format(double v) =>
      formatValue?.call(v) ?? v.toStringAsFixed(1);

  /// 把 [value] 按 [step] 挪一格并夹回区间 —— 读屏的上下滑手势走这里。
  double _stepped(double delta) {
    final raw = ((value + delta) / step).round() * step;
    return raw.clamp(min, max).toDouble();
  }

  double _snap(double pct) {
    final clamped = pct.clamp(0.0, 1.0);
    var raw = min + clamped * (max - min);
    raw = (raw / step).round() * step;
    return raw.clamp(min, max).toDouble();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final dark = context.themeController.isDark;
    final fraction = ((value - min) / (max - min)).clamp(0.0, 1.0);
    // 暗色 primary 是浅石板，当填充会和槽糊在一起；改用金色铺已完成段。
    final rest = Color.alphaBlend(
      colors.foreground.withValues(alpha: dark ? 0.52 : 0.22),
      colors.surface,
    );
    final fill = dark ? colors.gold : colors.primary;
    final thumbFill = dark ? colors.foreground : colors.primary;
    final thumbRing = dark ? colors.gold : colors.surfaceRaised;
    final trackHeight = dark ? 10.0 : _trackHeight;

    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        // 容器左右各留半个滑块的内边距，轨道宽度即 width - _thumbSize。
        final trackWidth = (width - _thumbSize).clamp(1.0, double.infinity);
        final thumbLeft = _thumbSize / 2 + fraction * trackWidth;

        void handleAt(Offset localPosition) {
          if (disabled) return;
          final x = localPosition.dx - _thumbSize / 2;
          onChanged(_snap(x / trackWidth));
        }

        // 轨道必须用 Positioned 拉满宽度。Stack 默认 loose，Container 会跟着
        // FractionallySizedBox 缩成「已填充」那一段，未完成的 track 就消失了。
        Widget content = SizedBox(
          height: 40,
          width: width,
          child: Stack(
            alignment: Alignment.centerLeft,
            children: [
              Positioned(
                left: _thumbSize / 2,
                right: _thumbSize / 2,
                top: 0,
                bottom: 0,
                child: Center(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(trackHeight / 2),
                    child: SizedBox(
                      height: trackHeight,
                      width: double.infinity,
                      child: ColoredBox(
                        color: rest,
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: FractionallySizedBox(
                            widthFactor: fraction,
                            heightFactor: 1,
                            child: ColoredBox(color: fill),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              Positioned(
                left: thumbLeft - _thumbSize / 2,
                top: (40 - _thumbSize) / 2,
                child: Container(
                  width: _thumbSize,
                  height: _thumbSize,
                  decoration: BoxDecoration(
                    color: thumbFill,
                    shape: BoxShape.circle,
                    border: Border.all(color: thumbRing, width: 2),
                    boxShadow: [
                      BoxShadow(
                        color: colors.primary.withValues(alpha: 0.35),
                        blurRadius: 4,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );

        if (disabled) {
          content = Opacity(opacity: 0.5, child: content);
        }

        // 读屏支持：报成可调节控件，并给出上下滑的加减动作
        // （TalkBack / VoiceOver 在滑块上的 swipe up/down）。
        return Semantics(
          slider: true,
          enabled: !disabled,
          label: label,
          value: _format(value),
          increasedValue: _format(_stepped(step)),
          decreasedValue: _format(_stepped(-step)),
          onIncrease: disabled ? null : () => onChanged(_stepped(step)),
          onDecrease: disabled ? null : () => onChanged(_stepped(-step)),
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTapDown: (d) => handleAt(d.localPosition),
            onHorizontalDragStart: (d) => handleAt(d.localPosition),
            onHorizontalDragUpdate: (d) => handleAt(d.localPosition),
            child: content,
          ),
        );
      },
    );
  }
}

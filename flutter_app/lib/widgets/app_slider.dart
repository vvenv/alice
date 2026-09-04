import 'package:flutter/material.dart';

import '../theme/theme_controller.dart';

/// 自绘滑块。对应 RN 版 src/components/Slider.tsx。
///
/// RN 侧要用 pageX 绕开 Android 上 locationX 参照系乱跳的 bug；Flutter 的
/// 手势坐标本来就是相对于当前 RenderBox 的，直接用 localPosition 即可。
const double _thumbSize = 24;
const double _trackHeight = 6;

class AppSlider extends StatelessWidget {
  const AppSlider({
    super.key,
    required this.min,
    required this.max,
    required this.step,
    required this.value,
    required this.onChanged,
    this.disabled = false,
  });

  final double min;
  final double max;
  final double step;
  final double value;
  final ValueChanged<double> onChanged;
  final bool disabled;

  double _snap(double pct) {
    final clamped = pct.clamp(0.0, 1.0);
    var raw = min + clamped * (max - min);
    raw = (raw / step).round() * step;
    return raw.clamp(min, max).toDouble();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final fraction = ((value - min) / (max - min)).clamp(0.0, 1.0);

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

        Widget content = SizedBox(
          height: 40,
          width: width,
          child: Stack(
            alignment: Alignment.centerLeft,
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: _thumbSize / 2,
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(_trackHeight / 2),
                  child: Container(
                    height: _trackHeight,
                    color: colors.border,
                    child: FractionallySizedBox(
                      alignment: Alignment.centerLeft,
                      widthFactor: fraction,
                      child: Container(color: colors.primary),
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
                    color: colors.primary,
                    shape: BoxShape.circle,
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

        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: (d) => handleAt(d.localPosition),
          onHorizontalDragStart: (d) => handleAt(d.localPosition),
          onHorizontalDragUpdate: (d) => handleAt(d.localPosition),
          child: content,
        );
      },
    );
  }
}

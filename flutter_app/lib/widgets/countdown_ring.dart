import 'dart:math' as math;

import 'package:flutter/material.dart';

/// 怀表倒计时环 —— Wonderland 怀表意象。金色圆环顺时针耗尽，
/// 由 0..1 的动画值驱动（1 = 满环）。
///
/// 对应 RN 版 src/components/CountdownRing.tsx。RN 侧用 react-native-svg
/// 的 strokeDasharray/strokeDashoffset 实现；Flutter 侧直接画弧，
/// 少一层 SVG 依赖，也没有 Animated 注入 collapsable 的那个 web 坑。
class CountdownRing extends StatelessWidget {
  const CountdownRing({
    super.key,
    required this.size,
    required this.strokeWidth,
    required this.progress,
    required this.color,
    required this.trackColor,
    this.ticks = 0,
    this.tickColor,
    this.child,
  });

  final double size;
  final double strokeWidth;

  /// 剩余比例，0..1（1 = 满环）。
  final Animation<double> progress;

  final Color color;
  final Color trackColor;

  /// 表盘刻度数量（0 表示不画）。
  final int ticks;
  final Color? tickColor;

  final Widget? child;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Positioned.fill(
            child: RepaintBoundary(
              child: AnimatedBuilder(
                animation: progress,
                builder: (context, _) => CustomPaint(
                  painter: _CountdownRingPainter(
                    progress: progress.value.clamp(0.0, 1.0),
                    strokeWidth: strokeWidth,
                    color: color,
                    trackColor: trackColor,
                    ticks: ticks,
                    tickColor: tickColor,
                  ),
                ),
              ),
            ),
          ),
          if (child != null) child!,
        ],
      ),
    );
  }
}

class _CountdownRingPainter extends CustomPainter {
  const _CountdownRingPainter({
    required this.progress,
    required this.strokeWidth,
    required this.color,
    required this.trackColor,
    required this.ticks,
    required this.tickColor,
  });

  final double progress;
  final double strokeWidth;
  final Color color;
  final Color trackColor;
  final int ticks;
  final Color? tickColor;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = (size.width - strokeWidth) / 2;

    // 轨道
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth
        ..color = trackColor,
    );

    // 表盘刻度：每 3 格一个粗刻度，与 RN 版一致。
    final tick = tickColor;
    if (ticks > 0 && tick != null) {
      final outer = radius - strokeWidth / 2 - 4;
      final inner = outer - 6;
      for (var i = 0; i < ticks; i++) {
        final angle = (i / ticks) * 2 * math.pi - math.pi / 2;
        canvas.drawLine(
          Offset(
            center.dx + inner * math.cos(angle),
            center.dy + inner * math.sin(angle),
          ),
          Offset(
            center.dx + outer * math.cos(angle),
            center.dy + outer * math.sin(angle),
          ),
          Paint()
            ..color = tick
            ..strokeWidth = i % 3 == 0 ? 2 : 1
            ..strokeCap = StrokeCap.round,
        );
      }
    }

    // 进度弧：从 12 点方向顺时针画 progress 比例的一段。
    if (progress > 0) {
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        -math.pi / 2,
        2 * math.pi * progress,
        false,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = strokeWidth
          ..strokeCap = StrokeCap.round
          ..color = color,
      );
    }
  }

  @override
  bool shouldRepaint(_CountdownRingPainter old) {
    return old.progress != progress ||
        old.color != color ||
        old.trackColor != trackColor ||
        old.strokeWidth != strokeWidth ||
        old.ticks != ticks ||
        old.tickColor != tickColor;
  }
}

import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../state/toast_controller.dart';
import '../theme/theme_controller.dart';
import '../theme/tokens.dart';

/// 底部浮出的 toast 药丸。对应 RN 版 src/components/Toast.tsx。
///
/// 放在 Stack 的最上层使用；toast 为 null 时不占位也不拦截点击。
class AppToast extends StatefulWidget {
  const AppToast({super.key, required this.toast, this.onActionPressed});

  final ToastState? toast;

  /// 操作按钮被点击后调用（用来关掉 toast）。
  final VoidCallback? onActionPressed;

  @override
  State<AppToast> createState() => _AppToastState();
}

class _AppToastState extends State<AppToast>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 320),
  );

  late final Animation<double> _anim = CurvedAnimation(
    parent: _controller,
    curve: Curves.easeOutBack,
  );

  @override
  void initState() {
    super.initState();
    if (widget.toast != null) _controller.forward();
  }

  @override
  void didUpdateWidget(AppToast oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 每条新 toast 都重新播一次进场动画（与 RN 版按 toast 对象重置一致）。
    if (widget.toast != null && widget.toast != oldWidget.toast) {
      _controller
        ..reset()
        ..forward();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final toast = widget.toast;
    if (toast == null) return const SizedBox.shrink();

    final colors = context.colors;
    final bottomInset = MediaQuery.of(context).padding.bottom;

    return Positioned(
      left: 0,
      right: 0,
      bottom: math.max(40.0, bottomInset + Spacing.lg),
      child: IgnorePointer(
        ignoring: toast.action == null,
        child: Align(
          alignment: Alignment.center,
          child: AnimatedBuilder(
            animation: _anim,
            builder: (context, child) => Opacity(
              opacity: _anim.value.clamp(0.0, 1.0),
              child: Transform.translate(
                offset: Offset(0, 16 * (1 - _anim.value)),
                child: child,
              ),
            ),
            child: Semantics(
              liveRegion: true,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: Spacing.lg,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: colors.foreground,
                  borderRadius: BorderRadius.circular(Radii.full),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.4),
                      blurRadius: 12,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Flexible(
                      child: Text(
                        toast.message,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                          color: colors.background,
                        ),
                      ),
                    ),
                    if (toast.action != null) ...[
                      const SizedBox(width: Spacing.md),
                      GestureDetector(
                        onTap: () {
                          toast.action!.onPressed();
                          widget.onActionPressed?.call();
                        },
                        behavior: HitTestBehavior.opaque,
                        child: Text(
                          toast.action!.label,
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: colors.gold,
                          ),
                        ),
                      ),
                    ],
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

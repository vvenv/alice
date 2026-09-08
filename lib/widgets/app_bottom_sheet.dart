import 'package:flutter/material.dart';

import '../theme/theme_controller.dart';
import '../theme/tokens.dart';

/// 共享的底部抽屉外壳：暗化背景、圆角面板 + 抓手、弹性入场。
/// 所有从底部弹出的模态（菜单、抽屉、操作表）都走这里，观感统一。
///
/// 对应 RN 版 src/components/BottomSheet.tsx。
///
/// [builder] 的结果挂在 [Flexible] 里，主体想吃掉剩余高度直接自己再套一层
/// [Flexible] 即可。RN 版是把算好的 bodyMaxHeight 传给 children 函数的，
/// 这里不照搬：那要在外面手算一遍 chrome 高度，而调用方还得把标题、搜索行
/// 之类再减一次 —— 漏算哪一项，列表就会把抽屉底撑破。
Future<T?> showAppBottomSheet<T>({
  required BuildContext context,
  String? title,
  Widget? headerRight,
  double maxHeightRatio = 0.8,
  required Widget Function(BuildContext context) builder,
}) {
  final colors = context.themeController.colors;

  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    barrierColor: colors.overlay,
    // 自绘 chrome，不要 Material 默认的 handle / 圆角。
    elevation: 0,
    builder: (sheetContext) => _AppBottomSheet(
      title: title,
      headerRight: headerRight,
      maxHeightRatio: maxHeightRatio,
      builder: builder,
    ),
  );
}

class _AppBottomSheet extends StatelessWidget {
  const _AppBottomSheet({
    required this.title,
    required this.headerRight,
    required this.maxHeightRatio,
    required this.builder,
  });

  final String? title;
  final Widget? headerRight;
  final double maxHeightRatio;
  final Widget Function(BuildContext context) builder;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final media = MediaQuery.of(context);

    final sheetMaxHeight = media.size.height * maxHeightRatio;
    final bottomPad =
        media.padding.bottom > Spacing.xl ? media.padding.bottom : Spacing.xl;

    // 不要再套一层 Align 把自己撑成满屏高。
    //
    // showModalBottomSheet 本来就把内容贴在底部，而外面那层 Align 会让
    // BottomSheet 的实际高度变成整块屏幕 —— 下拖收起的判定是按自身高度算的，
    // 于是怎么拖都够不到阈值：抽屉纹丝不动。去掉之后高度等于内容高度，
    // 下拖收起、拖到一半松手回弹都恢复正常。
    return Container(
      width: double.infinity,
      constraints: BoxConstraints(maxWidth: 640, maxHeight: sheetMaxHeight),
      padding: EdgeInsets.only(
        left: Spacing.lg,
        right: Spacing.lg,
        top: Spacing.lg,
        bottom: bottomPad,
      ),
      decoration: BoxDecoration(
        color: colors.background,
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(Radii.shell),
          topRight: Radius.circular(Radii.shell),
        ),
        border: Border(
          top: BorderSide(color: colors.borderSubtle),
          left: BorderSide(color: colors.borderSubtle),
          right: BorderSide(color: colors.borderSubtle),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: Container(
              width: 36,
              height: 4,
              margin: const EdgeInsets.only(bottom: Spacing.md),
              decoration: BoxDecoration(
                color: colors.border,
                borderRadius: BorderRadius.circular(Radii.full),
              ),
            ),
          ),
          if (title != null) ...[
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  title!,
                  style: TextStyle(
                    fontFamily: AppFonts.displayZh,
                    fontSize: 17,
                    color: colors.foreground,
                  ),
                ),
                if (headerRight != null) headerRight!,
              ],
            ),
            const SizedBox(height: Spacing.sm),
          ],
          Flexible(child: builder(context)),
        ],
      ),
    );
  }
}

/// 底部抽屉里的一行菜单项（首页「更多」/「拍照识词」菜单用）。
class SheetRow extends StatelessWidget {
  const SheetRow({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return Semantics(
      button: true,
      label: label,
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Container(
          constraints: const BoxConstraints(minHeight: 52),
          padding: const EdgeInsets.symmetric(horizontal: Spacing.lg),
          decoration: BoxDecoration(
            color: colors.surface,
            borderRadius: BorderRadius.circular(Radii.surface),
            border: Border.all(color: colors.borderSubtle),
          ),
          child: Row(
            children: [
              Icon(icon, size: 20, color: colors.foreground),
              const SizedBox(width: Spacing.md),
              Text(
                label,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: colors.foreground,
                ),
              ),
              const Spacer(),
              Icon(Icons.chevron_right, size: 16, color: colors.subtle),
            ],
          ),
        ),
      ),
    );
  }
}

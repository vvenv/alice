import 'package:flutter/material.dart';

import '../theme/theme_controller.dart';
import '../theme/tokens.dart';
import 'app_icons.dart';

/// 抽屉里的搜索行。词库、历史、收藏共用一份 —— 三处长得不一样反而更奇怪。
class DrawerSearchField extends StatelessWidget {
  const DrawerSearchField({
    super.key,
    required this.controller,
    required this.value,
    required this.onChanged,
    required this.hintText,
  });

  final TextEditingController controller;

  /// 当前查询串。只用来决定要不要显示清除按钮，不回写 [controller]。
  final String value;

  final ValueChanged<String> onChanged;
  final String hintText;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return Container(
      constraints: const BoxConstraints(minHeight: 36),
      padding: const EdgeInsets.symmetric(horizontal: Spacing.sm + 2),
      decoration: BoxDecoration(
        color: colors.surfaceSunken,
        borderRadius: BorderRadius.circular(Radii.control),
        border: Border.all(color: colors.border),
      ),
      child: Row(
        children: [
          Icon(AppIcons.search, size: 16, color: colors.subtle),
          const SizedBox(width: Spacing.xs),
          Expanded(
            child: TextField(
              controller: controller,
              onChanged: onChanged,
              textInputAction: TextInputAction.search,
              autocorrect: false,
              style: TextStyle(fontSize: 14, color: colors.foreground),
              decoration: InputDecoration(
                border: InputBorder.none,
                isDense: true,
                contentPadding:
                    const EdgeInsets.symmetric(vertical: Spacing.sm),
                hintText: hintText,
                hintStyle: TextStyle(fontSize: 14, color: colors.subtle),
              ),
            ),
          ),
          if (value.isNotEmpty)
            Semantics(
              button: true,
              label: '清除搜索',
              child: GestureDetector(
                onTap: () {
                  controller.clear();
                  onChanged('');
                },
                behavior: HitTestBehavior.opaque,
                child: Padding(
                  padding: const EdgeInsets.all(4),
                  child: Icon(
                    AppIcons.closeCircle,
                    size: 16,
                    color: colors.subtle,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

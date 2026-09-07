import 'package:flutter/material.dart';

import '../services/storage.dart';
import '../theme/app_colors.dart';
import '../theme/theme_controller.dart';
import '../theme/tokens.dart';
import 'app_button.dart';
import 'app_icons.dart';
import 'app_slider.dart';
import 'app_switch.dart';

/// 间隔滑块 + 自动播放/打乱开关 + 「开始听写」主按钮。
/// 首页和听写页共用（听写页不显示主按钮）。
///
/// 对应 RN 版 src/components/PlaybackControls.tsx。
class PlaybackControls extends StatelessWidget {
  const PlaybackControls({
    super.key,
    required this.intervalSec,
    required this.autoNext,
    required this.onIntervalChanged,
    required this.onAutoNextChanged,
    this.onPlayToggle,
    this.showPlayButton = true,
    this.shuffle,
    this.onShuffleChanged,
    this.wordCount,
    this.trailing,
  });

  final double intervalSec;
  final bool autoNext;
  final ValueChanged<double> onIntervalChanged;
  final ValueChanged<bool> onAutoNextChanged;
  final VoidCallback? onPlayToggle;
  final bool showPlayButton;
  final bool? shuffle;
  final ValueChanged<bool>? onShuffleChanged;

  /// 传了就在主按钮里显示词数徽标，为 0 时按钮变暗（但仍可点）。
  final int? wordCount;

  /// 开关行右端的附加控件。听写页没有「打乱顺序」，那半行本来是空的，
  /// 正好放语速入口。
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    // 0 词时仍可点击，好让 toast 解释为什么没开始。
    final playLooksDisabled = wordCount == 0;
    final showPlay = showPlayButton && onPlayToggle != null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            Text(
              '间隔',
              style: TextStyle(fontSize: 13, color: colors.muted),
            ),
            const SizedBox(width: Spacing.md),
            Expanded(
              child: AppSlider(
                min: kMinIntervalSec,
                max: kMaxIntervalSec,
                step: kIntervalStep,
                value: intervalSec,
                onChanged: onIntervalChanged,
                label: '听写间隔秒数',
                formatValue: (v) => '${v.toStringAsFixed(1)} 秒',
              ),
            ),
            const SizedBox(width: Spacing.sm),
            SizedBox(
              width: 36,
              child: Text(
                '${intervalSec.toStringAsFixed(1)}s',
                textAlign: TextAlign.right,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: colors.primary,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: Spacing.sm),
        Padding(
          padding: EdgeInsets.only(bottom: showPlay ? Spacing.xs : 0),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _ToggleItem(
                label: '自动播放',
                value: autoNext,
                onChanged: onAutoNextChanged,
                semanticLabel: '自动播放下一词',
                colors: colors,
              ),
              if (onShuffleChanged != null)
                _ToggleItem(
                  label: '打乱顺序',
                  value: shuffle ?? false,
                  onChanged: onShuffleChanged!,
                  semanticLabel: '打乱播放顺序',
                  colors: colors,
                )
              else if (trailing != null)
                trailing!,
            ],
          ),
        ),
        if (showPlay) ...[
          const SizedBox(height: Spacing.sm),
          AppButton(
            label: '开始听写',
            variant: ButtonVariant.primary,
            size: ButtonSize.lg,
            onPressed: onPlayToggle,
            dimmed: playLooksDisabled,
            leading: Container(
              width: 26,
              height: 26,
              padding: const EdgeInsets.only(left: 2),
              decoration: BoxDecoration(
                color: colors.gold,
                shape: BoxShape.circle,
              ),
              alignment: Alignment.center,
              child: const Icon(AppIcons.play, size: 14, color: kGoldInk),
            ),
            trailing: (wordCount != null && wordCount! > 0)
                ? Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: Spacing.sm,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: colors.background.withValues(alpha: 0.18),
                      borderRadius: BorderRadius.circular(Radii.full),
                    ),
                    child: Text(
                      '$wordCount 词',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: colors.background,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                  )
                : null,
          ),
        ],
      ],
    );
  }
}

class _ToggleItem extends StatelessWidget {
  const _ToggleItem({
    required this.label,
    required this.value,
    required this.onChanged,
    required this.semanticLabel,
    required this.colors,
  });

  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;
  final String semanticLabel;
  final AppColors colors;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(label, style: TextStyle(fontSize: 13, color: colors.muted)),
        const SizedBox(width: Spacing.lg),
        Semantics(
          label: semanticLabel,
          toggled: value,
          child: AppSwitch(
            value: value,
            onChanged: onChanged,
          ),
        ),
      ],
    );
  }
}

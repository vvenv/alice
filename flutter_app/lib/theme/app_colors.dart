import 'package:flutter/material.dart';

/// 主题色板。字段与取值逐一对应 RN 版 src/lib/theme.tsx 的 ThemeColors。
///
/// RN 侧写法是 `#RRGGBBAA`（尾部为 alpha），Dart 的 Color 是 `0xAARRGGBB`，
/// 下面的常量已完成换算 —— 例如 `#1A2B4ACC` → `0xCC1A2B4A`。
@immutable
class AppColors {
  const AppColors({
    required this.primary,
    required this.primarySoft,
    required this.gold,
    required this.goldSoft,
    required this.rose,
    required this.roseSoft,
    required this.danger,
    required this.dangerSoft,
    required this.dangerMuted,
    required this.foreground,
    required this.background,
    required this.muted,
    required this.subtle,
    required this.secondary,
    required this.border,
    required this.borderSubtle,
    required this.borderMuted,
    required this.surface,
    required this.surfaceRaised,
    required this.surfaceSunken,
    required this.track,
    required this.overlay,
  });

  final Color primary;
  final Color primarySoft;

  /// Wonderland 金 —— 仪表类元素（倒计时、进度）。
  final Color gold;
  final Color goldSoft;

  /// Wonderland 玫瑰 —— 斜体点缀与危险态。
  final Color rose;
  final Color roseSoft;

  final Color danger;
  final Color dangerSoft;
  final Color dangerMuted;

  final Color foreground;
  final Color background;

  final Color muted;
  final Color subtle;
  final Color secondary;

  final Color border;
  final Color borderSubtle;
  final Color borderMuted;

  final Color surface;
  final Color surfaceRaised;
  final Color surfaceSunken;
  final Color track;

  final Color overlay;

  /// 浅色「纸」主题：墨色字、纸色底、金色高光、玫瑰危险色。
  static const AppColors light = AppColors(
    primary: Color(0xFF1A2B4A), // ink
    primarySoft: Color(0xFFF4ECD6), // 暖金底 — 选中/激活高亮
    gold: Color(0xFFB8860B),
    goldSoft: Color(0xFFF4ECD6),
    rose: Color(0xFFC44569),
    roseSoft: Color(0xFFF6E4EA),
    danger: Color(0xFFC44569),
    dangerSoft: Color(0xFFF6E4EA),
    dangerMuted: Color(0xFFB8385E),
    foreground: Color(0xFF1A2B4A), // ink
    background: Color(0xFFFAF6EE), // paper
    muted: Color(0xCC1A2B4A),
    subtle: Color(0xB31A2B4A),
    secondary: Color(0xBF1A2B4A),
    border: Color(0x1A1A2B4A),
    borderSubtle: Color(0x0F1A2B4A),
    borderMuted: Color(0x131A2B4A),
    surface: Color(0xFFF2EBDA), // parchment
    surfaceRaised: Color(0xFFFFFEF9),
    surfaceSunken: Color(0xFFEFE6CF),
    track: Color(0x1A1A2B4A),
    overlay: Color(0x800F1A2E),
  );

  /// 深色「午夜」主题：纸色字、午夜底，金色只留给仪表读数。
  static const AppColors dark = AppColors(
    primary: Color(0xFFC5D0E0), // 柔和石板色（提亮的墨）
    primarySoft: Color(0xFF243352),
    gold: Color(0xFFD4A437),
    goldSoft: Color(0xFF2A2410),
    rose: Color(0xFFE06488),
    roseSoft: Color(0xFF2E1620),
    danger: Color(0xFFE06488),
    dangerSoft: Color(0xFF2E1620),
    dangerMuted: Color(0xFFE06488),
    foreground: Color(0xFFFAF6EE), // paper
    background: Color(0xFF0F1A2E), // midnight
    muted: Color(0xBFFAF6EE),
    subtle: Color(0x99FAF6EE),
    secondary: Color(0xBFFAF6EE),
    border: Color(0x1AFAF6EE),
    borderSubtle: Color(0x0FFAF6EE),
    borderMuted: Color(0x13FAF6EE),
    surface: Color(0xFF162238), // nightpaper
    surfaceRaised: Color(0xFF1B2A42),
    surfaceSunken: Color(0xFF0C1626),
    track: Color(0x1AFAF6EE),
    overlay: Color(0x99000000),
  );
}

/// 金色底上的墨色 —— 两套主题的金色上都足够可读。
const Color kGoldInk = Color(0xFF1A2B4A);

/// 「听写中 / 已完成」状态点的绿色。
const Color kStatusPlaying = Color(0xFF27AE60);

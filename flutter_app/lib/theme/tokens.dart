/// 共享设计令牌（非颜色）。颜色由 AppColors / ThemeController 提供。
///
/// 对应 RN 版 src/lib/designTokens.ts
library;

class Radii {
  const Radii._();

  static const double xs = 4;
  static const double control = 8;
  static const double surface = 12;
  static const double button = 15;
  static const double card = 18;
  static const double shell = 24;
  static const double full = 9999;
}

class Spacing {
  const Spacing._();

  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 20;
  static const double xxl = 24;
}

/// 打包进 pubspec.yaml 的字体族。
///
/// 每个 family 只挂了一个固定字重/字形的 TTF —— 使用时不要再叠加
/// fontWeight / fontStyle，否则 Android 的字体解析会落回系统默认字体。
class AppFonts {
  const AppFonts._();

  /// 英文单词、数字与拉丁文展示文案（Bold）。
  static const String display = 'PlayfairDisplay';

  /// 拉丁文斜体展示（Bold Italic）。
  static const String displayItalic = 'PlayfairDisplayItalic';

  /// 中文标题（Bold）。
  static const String displayZh = 'NotoSerifSCBold';

  /// 中文衬线正文（Medium）。
  static const String serif = 'NotoSerifSC';

  /// 系统无衬线（默认）—— 传 null 以使用平台默认字体。
  static const String? sans = null;
}

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/prefs.dart';
import 'app_colors.dart';

enum ThemeModeSetting { light, dark }

const String _themeKey = 'alice_theme_mode';

/// 主题状态。对应 RN 版的 ThemeProvider / useThemeColors / useThemeMode。
///
/// 行为与 RN 版一致：
/// - 启动时优先读取用户显式选择；没有则跟随系统。
/// - 用户一旦显式选择，就固定下来，不再被系统偏好覆盖。
class ThemeController extends ChangeNotifier {
  ThemeController();

  ThemeModeSetting _mode = ThemeModeSetting.light;
  bool _hasExplicitChoice = false;
  bool _ready = false;

  ThemeModeSetting get mode => _mode;
  bool get ready => _ready;
  bool get isDark => _mode == ThemeModeSetting.dark;
  AppColors get colors => isDark ? AppColors.dark : AppColors.light;

  /// 载入持久化的选择；没有存过就用系统亮暗偏好。
  Future<void> load(Brightness systemBrightness) async {
    final stored = await Prefs.getString(_themeKey);
    if (stored == 'dark' || stored == 'light') {
      _mode = stored == 'dark' ? ThemeModeSetting.dark : ThemeModeSetting.light;
      _hasExplicitChoice = true;
    } else {
      _mode = systemBrightness == Brightness.dark
          ? ThemeModeSetting.dark
          : ThemeModeSetting.light;
    }
    _ready = true;
    notifyListeners();
  }

  /// 系统亮暗切换时调用 —— 仅在用户没有显式选择过时才跟随。
  void syncSystemBrightness(Brightness brightness) {
    if (_hasExplicitChoice) return;
    final next = brightness == Brightness.dark
        ? ThemeModeSetting.dark
        : ThemeModeSetting.light;
    if (next == _mode) return;
    _mode = next;
    notifyListeners();
  }

  void toggle() {
    setMode(
      _mode == ThemeModeSetting.dark
          ? ThemeModeSetting.light
          : ThemeModeSetting.dark,
    );
  }

  void setMode(ThemeModeSetting next) {
    if (next == _mode && _hasExplicitChoice) return;
    _mode = next;
    _hasExplicitChoice = true;
    Prefs.setString(_themeKey, next == ThemeModeSetting.dark ? 'dark' : 'light');
    notifyListeners();
  }
}

/// `context.colors` —— 等价于 RN 版的 `useThemeColors()`。
extension ThemeColorsX on BuildContext {
  AppColors get colors => watch<ThemeController>().colors;
  ThemeController get themeController => read<ThemeController>();
}

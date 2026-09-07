import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/prefs.dart';
import 'app_colors.dart';

enum ThemeModeSetting { light, dark, system }

const String _themeKey = 'alice_theme_mode';

/// 主题状态。对应 RN 版的 ThemeProvider / useThemeColors / useThemeMode。
///
/// 三种模式：浅色、深色、跟随系统。
/// - 没存过任何选择的新安装，等价于「跟随系统」。
/// - [ThemeModeSetting.system] 会把存储里的键删掉，回到那个初始状态
///   —— 以前只有浅色/深色两个选项，用户点过一次就再也回不到跟随系统。
class ThemeController extends ChangeNotifier {
  ThemeController();

  ThemeModeSetting _mode = ThemeModeSetting.system;
  Brightness _systemBrightness = Brightness.light;
  bool _ready = false;

  ThemeModeSetting get mode => _mode;
  bool get ready => _ready;

  bool get isDark => switch (_mode) {
        ThemeModeSetting.dark => true,
        ThemeModeSetting.light => false,
        ThemeModeSetting.system => _systemBrightness == Brightness.dark,
      };

  AppColors get colors => isDark ? AppColors.dark : AppColors.light;

  /// 载入持久化的选择；没有存过就跟随系统。
  Future<void> load(Brightness systemBrightness) async {
    _systemBrightness = systemBrightness;
    final stored = await Prefs.getString(_themeKey);
    _mode = switch (stored) {
      'dark' => ThemeModeSetting.dark,
      'light' => ThemeModeSetting.light,
      _ => ThemeModeSetting.system,
    };
    _ready = true;
    notifyListeners();
  }

  /// 系统亮暗切换时调用 —— 只有「跟随系统」时才真的变色。
  void syncSystemBrightness(Brightness brightness) {
    if (_systemBrightness == brightness) return;
    final wasDark = isDark;
    _systemBrightness = brightness;
    if (isDark != wasDark) notifyListeners();
  }

  void setMode(ThemeModeSetting next) {
    if (next == _mode) return;
    _mode = next;
    // 跟随系统 = 没有显式选择，所以是删键而不是写一个新值。
    // 写成 'system' 的话，老版本读到不认识的值也会当作跟随系统，但删键更干净。
    if (next == ThemeModeSetting.system) {
      Prefs.remove(_themeKey);
    } else {
      Prefs.setString(
          _themeKey, next == ThemeModeSetting.dark ? 'dark' : 'light');
    }
    notifyListeners();
  }
}

/// `context.colors` —— 等价于 RN 版的 `useThemeColors()`。
extension ThemeColorsX on BuildContext {
  AppColors get colors => watch<ThemeController>().colors;
  ThemeController get themeController => read<ThemeController>();
}

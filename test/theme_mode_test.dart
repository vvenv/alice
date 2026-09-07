import 'package:alice_dictation/services/prefs.dart';
import 'package:alice_dictation/theme/theme_controller.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 主题三档：浅色 / 深色 / 跟随系统。
///
/// 0.7.6 之前设置页只给了浅色和深色两个选项，而「跟随系统」是隐含的初始态
/// —— 用户点过任意一个之后就再也回不去了。这里钉住往返都走得通。
void main() {
  WidgetsFlutterBinding.ensureInitialized();

  const themeKey = 'alice_theme_mode';

  setUpAll(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await Prefs.init();
  });

  setUp(() async {
    await Prefs.remove(themeKey);
  });

  test('没存过选择时跟随系统', () async {
    final c = ThemeController();
    await c.load(Brightness.dark);

    expect(c.mode, ThemeModeSetting.system);
    expect(c.isDark, isTrue);
  });

  test('跟随系统时，系统亮暗切换会跟着变', () async {
    final c = ThemeController();
    await c.load(Brightness.light);
    expect(c.isDark, isFalse);

    var notified = 0;
    c.addListener(() => notified++);

    c.syncSystemBrightness(Brightness.dark);

    expect(c.isDark, isTrue);
    expect(notified, 1);
  });

  test('显式选了浅色之后，系统切到深色也不跟', () async {
    final c = ThemeController();
    await c.load(Brightness.light);

    c.setMode(ThemeModeSetting.light);
    c.syncSystemBrightness(Brightness.dark);

    expect(c.mode, ThemeModeSetting.light);
    expect(c.isDark, isFalse);
  });

  test('显式选择会落盘，重启后还在', () async {
    final first = ThemeController();
    await first.load(Brightness.light);
    first.setMode(ThemeModeSetting.dark);
    await pumpEventQueue();

    final second = ThemeController();
    await second.load(Brightness.light);

    expect(second.mode, ThemeModeSetting.dark);
    expect(second.isDark, isTrue);
  });

  // 这条是这次改动的重点：以前没有回头路。
  test('从深色切回跟随系统，会删掉存储里的键并重新跟随', () async {
    final c = ThemeController();
    await c.load(Brightness.light);
    c.setMode(ThemeModeSetting.dark);
    await pumpEventQueue();
    expect(c.isDark, isTrue);

    c.setMode(ThemeModeSetting.system);
    await pumpEventQueue();

    expect(c.mode, ThemeModeSetting.system);
    expect(c.isDark, isFalse, reason: '系统当前是浅色');
    expect(await Prefs.getString(themeKey), isNull);

    c.syncSystemBrightness(Brightness.dark);
    expect(c.isDark, isTrue);
  });
}

import 'package:alice_dictation/screens/dictation_screen.dart';
import 'package:alice_dictation/screens/home_screen.dart';
import 'package:alice_dictation/screens/settings_screen.dart';
import 'package:alice_dictation/services/dictionary.dart';
import 'package:alice_dictation/services/library_data.dart';
import 'package:alice_dictation/services/prefs.dart';
import 'package:alice_dictation/state/ocr_quota_controller.dart';
import 'package:alice_dictation/theme/theme_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 底部内容与屏幕下边缘之间要留够手势条的位置。
///
/// 用户报过「底部太贴近屏幕（可用区域）边缘」。这里模拟一条 24dp 的手势条
/// 安全区，量最底部的可交互控件离屏幕底还有多远 —— SafeArea 撑开的部分要能
/// 完整让出手势条，再加上一点视觉留白。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  /// Android 手势导航的典型底部安全区。
  const double gestureInset = 24;

  /// 手势条之外还应该留的视觉呼吸量。
  const double minBreathingRoom = 12;

  setUpAll(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await Prefs.init();
    await loadDictionary();
    await loadLibrary();
  });

  Widget wrap(Widget child) {
    final themeController = ThemeController();
    return MultiProvider(
      providers: [
        ChangeNotifierProvider<ThemeController>.value(value: themeController),
        ChangeNotifierProvider(create: (_) => OcrQuotaController()),
      ],
      child: MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(
            size: Size(390, 844),
            padding: EdgeInsets.only(top: 47, bottom: gestureInset),
            viewPadding: EdgeInsets.only(top: 47, bottom: gestureInset),
          ),
          child: child,
        ),
      ),
    );
  }

  /// 最底部控件的下边缘到屏幕底的距离。
  double gapBelow(WidgetTester tester, Finder finder) {
    final box = tester.getRect(finder);
    final screenHeight = tester.view.physicalSize.height / tester.view.devicePixelRatio;
    return screenHeight - box.bottom;
  }

  testWidgets('首页：开始听写按钮离屏幕底留够手势条', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(wrap(const HomeScreen()));
    await tester.pumpAndSettle();

    final gap = gapBelow(tester, find.text('开始听写'));
    expect(
      gap,
      greaterThanOrEqualTo(gestureInset + minBreathingRoom),
      reason: '开始听写按钮离屏幕底只有 ${gap}px，手势条要 ${gestureInset}px',
    );
  });

  testWidgets('设置页：最后一行离屏幕底留够手势条', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(wrap(const SettingsScreen()));
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(find.text('清空发音缓存'), 300);
    await tester.pumpAndSettle();

    final listBottom = tester.getRect(find.byType(ListView)).bottom;
    final screenHeight =
        tester.view.physicalSize.height / tester.view.devicePixelRatio;
    final gap = screenHeight - listBottom;
    expect(
      gap,
      greaterThanOrEqualTo(gestureInset),
      reason: '设置页列表底部离屏幕底只有 ${gap}px',
    );
  });

  testWidgets('听写页：标记错词按钮离屏幕底留够手势条', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      wrap(
        const DictationScreen(
          words: ['apple | n. | 苹果', 'banana'],
          intervalSec: 7,
          autoNext: true,
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    final gap = gapBelow(tester, find.text('标记错词'));
    expect(
      gap,
      greaterThanOrEqualTo(gestureInset + minBreathingRoom),
      reason: '标记错词按钮离屏幕底只有 ${gap}px，手势条要 ${gestureInset}px',
    );
  });
}

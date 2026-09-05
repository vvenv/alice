import 'package:alice_dictation/screens/dictation_screen.dart';
import 'package:alice_dictation/screens/home_screen.dart';
import 'package:alice_dictation/screens/settings_screen.dart';
import 'package:alice_dictation/services/dictionary.dart';
import 'package:alice_dictation/services/library_data.dart';
import 'package:alice_dictation/services/prefs.dart';
import 'package:alice_dictation/services/storage.dart';
import 'package:alice_dictation/state/ocr_quota_controller.dart';
import 'package:alice_dictation/theme/theme_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 三个屏幕的冒烟测试：能否在两套主题下构建出来而不抛异常。
///
/// 这类测试抓不到视觉问题，但能抓住迁移里最常见的一类错误 ——
/// 约束冲突、Positioned 不在 Stack 里、provider 找不到、空安全炸掉，
/// 这些在真机上都是白屏或红屏。
///
/// 平台插件（flutter_tts / just_audio / path_provider / image_picker）在
/// 测试环境里没有实现，相关调用会抛 MissingPluginException —— 业务代码
/// 本来就都做了防御性捕获，这里正好顺带验证那些 catch 是真的兜住了。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await Prefs.init();
    await loadDictionary();
    await loadLibrary();
  });

  Widget wrap(Widget child, {required bool dark}) {
    final themeController = ThemeController();
    if (dark) themeController.setMode(ThemeModeSetting.dark);

    return MultiProvider(
      providers: [
        ChangeNotifierProvider<ThemeController>.value(value: themeController),
        ChangeNotifierProvider(create: (_) => OcrQuotaController()),
      ],
      child: MaterialApp(home: child),
    );
  }

  for (final dark in [false, true]) {
    final mode = dark ? '深色' : '浅色';

    testWidgets('HomeScreen 能构建（$mode）', (tester) async {
      await tester.pumpWidget(wrap(const HomeScreen(), dark: dark));
      // 首帧是加载态，等 _bootstrap 读完存储。
      await tester.pumpAndSettle();

      expect(find.text('Alice'), findsOneWidget);
      expect(find.text('听写'), findsOneWidget);
      expect(find.text('单词列表'), findsOneWidget);
      expect(find.text('开始听写'), findsOneWidget);
    });

    testWidgets('SettingsScreen 能构建（$mode）', (tester) async {
      await tester.pumpWidget(wrap(const SettingsScreen(), dark: dark));
      await tester.pumpAndSettle();

      expect(find.text('设置'), findsOneWidget);
      expect(find.text('外观'), findsOneWidget);
      expect(find.text('发音源'), findsOneWidget);
      expect(find.text('朗读中文释义'), findsOneWidget);

      // 下面这些分组在首屏之外，ListView 还没构建到 —— 逐个滚过去，
      // 顺带验证整条滚动路径不会因为约束问题炸掉。
      await tester.scrollUntilVisible(find.text('识别服务'), 300);
      expect(find.text('识别服务'), findsOneWidget);

      await tester.scrollUntilVisible(find.text('清空发音缓存'), 300);
      expect(find.text('清空发音缓存'), findsOneWidget);
    });

    testWidgets('DictationScreen 能构建（$mode）', (tester) async {
      await tester.pumpWidget(
        wrap(
          const DictationScreen(
            words: ['apple | n. | 苹果', 'banana', 'cat'],
            intervalSec: 7,
            autoNext: true,
          ),
          dark: dark,
        ),
      );
      // 不用 pumpAndSettle —— 倒计时动画一直在跑，永远 settle 不了。
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('错词本 (0)'), findsOneWidget);
      expect(find.text('尚无错词'), findsOneWidget);
      // 单词默认隐藏
      expect(find.text('•••••'), findsOneWidget);
    });
  }

  testWidgets('首页：写进存储的历史能在历史抽屉里看到', (tester) async {
    // 直接写存储，再让首页启动时把它读出来 —— 覆盖「保存了但看不见」这一半。
    await clearWordHistory();
    await addWordHistory('zebra\nyak\nxylophone');

    await tester.pumpWidget(wrap(const HomeScreen(), dark: false));
    await tester.pumpAndSettle();

    await tester.tap(find.bySemanticsLabel('菜单'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('历史记录'));
    await tester.pumpAndSettle();

    expect(find.textContaining('zebra'), findsWidgets);
  });

  testWidgets('设置页：发音源弹窗能打开并切到自定义接口', (tester) async {
    await tester.pumpWidget(wrap(const SettingsScreen(), dark: false));
    await tester.pumpAndSettle();

    await tester.tap(find.text('发音源'));
    await tester.pumpAndSettle();

    // 默认是有道，说明文案与服务商预设都还没出现
    expect(find.text('当前使用有道词典发音'), findsOneWidget);
    expect(find.text('小米 MiMo'), findsNothing);

    await tester.tap(find.text('自定义接口'));
    await tester.pumpAndSettle();

    // 切过去之后：预设、接口类型、各个字段都在
    expect(find.text('小米 MiMo'), findsOneWidget);
    expect(find.text('Chat Completions'), findsOneWidget);
    expect(find.text('接口地址 (Base URL)'), findsOneWidget);
    expect(find.text('模型名称'), findsOneWidget);
    expect(find.text('英文音色'), findsOneWidget);

    // 选预设会把地址/模型填好
    await tester.tap(find.text('小米 MiMo'));
    await tester.pumpAndSettle();
    expect(
      find.widgetWithText(TextField, 'https://api.xiaomimimo.com/v1'),
      findsOneWidget,
    );
    expect(
      find.widgetWithText(TextField, 'mimo-v2.5-tts'),
      findsOneWidget,
    );
  });

  testWidgets('听写页：眼睛按钮切换单词显示', (tester) async {
    await tester.pumpWidget(
      wrap(
        const DictationScreen(
          words: ['apple | n. | 苹果', 'banana'],
          intervalSec: 7,
          autoNext: true,
        ),
        dark: false,
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('•••••'), findsOneWidget);
    expect(find.text('apple'), findsNothing);

    await tester.tap(find.bySemanticsLabel('显示单词'));
    await tester.pump();

    expect(find.text('•••••'), findsNothing);
    expect(find.text('apple'), findsOneWidget);
    expect(find.text('n. 苹果'), findsOneWidget);
  });

  testWidgets('首页：示例按钮填入单词并显示词数', (tester) async {
    await tester.pumpWidget(wrap(const HomeScreen(), dark: false));
    await tester.pumpAndSettle();

    // 空列表时是编辑模式，底部有「示例」「清空」
    await tester.tap(find.text('示例'));
    await tester.pumpAndSettle();

    // 词数在两处显示：「单词列表」右侧的徽标，和「开始听写」按钮里的徽标。
    expect(find.text('7 词'), findsNWidgets(2));

    // 有词之后才允许切换展示模式，「编辑」按钮出现。
    expect(find.text('编辑'), findsOneWidget);
  });
}

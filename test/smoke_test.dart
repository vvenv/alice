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
      expect(find.textContaining('每行一个单词'), findsOneWidget);
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

  // 抽屉高度：底部面板过去是外面算一个 bodyMaxHeight、抽屉自己再减掉搜索行，
  // 而词库抽屉的标题是画在正文里的（外面按「无标题」算的 chrome），这 36px
  // 没人减 —— 正文比拿到的空间高一截，列表把抽屉底撑破。
  //
  // 矮屏才看得见：屏幕够高时列表内容撑不满 ConstrainedBox，多要的那点空间
  // 没人去用。390x844 上一切正常，390x420 上就是 36px 的 RenderFlex 溢出。
  testWidgets('首页：矮屏上打开词库抽屉不溢出', (tester) async {
    tester.view.physicalSize = const Size(390, 420);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(wrap(const HomeScreen(), dark: false));
    await tester.pumpAndSettle();

    await tester.tap(find.bySemanticsLabel('菜单'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('词库'));
    await tester.pumpAndSettle();

    expect(find.textContaining('词库 ('), findsOneWidget);
    expect(find.text('搜索标题或分类'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

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

    // 展示态标题改成起点，词数仍在徽标和「开始听写」按钮里各出现一次。
    expect(find.text('从 apple 开始'), findsOneWidget);
    expect(find.text('7 词'), findsNWidgets(2));

    // 有词之后才允许切换展示模式，「编辑」按钮出现。
    expect(find.text('编辑'), findsOneWidget);
  });

  testWidgets('首页：空列表输入后仍保持编辑态', (tester) async {
    await saveWordInput('');
    await tester.pumpWidget(wrap(const HomeScreen(), dark: false));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'hello');
    await tester.pump();

    // 还在编辑：底部「示例 / 清空」还在，标题行是「完成」而不是「编辑」。
    expect(find.text('示例'), findsOneWidget);
    expect(find.text('清空'), findsOneWidget);
    expect(find.text('完成'), findsOneWidget);
    expect(find.text('编辑'), findsNothing);
    expect(find.text('1 个单词'), findsOneWidget);
  });

  testWidgets('首页：点完成会去掉重复单词', (tester) async {
    await saveWordInput('');
    await tester.pumpWidget(wrap(const HomeScreen(), dark: false));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'apple\nbanana\napple\nApple');
    await tester.pump();
    expect(find.text('4 个单词'), findsOneWidget);

    await tester.tap(find.text('完成'));
    await tester.pumpAndSettle();

    expect(find.text('从 apple 开始'), findsOneWidget);
    // 词数在标题徽标和「开始听写」按钮里各出现一次。
    expect(find.text('2 词'), findsNWidgets(2));
    expect(find.text('apple'), findsOneWidget);
    expect(find.text('banana'), findsOneWidget);
    expect(find.text('Apple'), findsNothing);
  });

  testWidgets('首页：单词列表标题行高度不随按钮显隐变化', (tester) async {
    await saveWordInput('');
    await tester.pumpWidget(wrap(const HomeScreen(), dark: false));
    await tester.pumpAndSettle();

    final header = find.byKey(const Key('word-list-header'));
    final emptyHeight = tester.getSize(header).height;

    await tester.tap(find.text('示例'));
    await tester.pumpAndSettle();

    expect(tester.getSize(header).height, emptyHeight);
  });
}

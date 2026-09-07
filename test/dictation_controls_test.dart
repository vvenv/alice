import 'package:alice_dictation/screens/dictation_screen.dart';
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

/// 听写页的操作区。
///
/// 这里钉的是「有哪些操作、以及不可逆的操作有没有拦一道」，时序留给
/// playback_scheduler_test.dart（那边用假 SpeechPort，能断言读了几遍）。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await Prefs.init();
    await loadDictionary();
    await loadLibrary();
  });

  setUp(() async {
    await clearWrongWordsBook();
  });

  Future<void> pumpDictation(WidgetTester tester, {Size? size}) async {
    if (size != null) {
      tester.view.physicalSize = size * 3;
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
    }

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider(create: (_) => ThemeController()),
          ChangeNotifierProvider(create: (_) => OcrQuotaController()),
        ],
        child: const MaterialApp(
          home: DictationScreen(
            words: ['apple | n. | 苹果', 'banana', 'cat'],
            intervalSec: 7,
            autoNext: true,
          ),
        ),
      ),
    );
    // 倒计时动画一直在跑，pumpAndSettle 永远 settle 不了。
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
  }

  testWidgets('控制行有「重听」，「结束」不再重复占一格', (tester) async {
    await pumpDictation(tester);

    expect(find.text('重听'), findsOneWidget);
    // 退出仍然在页头左上角（以及系统返回键），只是不再在控制行里重复一次。
    expect(find.bySemanticsLabel('退出听写'), findsOneWidget);
    expect(find.text('结束'), findsNothing);
  });

  testWidgets('表盘可点按重听，无障碍提示说明了三个手势', (tester) async {
    await pumpDictation(tester);

    // 按 Semantics widget 自己的属性找，而不是 find.bySemanticsLabel ——
    // 表盘里还嵌着单词与倒计时，渲染出来的 semantics 节点标签是合并过的。
    final dial = find.byWidgetPredicate(
      (w) => w is Semantics && w.properties.label == '听写表盘',
    );
    expect(dial, findsOneWidget);

    final props = (tester.widget(dial) as Semantics).properties;
    expect(props.hint, contains('点按再读一遍'));
    expect(props.hint, contains('向左滑标记错词'));

    // 点下去不该抛异常（测试环境没有 TTS 插件，业务代码自己兜住）。
    await tester.tap(dial, warnIfMissed: false);
    await tester.pump();
    expect(tester.takeException(), isNull);
  });

  testWidgets('听写中能直接调语速，不必退出去设置页', (tester) async {
    await pumpDictation(tester);

    expect(find.textContaining('语速'), findsOneWidget);

    await tester.tap(find.textContaining('语速'));
    await tester.pumpAndSettle();

    expect(find.text('朗读'), findsOneWidget);
    expect(find.text('朗读中文释义'), findsOneWidget);
    expect(find.textContaining('下一个词'), findsOneWidget);
  });

  // 删单个错词一直有撤销，整批清空却是一键不可逆 —— 而且它还会把这些词
  // 从累计错词本里一并撤掉。
  testWidgets('清空错词要先确认', (tester) async {
    await pumpDictation(tester);

    await tester.tap(find.text('标记错词'));
    await tester.pump();
    expect(find.text('本轮错词 (1)'), findsOneWidget);

    await tester.tap(find.text('清空'));
    await tester.pumpAndSettle();

    expect(find.text('清空错词'), findsOneWidget);
    expect(find.textContaining('也会从错词本里移除'), findsOneWidget);

    // 取消：错词还在。
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(find.text('本轮错词 (1)'), findsOneWidget);
  });

  testWidgets('确认清空后留一手撤销', (tester) async {
    await pumpDictation(tester);

    await tester.tap(find.text('标记错词'));
    await tester.pump();

    await tester.tap(find.text('清空'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(GestureDetector, '清空').last);
    await tester.pumpAndSettle();

    expect(find.text('本轮错词 (0)'), findsOneWidget);
    expect(find.text('撤销'), findsOneWidget);

    await tester.tap(find.text('撤销'));
    await tester.pumpAndSettle();
    expect(find.text('本轮错词 (1)'), findsOneWidget);
  });

  // 底部面板那一行现在是「自动播放 [开关]」+「语速 0.9x」，最窄的机型上
  // 最容易挤破。
  testWidgets('窄屏上底部面板不溢出，语速入口仍在', (tester) async {
    await pumpDictation(tester, size: const Size(320, 640));

    expect(find.textContaining('语速'), findsOneWidget);
    expect(find.text('重听'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('没有错词时点清空只给个提示，不弹确认框', (tester) async {
    await pumpDictation(tester);

    await tester.tap(find.text('清空'));
    await tester.pumpAndSettle();

    expect(find.text('清空错词'), findsNothing);
    expect(find.text('尚无错词'), findsWidgets);
  });
}

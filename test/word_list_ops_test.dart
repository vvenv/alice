import 'package:alice_dictation/screens/home_screen.dart';
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

/// 词表的破坏性操作都得有退路。
///
/// 删除是列表行里一个 20px 的 ✕，旁边就是「点词设为起点」的点击区 ——
/// 误触代价不小：刚 OCR 识出来三十个词，误删一个就得重拍。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await Prefs.init();
    await loadDictionary();
    await loadLibrary();
  });

  setUp(() async {
    await saveWordInput('apple\nbanana\ncat');
  });

  Widget wrap(Widget child, {Size? size}) {
    final app = MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => ThemeController()),
        ChangeNotifierProvider(create: (_) => OcrQuotaController()),
      ],
      child: MaterialApp(home: child),
    );
    return size == null
        ? app
        : MediaQuery(data: MediaQueryData(size: size), child: app);
  }

  testWidgets('删掉一个词可以撤销，位置也回到原处', (tester) async {
    await tester.pumpWidget(wrap(const HomeScreen()));
    await tester.pumpAndSettle();
    expect(find.text('banana'), findsOneWidget);

    await tester.tap(find.bySemanticsLabel('删除 banana'));
    await tester.pumpAndSettle();

    expect(find.text('banana'), findsNothing);
    expect(find.text('已删除 banana'), findsOneWidget);

    await tester.tap(find.text('撤销'));
    await tester.pumpAndSettle();

    expect(find.text('banana'), findsOneWidget);
    // 回到中间那一行，而不是被追加到末尾。
    final rows = tester
        .widgetList<Text>(find.byType(Text))
        .map((t) => t.data)
        .where((d) => d == 'apple' || d == 'banana' || d == 'cat')
        .toList();
    expect(rows, ['apple', 'banana', 'cat']);
  });

  testWidgets('清空词表可以撤销', (tester) async {
    await tester.pumpWidget(wrap(const HomeScreen()));
    await tester.pumpAndSettle();

    await tester.tap(find.text('清空'));
    await tester.pumpAndSettle();

    expect(find.text('apple'), findsNothing);
    expect(find.text('已清空词表'), findsOneWidget);
    // 清空之后回到编辑态，占位提示重新出现。
    expect(find.textContaining('每行一个单词'), findsOneWidget);

    await tester.tap(find.text('撤销'));
    await tester.pumpAndSettle();

    expect(find.text('apple'), findsOneWidget);
    expect(find.text('cat'), findsOneWidget);
  });

  testWidgets('空词表时卡片上没有清空按钮', (tester) async {
    await saveWordInput('');
    await tester.pumpWidget(wrap(const HomeScreen()));
    await tester.pumpAndSettle();

    expect(find.text('清空'), findsNothing);
  });

  // 卡片头现在是「N 个单词 · 点词设为起点」+ 清空 + 完成/编辑，最窄的机型上
  // 最容易挤破。
  testWidgets('窄屏上卡片头不溢出', (tester) async {
    tester.view.physicalSize = const Size(320, 640) * 3;
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(wrap(const HomeScreen()));
    await tester.pumpAndSettle();

    expect(find.text('清空'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

import 'package:alice_dictation/screens/dictation_screen.dart';
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

/// 「接着上次的来」：听写起点跨启动保留，词库抽屉记得上次停在哪。
///
/// 词表本身一直会恢复，起点却每次归零 —— 一份六十词的表听到第四十个退出去，
/// 回来得自己翻回去找；词库同理，一本教材要听一学期，每次都从全折叠开始。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await Prefs.init();
    await loadDictionary();
    await loadLibrary();
  });

  setUp(() async {
    await saveWordInput('');
    await saveStartIndex(0);
    await saveLibraryCategory(null);
    await saveLibraryItemId(null);
  });

  Widget wrap(Widget child) => MultiProvider(
        providers: [
          ChangeNotifierProvider(create: (_) => ThemeController()),
          ChangeNotifierProvider(create: (_) => OcrQuotaController()),
        ],
        child: MaterialApp(home: child),
      );

  void usePhone(WidgetTester tester, [Size size = const Size(390, 844)]) {
    tester.view.physicalSize = size * 3;
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
  }

  // 词典里查不到的词，免得补全出来的释义把行高和文本搅乱。
  final words = [
    for (var i = 0; i < 60; i++)
      'zq${String.fromCharCode(97 + i ~/ 26)}${String.fromCharCode(97 + i % 26)}',
  ];

  group('听写起点', () {
    test('读写往返，坏值回落到 0', () async {
      await saveStartIndex(17);
      expect(await loadStartIndex(), 17);

      await saveStartIndex(-3);
      expect(await loadStartIndex(), 0);

      await Prefs.setString('alice_start_index', 'oops');
      expect(await loadStartIndex(), 0);
    });

    testWidgets('重新打开应用停在上次的词上，并且滚到了它', (tester) async {
      usePhone(tester);
      await saveWordInput(words.join('\n'));
      await saveStartIndex(40);

      await tester.pumpWidget(wrap(const HomeScreen()));
      await tester.pumpAndSettle();

      // 列表是懒构建的：第 41 个词找得到，说明已经滚过去了。
      expect(find.text(words[40]), findsOneWidget);
      expect(find.text(words[0]), findsNothing);
    });

    testWidgets('词表比存下来的起点短时收回到最后一个词', (tester) async {
      usePhone(tester);
      await saveWordInput(words.take(3).join('\n'));
      await saveStartIndex(40);

      await tester.pumpWidget(wrap(const HomeScreen()));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(await loadStartIndex(), 2);
    });

    testWidgets('点词设起点会落盘', (tester) async {
      usePhone(tester);
      await saveWordInput(words.join('\n'));

      await tester.pumpWidget(wrap(const HomeScreen()));
      await tester.pumpAndSettle();

      await tester.tap(find.text(words[3]));
      await tester.pumpAndSettle();

      expect(await loadStartIndex(), 3);
    });

    testWidgets('从词库载入一份词表会立刻落盘，起点归零', (tester) async {
      usePhone(tester);
      await saveWordInput(words.join('\n'));
      await saveStartIndex(40);

      await tester.pumpWidget(wrap(const HomeScreen()));
      await tester.pumpAndSettle();

      await tester.tap(find.bySemanticsLabel('词库'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('高考3500'));
      await tester.pumpAndSettle();
      await tester.tap(find.bySemanticsLabel('载入 B'));
      await tester.pumpAndSettle();

      // 不等防抖、不等 dispose：这时候杀掉应用，回来也得是这一份。
      expect(await loadWordInput(), isNot(contains(words[0])));
      expect(await loadWordInput(), isNotEmpty);
      expect(await loadStartIndex(), 0);
    });

    testWidgets('听写页每换一个词就往外报下标', (tester) async {
      final reported = <int>[];
      await tester.pumpWidget(
        wrap(
          DictationScreen(
            words: const ['apple', 'banana', 'cat'],
            intervalSec: 7,
            autoNext: true,
            onIndexChanged: reported.add,
          ),
        ),
      );
      // 倒计时动画一直在跑，pumpAndSettle 永远 settle 不了。
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      await tester.tap(find.text('下一个'));
      await tester.pump();
      await tester.tap(find.text('下一个'));
      await tester.pump();
      await tester.tap(find.text('上一个'));
      await tester.pump();

      expect(reported, [1, 2, 1]);
    });
  });

  group('词库抽屉', () {
    Future<void> openLibrary(WidgetTester tester) async {
      await tester.pumpWidget(wrap(const HomeScreen()));
      await tester.pumpAndSettle();
      await tester.tap(find.bySemanticsLabel('词库'));
      await tester.pumpAndSettle();
    }

    testWidgets('第一次打开全部折叠', (tester) async {
      usePhone(tester);
      await openLibrary(tester);

      expect(find.text('人教版小学'), findsOneWidget);
      expect(find.text('Unit 1'), findsNothing);
    });

    testWidgets('教材按册分段，格子里只留单元名', (tester) async {
      usePhone(tester);
      await openLibrary(tester);

      await tester.tap(find.text('人教版小学'));
      await tester.pumpAndSettle();

      expect(find.text('三上'), findsOneWidget);
      expect(find.text('Unit 1'), findsWidgets);
      expect(find.text('三上 Unit 1'), findsNothing);
      // 读屏仍然报完整的名字。
      expect(find.bySemanticsLabel('载入 三上 Unit 1'), findsOneWidget);

      // 格子：同一册的前两个单元在同一行上。
      final first = tester.getTopLeft(find.bySemanticsLabel('载入 三上 Unit 1'));
      final second = tester.getTopLeft(find.bySemanticsLabel('载入 三上 Unit 2'));
      expect(second.dy, first.dy);
      expect(second.dx, greaterThan(first.dx));
    });

    testWidgets('再次打开时展开上次选过的分类，并标出那一条', (tester) async {
      usePhone(tester);
      await openLibrary(tester);

      await tester.tap(find.text('人教版小学'));
      await tester.pumpAndSettle();
      await tester.tap(find.bySemanticsLabel('载入 三上 Unit 2'));
      await tester.pumpAndSettle();

      expect(loadLibraryCategory(), '人教版小学');

      await tester.tap(find.bySemanticsLabel('词库'));
      await tester.pumpAndSettle();

      expect(find.text('三上'), findsOneWidget);
      expect(
        find.byWidgetPredicate(
          (w) =>
              w is Semantics &&
              w.properties.label == '载入 三上 Unit 2' &&
              w.properties.selected == true,
        ),
        findsOneWidget,
      );
      // 别的分类照旧折着。
      expect(find.bySemanticsLabel('载入 A'), findsNothing);
    });

    testWidgets('上次那条在好几屏之外时，打开就滚到它跟前', (tester) async {
      usePhone(tester);
      final group = getLibraryGroups().firstWhere((g) => g.category == '人教版小学');
      await saveLibraryCategory(group.category);
      await saveLibraryItemId(group.items.last.entry.id);
      await openLibrary(tester);

      final cell = find.bySemanticsLabel('载入 ${group.items.last.label}');
      expect(cell, findsOneWidget);
      // 整格都在屏幕里，点得到。
      expect(tester.getBottomLeft(cell).dy, lessThan(844));
      await tester.tap(cell);
      await tester.pumpAndSettle();
      expect(find.textContaining('词库 ('), findsNothing);
    });

    testWidgets('把记住的分类收起来就不再记它', (tester) async {
      usePhone(tester);
      await saveLibraryCategory('高考3500');
      await openLibrary(tester);

      expect(find.bySemanticsLabel('载入 A'), findsOneWidget);

      await tester.tap(find.text('高考3500'));
      await tester.pumpAndSettle();

      expect(find.bySemanticsLabel('载入 A'), findsNothing);
      expect(loadLibraryCategory(), isNull);
    });

    // 320 宽 + 最长的标签（Starter Unit 1）是格子最挤的组合。
    testWidgets('最窄的机型上格子不溢出', (tester) async {
      usePhone(tester, const Size(320, 640));
      await saveLibraryCategory('人教版初中');
      await openLibrary(tester);

      expect(find.text('Starter Unit 1'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}

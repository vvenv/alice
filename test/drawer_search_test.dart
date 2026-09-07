import 'package:alice_dictation/screens/home_screen.dart';
import 'package:alice_dictation/services/dictionary.dart';
import 'package:alice_dictation/services/library_data.dart';
import 'package:alice_dictation/services/prefs.dart';
import 'package:alice_dictation/services/storage.dart';
import 'package:alice_dictation/state/ocr_quota_controller.dart';
import 'package:alice_dictation/theme/theme_controller.dart';
import 'package:alice_dictation/widgets/drawer_search_field.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 历史与收藏的搜索。
///
/// 词库一直有搜索框，历史却只能一路滚 —— 而它的上限是 50 条。
/// 条目少的时候搜索框只是噪音，所以有个出现门槛。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await Prefs.init();
    await loadDictionary();
    await loadLibrary();
  });

  setUp(() async {
    await clearWordHistory();
    await saveWordInput('');
  });

  Widget wrap(Widget child) => MultiProvider(
        providers: [
          ChangeNotifierProvider(create: (_) => ThemeController()),
          ChangeNotifierProvider(create: (_) => OcrQuotaController()),
        ],
        child: MaterialApp(home: child),
      );

  // 首页的词表输入框也是 TextField，得把范围限定在搜索框里。
  final searchField = find.descendant(
    of: find.byType(DrawerSearchField),
    matching: find.byType(TextField),
  );

  Future<void> openHistory(WidgetTester tester) async {
    await tester.pumpWidget(wrap(const HomeScreen()));
    await tester.pumpAndSettle();
    await tester.tap(find.bySemanticsLabel('菜单'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('历史记录'));
    await tester.pumpAndSettle();
  }

  testWidgets('历史少于门槛时不出搜索框', (tester) async {
    for (final w in ['alpha', 'bravo', 'charlie']) {
      await addWordHistory(w);
    }

    await openHistory(tester);

    expect(find.text('历史记录 (3)'), findsOneWidget);
    expect(find.text('搜索词表内容'), findsNothing);
  });

  testWidgets('历史多起来出搜索框，按词表正文过滤', (tester) async {
    for (final w in [
      'alpha',
      'bravo',
      'charlie',
      'delta',
      'echo',
      'foxtrot',
      'elephant',
    ]) {
      await addWordHistory(w);
    }

    await openHistory(tester);
    expect(find.text('历史记录 (7)'), findsOneWidget);
    expect(find.text('搜索词表内容'), findsOneWidget);

    await tester.enterText(searchField, 'eleph');
    await tester.pumpAndSettle();

    // 标题给出「命中 / 总数」，别让用户以为记录丢了。
    expect(find.text('历史记录 (1/7)'), findsOneWidget);
    expect(find.text('elephant'), findsOneWidget);
    expect(find.text('alpha'), findsNothing);
  });

  testWidgets('搜不到时说得清楚，清除按钮能还原', (tester) async {
    for (final w in ['a1', 'b2', 'c3', 'd4', 'e5', 'f6']) {
      await addWordHistory(w);
    }

    await openHistory(tester);
    await tester.enterText(searchField, 'zzzz');
    await tester.pumpAndSettle();

    expect(find.text('没有匹配的历史记录'), findsOneWidget);

    await tester.tap(find.bySemanticsLabel('清除搜索'));
    await tester.pumpAndSettle();

    expect(find.text('历史记录 (6)'), findsOneWidget);
    expect(find.text('没有匹配的历史记录'), findsNothing);
  });
}

import 'dart:math';

import 'package:alice_dictation/screens/dictation_screen.dart';
import 'package:alice_dictation/screens/home_screen.dart';
import 'package:alice_dictation/services/dictation.dart';
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

/// 乱序听写之后要能按播出顺序对答案，同时原文还在。
///
/// 词表本身会进历史，但历史存的是打乱前的草稿。对答案要的是当时
/// 耳朵听到的那个顺序，所以单独留一份「上次听写」。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await Prefs.init();
    await loadDictionary();
    await loadLibrary();
  });

  setUp(() async {
    debugShuffleRandom = null;
    await saveWordInput('');
    await saveLastPlayback('');
    await clearCustomLists();
    await clearWordHistory();
  });

  tearDown(() {
    debugShuffleRandom = null;
  });

  Widget wrap(Widget child) => MultiProvider(
        providers: [
          ChangeNotifierProvider(create: (_) => ThemeController()),
          ChangeNotifierProvider(create: (_) => OcrQuotaController()),
        ],
        child: MaterialApp(home: child),
      );

  void usePhone(WidgetTester tester) {
    tester.view.physicalSize = const Size(390, 844) * 3;
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
  }

  Future<void> typeWords(WidgetTester tester) async {
    await tester.enterText(find.byType(TextField), 'apple\nbanana\ncat\ndog');
    await tester.pump();
  }

  testWidgets('乱序听完回到首页，上次听写是播出顺序，当前词表仍是原文', (tester) async {
    debugShuffleRandom = Random(1);
    usePhone(tester);

    await tester.pumpWidget(wrap(const HomeScreen()));
    await tester.pumpAndSettle();
    await typeWords(tester);

    await tester.tap(find.bySemanticsLabel('打乱播放顺序'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('开始听写'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.byType(DictationScreen), findsOneWidget);
    final played =
        tester.widget<DictationScreen>(find.byType(DictationScreen));
    final playedWords = [
      for (final line in played.words) speakTextFromEntry(line),
    ];
    expect(playedWords, isNot(orderedEquals(['apple', 'banana', 'cat', 'dog'])));

    final navigator = tester.state<NavigatorState>(find.byType(Navigator));
    navigator.pop();
    await tester.pumpAndSettle();

    expect(find.text('上次听写'), findsOneWidget);
    expect(find.textContaining('按播放顺序对答案'), findsOneWidget);
    final shown = tester
        .widgetList<Text>(find.byType(Text))
        .map((t) => t.data)
        .whereType<String>()
        .toList();
    for (final word in playedWords) {
      expect(shown, contains(word));
    }
    // 播出顺序要和屏幕上的上下顺序一致。
    final tops = <String, double>{};
    for (final word in playedWords) {
      tops[word] = tester.getTopLeft(find.text(word).first).dy;
    }
    final onScreen = playedWords.toList()
      ..sort((a, b) => tops[a]!.compareTo(tops[b]!));
    expect(onScreen, playedWords);

    expect(await loadLastPlayback(), played.words.join('\n'));

    await tester.tap(find.text('当前词表'));
    await tester.pumpAndSettle();
    expect(find.textContaining('按播放顺序对答案'), findsNothing);
    final field = tester.widget<TextField>(find.byType(TextField));
    expect(
      parseWords(field.controller!.text).map(speakTextFromEntry).toList(),
      ['apple', 'banana', 'cat', 'dog'],
    );
  });

  testWidgets('上次听写可以存进我的词库，再载入时回到当前词表', (tester) async {
    usePhone(tester);
    await saveLastPlayback('dog\ncat\nbanana\napple');
    await saveWordInput('apple\nbanana\ncat\ndog');

    await tester.pumpWidget(wrap(const HomeScreen()));
    await tester.pumpAndSettle();

    expect(find.text('上次听写'), findsOneWidget);
    await tester.tap(find.text('上次听写'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('存入词库').first);
    await tester.pumpAndSettle();
    expect(find.text('存入词库'), findsWidgets);

    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();

    final lists = await loadCustomLists();
    expect(lists, hasLength(1));
    expect(plainWordList(lists.single.text), 'dog\ncat\nbanana\napple');

    await tester.tap(find.bySemanticsLabel('词库'));
    await tester.pumpAndSettle();
    expect(find.text('我的词库'), findsOneWidget);
    await tester.tap(find.text('我的词库'));
    await tester.pumpAndSettle();

    await tester.longPress(find.bySemanticsLabel('载入 ${lists.single.name}'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('删除'));
    await tester.pumpAndSettle();
    expect(await loadCustomLists(), isEmpty);
    expect(find.text('我的词库'), findsNothing);

    await tester.tap(find.text('人教版小学'));
    await tester.pumpAndSettle();
    await tester.tap(find.bySemanticsLabel('载入 三上 Unit 1'));
    await tester.pumpAndSettle();
    expect(find.textContaining('按播放顺序对答案'), findsNothing);
    expect(find.textContaining('个单词'), findsOneWidget);
  });

  testWidgets('从上次听写的中间再听，完整顺序和起点都还在', (tester) async {
    usePhone(tester);
    const playback = 'dog\ncat\nbanana\napple';
    await saveLastPlayback(playback);
    await saveWordInput('apple\nbanana\ncat\ndog');

    await tester.pumpWidget(wrap(const HomeScreen()));
    await tester.pumpAndSettle();
    await tester.tap(find.text('上次听写'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('banana'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('开始听写'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    final first = tester.widget<DictationScreen>(find.byType(DictationScreen));
    expect(
      first.words.map(speakTextFromEntry).toList(),
      ['banana', 'apple'],
    );
    tester.state<NavigatorState>(find.byType(Navigator)).pop();
    await tester.pumpAndSettle();

    expect(await loadLastPlayback(), playback);
    final tops = <String, double>{};
    for (final word in ['dog', 'cat', 'banana', 'apple']) {
      tops[word] = tester.getTopLeft(find.text(word).first).dy;
    }
    final onScreen = ['dog', 'cat', 'banana', 'apple']
      ..sort((a, b) => tops[a]!.compareTo(tops[b]!));
    expect(onScreen, ['dog', 'cat', 'banana', 'apple']);

    await tester.tap(find.text('开始听写'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    final again = tester.widget<DictationScreen>(find.byType(DictationScreen));
    expect(
      again.words.map(speakTextFromEntry).toList(),
      ['banana', 'apple'],
    );
  });
}

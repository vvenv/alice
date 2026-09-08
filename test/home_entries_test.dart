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

/// 首页的「错词本」入口。
///
/// 累计错词本一直是持久化的，却只有听写页里能看到 —— 想重听昨天的错词，
/// 得先随便开一轮听写。
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
    await clearWrongWordsBook();
  });

  Widget wrap(Widget child, {Size? size}) {
    final app = MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => ThemeController()),
        ChangeNotifierProvider(create: (_) => OcrQuotaController()),
      ],
      child: MaterialApp(home: child),
    );
    if (size == null) return app;
    return MediaQuery(
      data: MediaQueryData(size: size),
      child: app,
    );
  }

  testWidgets('菜单里能打开错词本，看到攒下来的错词', (tester) async {
    await addWrongWordToBook('castle');
    await addWrongWordToBook('whisper');

    await tester.pumpWidget(wrap(const HomeScreen()));
    await tester.pumpAndSettle();

    await tester.tap(find.bySemanticsLabel('菜单'));
    await tester.pumpAndSettle();
    expect(find.text('错词本'), findsOneWidget);

    await tester.tap(find.text('错词本'));
    await tester.pumpAndSettle();

    expect(find.text('错词本 (2)'), findsOneWidget);
    expect(find.text('castle'), findsOneWidget);
    expect(find.text('whisper'), findsOneWidget);
    expect(find.text('听写错词 (2)'), findsOneWidget);
  });

  testWidgets('错词本为空时给出说明，不显示听写按钮', (tester) async {
    await tester.pumpWidget(wrap(const HomeScreen()));
    await tester.pumpAndSettle();

    await tester.tap(find.bySemanticsLabel('菜单'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('错词本'));
    await tester.pumpAndSettle();

    expect(find.text('错词本 (0)'), findsOneWidget);
    expect(find.textContaining('尚无错词'), findsOneWidget);
    expect(find.textContaining('听写错词'), findsNothing);
  });

  testWidgets('在错词本里划掉一个词会同时写回存储', (tester) async {
    await addWrongWordToBook('castle');
    await addWrongWordToBook('whisper');

    await tester.pumpWidget(wrap(const HomeScreen()));
    await tester.pumpAndSettle();

    await tester.tap(find.bySemanticsLabel('菜单'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('错词本'));
    await tester.pumpAndSettle();

    await tester.tap(find.bySemanticsLabel('从错词本移除 castle'));
    await tester.pumpAndSettle();

    expect(find.text('错词本 (1)'), findsOneWidget);
    expect(find.text('castle'), findsNothing);
    expect(loadWrongWords(), ['whisper']);
  });

  // 320px 宽是最挤的机型。品牌行曾经在这里溢出 0.1px，把「写」裁掉半个。
  testWidgets('窄屏上首页不溢出', (tester) async {
    tester.view.physicalSize = const Size(320, 640) * 3;
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(wrap(const HomeScreen()));
    await tester.pumpAndSettle();

    expect(find.text('开始听写'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

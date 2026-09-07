import 'package:alice_dictation/screens/home_screen.dart';
import 'package:alice_dictation/services/dictation.dart';
import 'package:alice_dictation/services/dictionary.dart';
import 'package:alice_dictation/services/library_data.dart';
import 'package:alice_dictation/services/prefs.dart';
import 'package:alice_dictation/services/storage.dart';
import 'package:alice_dictation/state/ocr_quota_controller.dart';
import 'package:alice_dictation/theme/theme_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 「分享到 Alice」。
///
/// 从微信 / 浏览器 / 备忘录里选中一段单词分享过来，直接成词表 —— 比拍照识别
/// 更快，也不消耗 credits。原生侧只有 Android（iOS 要独立的 Share Extension）。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('alice/share');

  setUpAll(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await Prefs.init();
    await loadDictionary();
    await loadLibrary();
  });

  String? pending;

  setUp(() async {
    pending = null;
    await saveWordInput('');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      if (call.method != 'takeSharedText') return null;
      final v = pending;
      pending = null;
      return v;
    });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  Widget wrap(Widget child) => MultiProvider(
        providers: [
          ChangeNotifierProvider(create: (_) => ThemeController()),
          ChangeNotifierProvider(create: (_) => OcrQuotaController()),
        ],
        child: MaterialApp(home: child),
      );

  /// 模拟原生侧在应用运行中推一份分享过来。
  Future<void> pushShared(String text) async {
    await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .handlePlatformMessage(
      channel.name,
      const StandardMethodCodec()
          .encodeMethodCall(MethodCall('sharedText', text)),
      (_) {},
    );
  }

  group('文本归一化', () {
    test('本来就是多行的原样保留', () {
      expect(normalizeSharedText('apple\nbanana\ncat'),
          'apple\nbanana\ncat');
    });

    test('单行带分隔符时拆开', () {
      expect(normalizeSharedText('apple, banana, cat'), 'apple\nbanana\ncat');
      expect(normalizeSharedText('苹果、香蕉、猫'), '苹果\n香蕉\n猫');
      expect(normalizeSharedText('apple；banana'), 'apple\nbanana');
    });

    // 拆空格会把这两种合法写法毁掉。
    test('不拆空格和斜杠', () {
      expect(normalizeSharedText('actor / actress'), 'actor / actress');
      expect(normalizeSharedText("you're = you are"), "you're = you are");
      expect(normalizeSharedText('take off'), 'take off');
    });

    test('空白输入不产出空行', () {
      expect(normalizeSharedText('   '), '');
      expect(normalizeSharedText('apple,,banana'), 'apple\nbanana');
    });
  });

  group('接收', () {
    testWidgets('冷启动时取走原生存着的那一份', (tester) async {
      pending = 'rabbit\ngarden\nmirror';

      await tester.pumpWidget(wrap(const HomeScreen()));
      await tester.pumpAndSettle();

      expect(find.text('rabbit'), findsOneWidget);
      expect(find.text('mirror'), findsOneWidget);
      expect(find.text('已载入分享的 3 个词'), findsOneWidget);
    });

    testWidgets('没有待处理的分享就什么也不做', (tester) async {
      await tester.pumpWidget(wrap(const HomeScreen()));
      await tester.pumpAndSettle();

      expect(find.textContaining('已载入分享'), findsNothing);
      expect(find.text('第一次用？'), findsOneWidget);
    });

    testWidgets('运行中收到分享会换掉当前词表，并留一手撤销', (tester) async {
      await saveWordInput('apple\nbanana');

      await tester.pumpWidget(wrap(const HomeScreen()));
      await tester.pumpAndSettle();
      expect(find.text('apple'), findsOneWidget);

      await pushShared('castle, whisper');
      await tester.pumpAndSettle();

      expect(find.text('castle'), findsOneWidget);
      expect(find.text('apple'), findsNothing);
      expect(find.text('已载入分享的 2 个词'), findsOneWidget);

      await tester.tap(find.text('撤销'));
      await tester.pumpAndSettle();

      expect(find.text('apple'), findsOneWidget);
      expect(find.text('castle'), findsNothing);
    });

    testWidgets('原来是空词表时不给撤销 —— 没什么可回去的', (tester) async {
      await tester.pumpWidget(wrap(const HomeScreen()));
      await tester.pumpAndSettle();

      await pushShared('castle');
      await tester.pumpAndSettle();

      expect(find.text('castle'), findsOneWidget);
      expect(find.text('撤销'), findsNothing);
    });

    testWidgets('分享来的是空白就忽略', (tester) async {
      await saveWordInput('apple');

      await tester.pumpWidget(wrap(const HomeScreen()));
      await tester.pumpAndSettle();

      await pushShared('   ');
      await tester.pumpAndSettle();

      expect(find.text('apple'), findsOneWidget);
      expect(find.textContaining('已载入分享'), findsNothing);
    });
  });
}

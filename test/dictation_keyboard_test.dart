import 'dart:async';

import 'package:alice_dictation/screens/dictation_screen.dart';
import 'package:alice_dictation/services/audio_interruptions.dart';
import 'package:alice_dictation/services/dictionary.dart';
import 'package:alice_dictation/services/library_data.dart';
import 'package:alice_dictation/services/prefs.dart';
import 'package:alice_dictation/state/ocr_quota_controller.dart';
import 'package:alice_dictation/theme/theme_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 听写页的键盘操作。
///
/// Web 是正式发布目标（alice.edao.plus/app/），坐在电脑前听写却只能用鼠标点；
/// 外接键盘的平板同理。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await Prefs.init();
    await loadDictionary();
    await loadLibrary();
  });

  late StreamController<PlaybackInterruption> interruptions;

  setUp(() {
    interruptions = StreamController<PlaybackInterruption>.broadcast();
  });

  tearDown(() => interruptions.close());

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
        child: MaterialApp(
          home: DictationScreen(
            words: const ['apple | n. | 苹果', 'banana', 'cat'],
            intervalSec: 7,
            autoNext: true,
            interruptions: interruptions.stream,
          ),
        ),
      ),
    );
    // 倒计时动画一直在跑，pumpAndSettle 永远 settle 不了。
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
  }

  group('键盘', () {
    testWidgets('空格暂停 / 继续', (tester) async {
      await pumpDictation(tester);
      expect(find.text('听写中'), findsOneWidget);

      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      await tester.pump();
      expect(find.text('已暂停'), findsOneWidget);

      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      await tester.pump();
      expect(find.text('听写中'), findsOneWidget);
    });

    testWidgets('M 标记错词', (tester) async {
      await pumpDictation(tester);
      expect(find.text('本轮错词 (0)'), findsOneWidget);

      await tester.sendKeyEvent(LogicalKeyboardKey.keyM);
      await tester.pump();

      expect(find.text('本轮错词 (1)'), findsOneWidget);
    });

    testWidgets('← → 切词', (tester) async {
      await pumpDictation(tester);
      expect(find.text('1 / 3'), findsOneWidget);

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pump();
      expect(find.text('2 / 3'), findsOneWidget);

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      await tester.pump();
      expect(find.text('1 / 3'), findsOneWidget);
    });

    testWidgets('R 重听不改变词序', (tester) async {
      await pumpDictation(tester);
      expect(find.text('1 / 3'), findsOneWidget);

      await tester.sendKeyEvent(LogicalKeyboardKey.keyR);
      await tester.pump();

      expect(find.text('1 / 3'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('够宽的屏幕上把快捷键写出来，窄屏不占地方', (tester) async {
      await pumpDictation(tester, size: const Size(900, 700));
      expect(find.textContaining('空格 暂停'), findsOneWidget);

      await tester.binding.setSurfaceSize(null);
      await pumpDictation(tester, size: const Size(390, 844));
      expect(find.textContaining('空格 暂停'), findsNothing);
    });
  });
}

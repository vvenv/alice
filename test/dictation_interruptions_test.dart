import 'dart:async';

import 'package:alice_dictation/screens/dictation_screen.dart';
import 'package:alice_dictation/services/audio_interruptions.dart';
import 'package:alice_dictation/services/dictionary.dart';
import 'package:alice_dictation/services/library_data.dart';
import 'package:alice_dictation/services/prefs.dart';
import 'package:alice_dictation/state/ocr_quota_controller.dart';
import 'package:alice_dictation/theme/theme_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 听写被打断时的行为，以及键盘操作。
///
/// 这几条以前全都没有：切后台、来电、拔耳机，调度器一概不理，倒计时照走 ——
/// 那几个词等于白读。三种情况都停在原地，让用户自己决定什么时候继续。
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

  group('打断', () {
    testWidgets('切到后台会暂停，回到前台把原因说出来', (tester) async {
      await pumpDictation(tester);
      expect(find.text('听写中'), findsOneWidget);

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pump();

      expect(find.text('已暂停'), findsOneWidget);
      expect(find.text('听写中'), findsNothing);

      // 回前台不自动续播 —— 用户未必已经拿起笔。
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(find.text('已暂停'), findsOneWidget);
      expect(find.text('切到后台时已暂停'), findsOneWidget);
    });

    testWidgets('音频焦点被抢走会暂停', (tester) async {
      await pumpDictation(tester);
      expect(find.text('听写中'), findsOneWidget);

      interruptions.add(PlaybackInterruption.focusLost);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(find.text('已暂停'), findsOneWidget);
      expect(find.text('音频被打断，已暂停'), findsOneWidget);
    });

    // 耳机一拔，下一个单词会直接从外放喇叭喊出来。
    testWidgets('拔耳机会暂停', (tester) async {
      await pumpDictation(tester);

      interruptions.add(PlaybackInterruption.becameNoisy);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(find.text('已暂停'), findsOneWidget);
      expect(find.text('耳机已断开，已暂停'), findsOneWidget);
    });

    testWidgets('已经暂停时再被打断不会多弹提示', (tester) async {
      await pumpDictation(tester);

      // 点按钮本体：控制行里那个「暂停」是标签，不在点击区内。
      // 按 Semantics widget 的属性找，别用 find.bySemanticsLabel —— 它连
      // 同名的 RichText 一起匹配，命中几个取决于当时的树长什么样。
      await tester.tap(find.byWidgetPredicate(
        (w) => w is Semantics && w.properties.label == '暂停',
      ));
      await tester.pump();
      expect(find.text('已暂停'), findsOneWidget);

      interruptions.add(PlaybackInterruption.becameNoisy);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(find.text('耳机已断开，已暂停'), findsNothing);
    });
  });
}

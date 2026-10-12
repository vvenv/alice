import 'package:alice_dictation/screens/dictation_screen.dart';
import 'package:alice_dictation/services/dictionary.dart';
import 'package:alice_dictation/services/library_data.dart';
import 'package:alice_dictation/services/prefs.dart';
import 'package:alice_dictation/state/ocr_quota_controller.dart';
import 'package:alice_dictation/theme/theme_controller.dart';
import 'package:alice_dictation/widgets/app_button.dart';
import 'package:alice_dictation/widgets/app_icons.dart';
import 'package:alice_dictation/widgets/countdown_ring.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 听写页在真机上的排版：小屏 + 系统字号放大时也不能裁掉内容。
///
/// 用户报过「标记错词」在真机上只显示了一半 —— 圆盘直径是按整块屏幕估的，
/// 舞台实际拿到的高度更少，Column 溢出后就把按钮切掉了。现在整排操作键
/// （重听 / 上一个 / 暂停 / 下一个 / 标记错词）都在表盘下面，一并钉住。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await Prefs.init();
    await loadDictionary();
    await loadLibrary();
  });

  /// 覆盖到最挤的组合：矮屏、带手势条的窄屏、以及放大到 1.3 倍的系统字号。
  const devices = <String, (Size, EdgeInsets)>{
    'iPhone SE 375x667': (Size(375, 667), EdgeInsets.only(top: 20)),
    'Android 360x740': (
      Size(360, 740),
      EdgeInsets.only(top: 24, bottom: 24),
    ),
    'iPhone 15 393x852': (
      Size(393, 852),
      EdgeInsets.only(top: 59, bottom: 34),
    ),
  };
  const textScales = <double>[1.0, 1.3];

  Future<void> pumpDictation(
    WidgetTester tester,
    Size size,
    EdgeInsets padding,
    double textScale,
  ) async {
    tester.view.physicalSize = size * 3;
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider(create: (_) => ThemeController()),
          ChangeNotifierProvider(create: (_) => OcrQuotaController()),
        ],
        child: MaterialApp(
          home: MediaQuery(
            data: MediaQueryData(
              size: size,
              padding: padding,
              viewPadding: padding,
              textScaler: TextScaler.linear(textScale),
            ),
            child: const DictationScreen(
              words: ['apple | n. | 苹果', 'banana'],
              intervalSec: 7,
              autoNext: true,
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
  }

  devices.forEach((name, config) {
    for (final textScale in textScales) {
      testWidgets('$name 字号 ${textScale}x：表盘下的操作行完整可见', (tester) async {
        final (size, padding) = config;
        await pumpDictation(tester, size, padding, textScale);

        // 放大字号时表盘里的假字体（widget test 用的等宽方块字）会比真机宽
        // 很多，那种溢出不算数；默认字号下则一个溢出都不该有。
        final overflow = tester.takeException();
        if (textScale == 1.0) {
          expect(overflow, isNull, reason: '$name 有溢出');
        }

        // 舞台会裁掉超出的部分，所以操作行每一格都得整块落在舞台可视区里。
        final stage = tester.getRect(
          find
              .ancestor(
                of: find.text('标记错词'),
                matching: find.byType(SingleChildScrollView),
              )
              .first,
        );

        for (final label in ['重听', '上一个', '暂停', '下一个', '标记错词']) {
          final text = tester.getRect(find.text(label));
          expect(
            text.bottom,
            lessThanOrEqualTo(stage.bottom),
            reason: '「$label」底部超出舞台 ${text.bottom - stage.bottom}px，会被裁掉',
          );
          expect(text.left, greaterThanOrEqualTo(stage.left));
          expect(text.right, lessThanOrEqualTo(stage.right));
        }

        // 操作行在表盘下面，而且主按钮和表盘同一条中轴。
        final dial = tester.getRect(find.byType(CountdownRing));
        final play = tester.getRect(
          find.widgetWithIcon(AppIconButton, AppIcons.pause),
        );
        expect(dial.top, greaterThanOrEqualTo(stage.top));
        expect(play.top, greaterThanOrEqualTo(dial.bottom));
        expect(play.center.dx, moreOrLessEquals(dial.center.dx, epsilon: 1));
      });
    }
  });
}

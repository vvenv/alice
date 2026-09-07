import 'package:alice_dictation/screens/dictation_screen.dart';
import 'package:alice_dictation/services/dictionary.dart';
import 'package:alice_dictation/services/library_data.dart';
import 'package:alice_dictation/services/keep_awake.dart';
import 'package:alice_dictation/services/prefs.dart';
import 'package:alice_dictation/state/ocr_quota_controller.dart';
import 'package:alice_dictation/theme/theme_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'package:wakelock_plus_platform_interface/wakelock_plus_platform_interface.dart';

/// 听写过程中的屏幕常亮。
///
/// 听写的标准姿势是手机放桌上、人在纸上写字。系统息屏通常 30 秒，一轮下来
/// 没人会去碰屏幕 —— 屏幕黑掉之后倒计时看不见、「标记错词」点不到。
/// 这条链路在真机之外没别的地方能验，所以把平台实现换成假的来断言调用。
class FakeWakelock extends WakelockPlusPlatformInterface {
  final List<bool> toggles = [];
  bool _enabled = false;

  @override
  Future<void> toggle({required bool enable}) async {
    toggles.add(enable);
    _enabled = enable;
  }

  @override
  Future<bool> get enabled async => _enabled;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FakeWakelock fake;

  setUpAll(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await Prefs.init();
    await loadDictionary();
    await loadLibrary();
  });

  setUp(() {
    fake = FakeWakelock();
    WakelockPlusPlatformInterface.instance = fake;
    // WakelockPlus 把平台实现抓在一个只惰性初始化一次的顶层变量里，
    // 只改 instance 的话第二个用例还在对着上一个 fake 说话。
    // wakelockPlusPlatformInstance 就是插件为此留的测试钩子。
    wakelockPlusPlatformInstance = fake;
  });

  Widget wrap(Widget child) => MultiProvider(
        providers: [
          ChangeNotifierProvider(create: (_) => ThemeController()),
          ChangeNotifierProvider(create: (_) => OcrQuotaController()),
        ],
        child: MaterialApp(home: child),
      );

  testWidgets('进听写页开始播放后打开屏幕常亮', (tester) async {
    await tester.pumpWidget(
      wrap(const DictationScreen(
        words: ['apple', 'banana'],
        intervalSec: 7,
        autoNext: true,
      )),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(fake.toggles, contains(true));
    expect(await fake.enabled, isTrue);
  });

  testWidgets('离开听写页一定放开屏幕常亮', (tester) async {
    await tester.pumpWidget(
      wrap(const DictationScreen(
        words: ['apple', 'banana'],
        intervalSec: 7,
        autoNext: true,
      )),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(await fake.enabled, isTrue);

    // 换掉整棵树 = 听写页 dispose。
    await tester.pumpWidget(wrap(const SizedBox()));
    await tester.pump();

    expect(fake.toggles.last, isFalse);
    expect(await fake.enabled, isFalse);
  });

  test('KeepAwake 的开关直接映射到平台的 toggle', () async {
    await KeepAwake.enable();
    await KeepAwake.disable();
    expect(fake.toggles, [true, false]);
  });
}

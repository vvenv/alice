import 'package:alice_dictation/services/prefs.dart';
import 'package:alice_dictation/services/tts.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 与 flutter_tts 原生插件之间的约定。
///
/// 真机上出过的问题：进听写后一个词都不响，暂停再继续就好了。原因在插件里 ——
/// Android 的 TextToSpeech 是异步初始化的，flutter_tts 把 onInit 之前收到的调用
/// 排进 pendingMethodCalls，然后在 onInit 里**先重放队列、再挂**
/// setOnUtteranceProgressListener。落在这个窗口里的 speak 拿不到任何进度回调，
/// onDone 不来，插件的 `speaking` 标志就一直举着；而它对之后每一次 speak 都直接
/// `result.success(0)` 丢弃。只有 stop() 能把标志放下来 —— 那正是「暂停」做的事。
///
/// 这些用例盯的是我们这一侧的两条防线：启动时把引擎排空，以及一次被丢弃的朗读
/// 必须复位引擎、并如实报失败。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('flutter_tts');

  /// 按发生顺序记下发给插件的方法名。
  final calls = <String>[];

  /// speak 的返回值：1 = 读完了，0 = 插件把这一遍丢了。
  var speakResult = 1;

  setUpAll(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await Prefs.init();

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      calls.add(call.method);
      if (call.method == 'speak') return speakResult;
      return 1;
    });
  });

  tearDownAll(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  // 用例之间共用同一个引擎实例（模块级缓存），所以顺序是有意义的：
  // 先预热，再朗读 —— 与真实启动流程一致。

  test('预热在第一次朗读之前把引擎排空，而且自己不发 speak', () async {
    await warmUpTts();

    expect(calls, isNotEmpty, reason: '预热应该真的和插件说上话');
    expect(calls, isNot(contains('speak')),
        reason: '预热只负责把 pendingMethodCalls 排空，不该自己读出声');
    expect(calls.first, 'awaitSpeakCompletion',
        reason: '第一个调用用来等 onInit 跑完；它返回时进度监听器才挂上');
    expect(calls.indexOf('setLanguage'), greaterThan(0),
        reason: 'onInit 重放完队列后会把语言重置成设备默认音，'
            'setLanguage 必须排在预热之后才不会被盖掉');
    expect(
      calls.indexOf('setSpeechRate'),
      greaterThan(calls.indexOf('setLanguage')),
      reason: 'Android 默认语速偏快，预热就要把用户语速写进引擎，'
          '否则第一遍 TTS 会明显快于第二遍',
    );
  });

  test('preparePlayback 只激活会话和引擎，自己不发 speak', () async {
    calls.clear();
    await preparePlayback();
    expect(calls, isNot(contains('speak')),
        reason: '点「开始听写」时的准备不能自己读出声');
  });

  test('引擎丢掉这次朗读时，会 stop() 复位并按失败返回', () async {
    speakResult = 0;
    calls.clear();

    final ok = await speakWord('apple');

    expect(ok, isFalse, reason: '没读出声就不能报成功，否则整段听写会一路静音');
    final spoke = calls.indexOf('speak');
    expect(spoke, greaterThanOrEqualTo(0));
    expect(calls.skip(spoke).contains('stop'), isTrue,
        reason: '插件的 speaking 标志只有 stop() 能放下来；'
            '不复位的话后面每一个词都会被静默丢弃');
  });

  test('正常读完时不会多余地复位引擎', () async {
    speakResult = 1;
    calls.clear();

    final ok = await speakWord('apple');

    expect(ok, isTrue);
    final spoke = calls.indexOf('speak');
    expect(spoke, greaterThanOrEqualTo(0));
    expect(calls.skip(spoke).contains('stop'), isFalse,
        reason: '读完之后再 stop() 会掐掉下一遍的开头');
  });
}

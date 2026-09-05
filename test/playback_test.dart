import 'package:alice_dictation/services/library_data.dart';
import 'package:alice_dictation/services/prefs.dart';
import 'package:alice_dictation/state/playback_controller.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 调度器本身的行为。
///
/// 测试环境里没有 flutter_tts / just_audio 的平台实现，`speakWord` 会一路
/// 抛 MissingPluginException 再被兜住、返回 false —— 也就是说这里验的是
/// 「朗读全部失败时调度器还走不走得动」，而不是有没有声音。用户报的
/// 「第一个词不自动播放」如果出在调度器上，这里就会红。
void main() {
  WidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await Prefs.init();
    await loadLibrary();
  });

  test('startDictation 立刻进入 playing 并停在第 0 个词', () async {
    final c = PlaybackController(intervalSec: 0.5, autoNext: true);
    addTearDown(c.dispose);

    c.startDictation(['apple', 'banana']);

    expect(c.playState, PlayState.playing);
    expect(c.currentIndex, 0);
    expect(c.isActive, isTrue);
  });

  test('空词表不会进入 playing', () async {
    final c = PlaybackController(intervalSec: 0.5, autoNext: true);
    addTearDown(c.dispose);

    c.startDictation(const []);

    expect(c.playState, PlayState.idle);
  });

  test('调度器会自己跑起来：第 0 个词在几拍之内被处理掉', () async {
    final c = PlaybackController(intervalSec: 0.5, autoNext: true);
    addTearDown(c.dispose);

    c.startDictation(['apple', 'banana']);
    expect(c.currentIndex, 0);

    // 朗读在测试环境里必然失败，调度器应当继续推进而不是卡死。
    // 给它足够的时间走完 speak1 → speak2 → interval。
    for (var i = 0; i < 40; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 50));
      if (c.currentIndex > 0) break;
    }

    expect(
      c.currentIndex,
      greaterThan(0),
      reason: '调度器卡在第 0 个词上了 —— 它没有推进到下一个词',
    );
  });
}

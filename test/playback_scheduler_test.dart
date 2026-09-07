import 'package:alice_dictation/state/playback_controller.dart';
import 'package:alice_dictation/state/speech_port.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

/// 听写调度器的时序。
///
/// 用假的 [SpeechPort] 把音频插件换掉，于是「读了几遍、什么顺序、什么语言、
/// stop 有没有排在 speak 前面」全都可断言 —— 这些在真机上只能靠耳朵听，
/// 而这块恰恰是这个项目里出 bug 最多的地方。
///
/// 每个用例对应一个真实发生过或差点发生的问题，改坏了会立刻红。

/// 记录调用顺序的假朗读端口。
class FakeSpeech extends SpeechPort {
  FakeSpeech({
    this.readTranslation = false,
    this.speakSucceeds = true,
    this.speakDuration = const Duration(milliseconds: 10),
    this.stopDuration = Duration.zero,
  });

  /// 「朗读中文释义」开关。
  bool readTranslation;

  /// speak 是否算读完（false 模拟 TTS 故障）。
  bool speakSucceeds;

  /// 一次朗读耗时。
  Duration speakDuration;

  /// 一次 stop 耗时 —— 调大用来暴露 stop/speak 的竞态。
  Duration stopDuration;

  /// 按发生顺序记下的事件：`stop`、`prepare`、`speak:<text>@<lang>`、`prefetch:<text>`。
  final List<String> events = [];

  @override
  Future<void> prepare() async {
    events.add('prepare');
  }

  List<String> get spoken => events
      .where((e) => e.startsWith('speak:'))
      .map((e) => e.substring('speak:'.length))
      .toList();

  @override
  Future<void> stop() async {
    events.add('stop');
    if (stopDuration > Duration.zero) await Future<void>.delayed(stopDuration);
    events.add('stop:done');
  }

  @override
  Future<bool> speak(String text, {String? lang}) async {
    events.add('speak:$text@${lang ?? 'auto'}');
    await Future<void>.delayed(speakDuration);
    return speakSucceeds;
  }

  @override
  Future<void> prefetch(String text) async {
    events.add('prefetch:$text');
  }

  @override
  Future<bool> loadReadTranslation() async => readTranslation;

  @override
  bool get readTranslationEnabled => readTranslation;
}

void main() {
  WidgetsFlutterBinding.ensureInitialized();

  /// 一直抽 event loop，直到 [predicate] 成立或超时。
  Future<void> until(
    bool Function() predicate, {
    Duration timeout = const Duration(seconds: 5),
  }) async {
    final deadline = DateTime.now().add(timeout);
    while (!predicate()) {
      if (DateTime.now().isAfter(deadline)) return;
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
  }

  PlaybackController make(
    FakeSpeech speech, {
    double intervalSec = 0.05,
    bool autoNext = true,
  }) =>
      PlaybackController(
        intervalSec: intervalSec,
        autoNext: autoNext,
        speech: speech,
      );

  test('一个词读两遍', () async {
    final speech = FakeSpeech();
    final c = make(speech, autoNext: false);
    addTearDown(c.dispose);

    c.startDictation(['apple']);
    await until(() => speech.spoken.length >= 2);

    expect(speech.spoken, ['apple@auto', 'apple@auto']);
  });

  test('开了「朗读中文释义」：单词 → 释义 → 单词，释义走中文', () async {
    final speech = FakeSpeech(readTranslation: true);
    final c = make(speech, autoNext: false);
    addTearDown(c.dispose);

    c.startDictation(['apple | n. | 苹果']);
    await until(() => speech.spoken.length >= 3);

    expect(speech.spoken, [
      'apple | n. | 苹果@auto',
      '苹果@zh-CN',
      'apple | n. | 苹果@auto',
    ]);
  });

  test('关掉开关时不读释义', () async {
    final speech = FakeSpeech();
    final c = make(speech, autoNext: false);
    addTearDown(c.dispose);

    c.startDictation(['apple | n. | 苹果']);
    await until(() => speech.spoken.length >= 2);
    await Future<void>.delayed(const Duration(milliseconds: 200));

    expect(speech.spoken.where((e) => e.contains('zh-CN')), isEmpty);
    expect(speech.spoken, hasLength(2));
  });

  test('开了开关但这个词没有释义时，仍然只读两遍', () async {
    final speech = FakeSpeech(readTranslation: true);
    final c = make(speech, autoNext: false);
    addTearDown(c.dispose);

    c.startDictation(['apple']);
    await until(() => speech.spoken.length >= 2);
    await Future<void>.delayed(const Duration(milliseconds: 200));

    expect(speech.spoken, hasLength(2));
  });

  // 0.7.1 修过：stopSpeech 没被 await，tts.stop() 落在 speak() 之后，
  // 把第一个词掐掉。这里把 stop 拖慢，顺序错了就会红。
  test('stop 必须在第一次 speak 之前完成', () async {
    final speech = FakeSpeech(stopDuration: const Duration(milliseconds: 80));
    final c = make(speech, autoNext: false);
    addTearDown(c.dispose);

    c.startDictation(['apple']);
    await until(() => speech.spoken.isNotEmpty);

    final stopDone = speech.events.indexOf('stop:done');
    final firstSpeak = speech.events.indexWhere((e) => e.startsWith('speak:'));
    expect(stopDone, isNonNegative);
    expect(
      stopDone,
      lessThan(firstSpeak),
      reason: 'stop 还没做完就开口了 —— 第一个词会被掐掉。事件序列：'
          '${speech.events}',
    );
    final prepared = speech.events.indexOf('prepare');
    expect(prepared, greaterThan(stopDone));
    expect(
      prepared,
      lessThan(firstSpeak),
      reason: '开口前必须先激活音频会话，否则进页第一句会静音',
    );
  });

  test('朗读失败不会卡住，词表照样走完', () async {
    final speech = FakeSpeech(speakSucceeds: false);
    final c = make(speech);
    addTearDown(c.dispose);

    c.startDictation(['apple', 'banana']);
    await until(() => c.playState == PlayState.idle);

    expect(c.playState, PlayState.idle);
  });

  test('autoNext 关掉时，第二遍读完就停住不前进', () async {
    final speech = FakeSpeech();
    final c = make(speech, autoNext: false);
    addTearDown(c.dispose);

    c.startDictation(['apple', 'banana']);
    await until(() => speech.spoken.length >= 2);
    await Future<void>.delayed(const Duration(milliseconds: 300));

    expect(c.currentIndex, 0);
    expect(speech.spoken.where((e) => e.startsWith('banana')), isEmpty);
  });

  test('autoNext 打开时会自己走到下一个词，读完进 idle', () async {
    final speech = FakeSpeech();
    final c = make(speech);
    addTearDown(c.dispose);

    c.startDictation(['apple', 'banana']);
    await until(() => c.playState == PlayState.idle);

    expect(speech.spoken.where((e) => e.startsWith('banana')), hasLength(2));
    expect(c.playState, PlayState.idle);
  });

  test('跳到下一个词会打断当前朗读', () async {
    final speech = FakeSpeech(speakDuration: const Duration(seconds: 5));
    final c = make(speech);
    addTearDown(c.dispose);

    c.startDictation(['apple', 'banana']);
    await until(() => speech.spoken.isNotEmpty);

    c.skipToNextWord();
    await until(() => c.currentIndex == 1);

    expect(c.currentIndex, 1);
    expect(c.playState, PlayState.playing);
  });

  // 「再读一遍」是听写里最高频的动作，以前没有入口，只能靠「暂停 → 继续」
  // 凑（恢复播放本来就是从 speak1 重来）。现在是明确的一档操作，别再退化成
  // 「跳到下一个词」或者「什么都没发生」。
  test('重听会重新从第一遍开始读当前词，且不改变词序', () async {
    final speech = FakeSpeech(speakDuration: const Duration(seconds: 5));
    final c = make(speech);
    addTearDown(c.dispose);

    c.startDictation(['apple', 'banana']);
    await until(() => speech.spoken.isNotEmpty);
    expect(c.currentIndex, 0);

    c.replayCurrentWord();
    await until(() => speech.spoken.length >= 2);

    expect(c.currentIndex, 0, reason: '重听不该走到下一个词');
    expect(speech.spoken, ['apple@auto', 'apple@auto']);
    expect(c.playState, PlayState.playing);
  });

  test('暂停中重听会恢复播放', () async {
    final speech = FakeSpeech(speakDuration: const Duration(seconds: 5));
    final c = make(speech);
    addTearDown(c.dispose);

    c.startDictation(['apple', 'banana']);
    await until(() => speech.spoken.isNotEmpty);
    c.pauseDictation();
    expect(c.playState, PlayState.paused);

    c.replayCurrentWord();
    await until(() => speech.spoken.length >= 2);

    expect(c.playState, PlayState.playing);
    expect(c.currentIndex, 0);
  });

  test('听写结束后重听不做任何事', () async {
    final speech = FakeSpeech();
    final c = make(speech);
    addTearDown(c.dispose);

    c.startDictation(['apple']);
    await until(() => c.playState == PlayState.idle);
    final before = speech.spoken.length;

    c.replayCurrentWord();
    await Future<void>.delayed(const Duration(milliseconds: 150));

    expect(c.playState, PlayState.idle);
    expect(speech.spoken, hasLength(before));
  });

  test('暂停会停掉朗读并保持在原词', () async {
    final speech = FakeSpeech(speakDuration: const Duration(seconds: 5));
    final c = make(speech);
    addTearDown(c.dispose);

    c.startDictation(['apple', 'banana']);
    await until(() => speech.spoken.isNotEmpty);

    c.pauseDictation();

    expect(c.playState, PlayState.paused);
    expect(c.currentIndex, 0);
  });

  // 0.7.0 修过：ticker 读的是启动时捕获的 deadline，滑块写进去的新值
  // 50ms 后就被覆盖回去，「实时生效」其实什么也没做。
  test('间隔滑块在倒计时中途生效', () async {
    final speech = FakeSpeech();
    final c = make(speech, intervalSec: 10);
    addTearDown(c.dispose);

    c.startDictation(['apple', 'banana']);
    // 等两遍读完、进入 interval 倒计时
    await until(() => c.remainingMs != null && c.remainingMs! > 5000);
    final before = c.remainingMs!;

    c.setIntervalSec(1);

    // ★ 必须等过几拍 ticker（50ms 一拍）再断言。setIntervalSec 自己会先写一次
    //   _remainingMs，立刻读到的是那个值 —— bug 恰恰是「ticker 下一拍把它覆盖
    //   回旧的截止时刻」。不等就等于没测。
    await Future<void>.delayed(const Duration(milliseconds: 250));

    expect(
      c.remainingMs,
      isNotNull,
      reason: '倒计时不该在这时候结束',
    );
    expect(
      c.remainingMs,
      lessThan(2000),
      reason: '几拍之后剩余时间又回到了 ${c.remainingMs} ms（原本 $before ms）—— '
          'ticker 没有读新的截止时刻',
    );
  });

  test('停止听写后不再朗读', () async {
    final speech = FakeSpeech();
    final c = make(speech);
    addTearDown(c.dispose);

    c.startDictation(['apple', 'banana']);
    await until(() => speech.spoken.isNotEmpty);

    c.stopDictation();
    final countAtStop = speech.spoken.length;
    await Future<void>.delayed(const Duration(milliseconds: 300));

    expect(c.playState, PlayState.idle);
    expect(speech.spoken.length, countAtStop);
  });

  test('会为下一个词提前预取', () async {
    final speech = FakeSpeech();
    final c = make(speech, autoNext: false);
    addTearDown(c.dispose);

    c.startDictation(['apple', 'banana']);
    await until(() => speech.spoken.isNotEmpty);

    expect(speech.events, contains('prefetch:banana'));
  });

  test('开了释义朗读时，预取的是真正要读的那一段释义', () async {
    final speech = FakeSpeech(readTranslation: true);
    final c = make(speech, autoNext: false);
    addTearDown(c.dispose);

    c.startDictation(['apple | n. | 苹果']);
    await until(() => speech.spoken.isNotEmpty);

    expect(speech.events, contains('prefetch:苹果'));
  });
}

import 'dart:async';

import 'package:flutter/foundation.dart';

import '../services/abort.dart';
import '../services/dictation.dart';
import '../services/tts.dart' show kLangZh;
import 'speech_port.dart';

/// 听写播放调度器。对应 Expo 版 src/hooks/usePlayback.ts。
///
/// 一个单词的生命周期：
/// speak1 →（读中文释义开着时）speakMeaning → speak2 → interval → 下一词，
/// 每两遍朗读之间隔 700ms。
/// `gen` 是「代」计数：任何打断（暂停/停止/跳词/重开）都会 +1，
/// 让还在飞的异步回合自行作废，避免旧回合把状态写回来。
enum PlayState { idle, playing, paused }

/// 一个词的朗读阶段：单词 → 中文释义 → 单词 → 间隔。
///
/// 释义那一遍只在「读中文释义」开着且该词真有可读释义时才进；关掉时
/// speak1 直接接 speak2，与以前一致。
enum _WordPhase { speak1, speakMeaning, speak2, interval }

const int _repeatGapMs = 700;

class _Scheduler {
  _Scheduler({
    required this.gen,
    required this.index,
    required this.phase,
  });

  final int gen;
  int index;
  _WordPhase phase;

  /// 本词是否正在朗读中 —— 防止调度器重入。
  bool speaking = false;
}

class PlaybackController extends ChangeNotifier {
  PlaybackController({
    required double intervalSec,
    required bool autoNext,
    SpeechPort? speech,
  })  : _intervalSec = intervalSec,
        _autoNext = autoNext,
        _speech = speech ?? const SystemSpeechPort();

  /// 朗读能力。测试注入假实现，见 speech_port.dart。
  final SpeechPort _speech;

  PlayState _playState = PlayState.idle;
  List<String> _wordList = <String>[];
  int _currentIndex = 0;
  int? _remainingMs;

  /// 当前倒计时的截止时刻（epoch 毫秒）。见 [_waitMs]。
  int? _deadlineMs;

  /// 正在进行的 [SpeechPort.stop]。
  ///
  /// 停止是异步的（要 await 播放器 pause 和 TTS stop），而
  /// startDictation / 跳词 / 恢复播放都是「先停、紧接着开下一段朗读」。
  /// 不等它做完就 speak，`tts.stop()` 会落在 `tts.speak()` 之后，
  /// 把刚开始的那一遍掐掉 —— 表现就是「进听写第一个词不发声」。
  /// 调度器在朗读前 await 这个 future。
  Future<void>? _stopping;

  double _intervalSec;
  bool _autoNext;

  int _playGen = 0;
  _Scheduler? _scheduler;
  AbortSignal? _cycleAbort;
  Timer? _countdownTimer;
  bool _disposed = false;

  PlayState get playState => _playState;
  List<String> get wordList => List.unmodifiable(_wordList);
  int get currentIndex => _currentIndex;
  int? get remainingMs => _remainingMs;
  double get intervalSec => _intervalSec;
  bool get autoNext => _autoNext;

  bool get isActive =>
      _playState == PlayState.playing || _playState == PlayState.paused;
  bool get isDictationPlaying => _playState == PlayState.playing;

  void _notify() {
    if (_disposed) return;
    notifyListeners();
  }

  void _updatePlayState(PlayState state) {
    _playState = state;
    _notify();
  }

  void _clearCountdown() {
    _countdownTimer?.cancel();
    _countdownTimer = null;
    _deadlineMs = null;
    if (_remainingMs != null) {
      _remainingMs = null;
      _notify();
    }
  }

  void _abortCycle() {
    _cycleAbort?.abort();
    _cycleAbort = null;
  }

  /// 这一回合是否已经作废。
  bool _isCancelled(int gen) {
    return _playState != PlayState.playing ||
        _playGen != gen ||
        _scheduler == null ||
        _scheduler!.gen != gen;
  }

  void _finishDictation() {
    _abortCycle();
    _scheduler = null;
    _clearCountdown();
    _stopping = _speech.stop();
    _updatePlayState(PlayState.idle);
  }

  /// 等待 ms 毫秒，期间每 50ms 刷新一次剩余时间。被打断返回 false。
  ///
  /// 截止时刻放在字段里而不是闭包变量里：间隔滑块要在倒计时中途改写它
  /// （见 [setIntervalSec]）。以前 ticker 读的是启动时捕获的那个局部量，
  /// 滑块写进去的新值 50ms 后就被覆盖回去 —— 「实时生效」其实什么也没做。
  Future<bool> _waitMs(int ms, AbortSignal signal) {
    if (ms <= 0) return Future.value(true);

    _deadlineMs = DateTime.now().millisecondsSinceEpoch + ms;
    _remainingMs = ms;
    _notify();

    final completer = Completer<bool>();
    if (signal.aborted) {
      return Future.value(false);
    }

    Timer? ticker;
    late void Function() onAbort;

    void finish(bool ok) {
      if (completer.isCompleted) return;
      ticker?.cancel();
      signal.removeListener(onAbort);
      completer.complete(ok);
    }

    onAbort = () => finish(false);
    signal.addListener(onAbort);

    ticker = Timer.periodic(const Duration(milliseconds: 50), (_) {
      if (signal.aborted) {
        finish(false);
        return;
      }
      // 每一拍都重新读字段，才能吃到滑块中途改写的新截止时刻。
      final current = _deadlineMs;
      if (current == null) {
        finish(false);
        return;
      }
      final left = current - DateTime.now().millisecondsSinceEpoch;
      _remainingMs = left > 0 ? left : 0;
      _notify();
      if (left <= 0) finish(true);
    });

    _countdownTimer = ticker;
    return completer.future;
  }

  Future<void> _runScheduler() async {
    final s = _scheduler;
    if (s == null) return;
    if (_playState != PlayState.playing) return;
    if (s.speaking) return;

    final list = _wordList;
    if (s.index >= list.length) {
      _finishDictation();
      return;
    }

    final gen = s.gen;
    final word = list[s.index];
    final signal = _cycleAbort;
    if (signal == null || signal.aborted) return;

    // 先等上一次 stopSpeech 落地，再开口 —— 见 [_stopping]。
    final stopping = _stopping;
    if (stopping != null) {
      await stopping;
      if (identical(_stopping, stopping)) _stopping = null;
      if (_isCancelled(gen)) return;
    }

    // 进页第一句如果会话还没 setActive，会整句静音；暂停再继续却正常。
    // 开口前再激活一次，把转场里丢掉的会话补回来。
    await _speech.prepare();
    if (_isCancelled(gen)) return;

    // 开关是异步从存储读的；等它一次，否则第一个词会按默认值（关）播。
    await _speech.loadReadTranslation();
    if (_isCancelled(gen)) return;

    if (s.phase == _WordPhase.speak1 || s.phase == _WordPhase.speak2) {
      s.speaking = true;
      final phase = s.phase;
      _currentIndex = s.index;
      _notify();

      // 听写顺序：单词 → 释义 → 单词。释义夹在两遍单词中间；
      // 空串表示这个词没有可朗读的释义。
      final meaningSpeech = _speech.readTranslationEnabled
          ? speakableMeaning(parseWordLine(word).meaning)
          : '';

      // 后台继续预取，但不阻塞播放。speakWord 只用已经缓存好的音频，
      // 否则立即回落到系统 TTS。
      unawaited(_speech.prefetch(word));
      if (s.index + 1 < list.length) {
        unawaited(_speech.prefetch(list[s.index + 1]));
      }
      // 预取的必须是 speakMeaning 真正要播的那个串，否则缓存对不上。
      if (meaningSpeech.isNotEmpty) {
        unawaited(_speech.prefetch(meaningSpeech));
      }

      final ok = await _speech.speak(word);
      if (_isCancelled(gen)) return;

      final cur = _scheduler;
      if (cur == null || cur.gen != gen) return;
      cur.speaking = false;

      // 朗读失败时不要死循环重试同一个词 —— 那会把一次 TTS 故障变成
      // 无限循环（以及一个卡死的 App）。跳过重复间隙，让调度器推进到
      // 下一阶段/下一个词。`speak2` 本身就充当了 `speak1` 的第二次尝试。
      if (!ok && phase == _WordPhase.speak1) {
        cur.phase = meaningSpeech.isNotEmpty
            ? _WordPhase.speakMeaning
            : _WordPhase.speak2;
        unawaited(_runScheduler());
        return;
      }

      if (phase == _WordPhase.speak1) {
        final gapOk = await _waitMs(_repeatGapMs, signal);
        if (_isCancelled(gen) || !gapOk) return;
        cur.phase = meaningSpeech.isNotEmpty
            ? _WordPhase.speakMeaning
            : _WordPhase.speak2;
        unawaited(_runScheduler());
        return;
      }

      if (!_autoNext) {
        _scheduler = null;
        return;
      }

      cur.phase = _WordPhase.interval;
      final intervalOk = await _waitMs((_intervalSec * 1000).round(), signal);
      if (_isCancelled(gen) || !intervalOk) return;

      _clearCountdown();
      final nextIndex = cur.index + 1;
      if (nextIndex >= list.length) {
        _finishDictation();
        return;
      }
      cur.index = nextIndex;
      cur.phase = _WordPhase.speak1;
      _currentIndex = nextIndex;
      _notify();
      unawaited(_runScheduler());
      return;
    }

    if (s.phase == _WordPhase.speakMeaning) {
      final speakable = speakableMeaning(parseWordLine(word).meaning);
      if (speakable.isNotEmpty) {
        s.speaking = true;
        await _speech.speak(speakable, lang: kLangZh);
        if (_isCancelled(gen)) return;
        final cur = _scheduler;
        if (cur == null || cur.gen != gen) return;
        cur.speaking = false;
      }

      // 释义听完，用第二遍单词收尾 —— 最后落在耳朵里的应该是单词本身
      // （单词 → 释义 → 单词）。
      final gapOk = await _waitMs(_repeatGapMs, signal);
      if (_isCancelled(gen) || !gapOk) return;
      s.phase = _WordPhase.speak2;
      unawaited(_runScheduler());
      return;
    }

    if (s.phase == _WordPhase.interval) {
      final intervalOk = await _waitMs((_intervalSec * 1000).round(), signal);
      if (_isCancelled(gen) || !intervalOk) return;

      _clearCountdown();
      final nextIndex = s.index + 1;
      if (nextIndex >= list.length) {
        _finishDictation();
        return;
      }
      s.index = nextIndex;
      s.phase = _WordPhase.speak1;
      _currentIndex = nextIndex;
      _notify();
      unawaited(_runScheduler());
    }
  }

  void _startFrom(int index, _WordPhase fromPhase) {
    if (index >= _wordList.length) {
      _finishDictation();
      return;
    }

    _abortCycle();
    _cycleAbort = AbortSignal();

    _scheduler = _Scheduler(gen: _playGen, index: index, phase: fromPhase);
    _currentIndex = index;
    _notify();
    unawaited(_runScheduler());
  }

  // --- 对外操作 -----------------------------------------------------------

  void startDictation(List<String> words) {
    _playGen += 1;
    _abortCycle();
    _scheduler = null;
    _clearCountdown();
    _stopping = _speech.stop();

    _wordList = List<String>.from(words);
    _currentIndex = 0;

    if (words.isEmpty) {
      _updatePlayState(PlayState.idle);
      return;
    }

    // 给前两个词最早的预取机会。播放本身不等待这两个请求。
    unawaited(_speech.prefetch(words[0]));
    if (words.length > 1) {
      unawaited(_speech.prefetch(words[1]));
    }

    _updatePlayState(PlayState.playing);
    _startFrom(0, _WordPhase.speak1);
  }

  void resumeDictation() {
    if (_playState == PlayState.playing) return;

    final index = _currentIndex;
    if (index >= _wordList.length) {
      _finishDictation();
      return;
    }

    _playGen += 1;
    _updatePlayState(PlayState.playing);
    _startFrom(index, _WordPhase.speak1);
  }

  void pauseDictation() {
    _playGen += 1;
    _updatePlayState(PlayState.paused);
    _scheduler = null;
    _abortCycle();
    _clearCountdown();
    _stopping = _speech.stop();
  }

  void stopDictation() {
    _playGen += 1;
    _scheduler = null;
    _abortCycle();
    _clearCountdown();
    _stopping = _speech.stop();
    _updatePlayState(PlayState.idle);
  }

  void skipToNextWord() {
    if (!isActive) return;

    final nextIndex = _currentIndex + 1;
    _playGen += 1;
    _abortCycle();
    _clearCountdown();
    _stopping = _speech.stop();

    _currentIndex = nextIndex;
    if (_playState == PlayState.paused) {
      _updatePlayState(PlayState.playing);
    }
    _startFrom(nextIndex, _WordPhase.speak1);
  }

  /// 从头再读一遍当前词（单词 →〔释义〕→ 单词）。
  ///
  /// 听写场景里「再读一遍」是最高频的诉求，以前只能靠「暂停 → 继续」凑
  /// —— 那条路能走通纯属实现细节（恢复播放本来就是从 speak1 重来），
  /// 没人猜得到。暂停中调用会顺手恢复播放，与跳词一致。
  void replayCurrentWord() {
    if (!isActive) return;

    final index = _currentIndex;
    if (index >= _wordList.length) return;

    _playGen += 1;
    _abortCycle();
    _clearCountdown();
    _stopping = _speech.stop();

    if (_playState == PlayState.paused) {
      _updatePlayState(PlayState.playing);
    }
    _startFrom(index, _WordPhase.speak1);
  }

  void goToPreviousWord() {
    if (!isActive) return;

    final prevIndex = _currentIndex - 1 < 0 ? 0 : _currentIndex - 1;
    _playGen += 1;
    _abortCycle();
    _clearCountdown();
    _stopping = _speech.stop();

    _currentIndex = prevIndex;
    if (_playState == PlayState.paused) {
      _updatePlayState(PlayState.playing);
    }
    _startFrom(prevIndex, _WordPhase.speak1);
  }

  // --- 间隔滑块的实时更新 --------------------------------------------------
  // 对应 RN 版监听 intervalSec 的 useEffect：播放中且正处于 interval 阶段时，
  // 用新的间隔重开倒计时。
  void setIntervalSec(double sec) {
    if (_intervalSec == sec) return;
    _intervalSec = sec;

    if (_playState == PlayState.playing &&
        _scheduler?.phase == _WordPhase.interval) {
      // 用新的间隔重开倒计时：改写截止时刻，ticker 下一拍就会读到。
      final deadline =
          DateTime.now().millisecondsSinceEpoch + (sec * 1000).round();
      _deadlineMs = deadline;
      final left = deadline - DateTime.now().millisecondsSinceEpoch;
      _remainingMs = left > 0 ? left : 0;
    }
    _notify();
  }

  // --- 自动播放开关的实时切换 ----------------------------------------------
  // 关掉自动播放后 speak2 结束时调度器会被清空，而 playState 仍是 playing。
  // 重新打开必须把 interval → 下一词 的循环接回去；播放中关掉则应取消
  // 当前倒计时并停在原地。
  void setAutoNext(bool value) {
    if (_autoNext == value) return;
    _autoNext = value;
    _notify();

    if (_playState != PlayState.playing) return;

    if (!value) {
      if (_scheduler?.phase == _WordPhase.interval) {
        _abortCycle();
        _clearCountdown();
        _scheduler = null;
      }
      return;
    }

    if (_scheduler == null) {
      final index = _currentIndex;
      if (index >= _wordList.length) return;
      _startFrom(index, _WordPhase.interval);
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _abortCycle();
    _scheduler = null;
    _countdownTimer?.cancel();
    _countdownTimer = null;
    _stopping = _speech.stop();
    super.dispose();
  }
}

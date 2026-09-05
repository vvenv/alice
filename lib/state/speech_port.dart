import '../services/tts.dart' as tts;

/// 听写调度器用到的全部朗读能力。
///
/// [PlaybackController] 原先直接调 `services/tts.dart` 的顶层函数。那些函数
/// 背后是 flutter_tts / just_audio 的平台插件，测试环境里没有实现，于是调度器
/// —— 这个项目里出 bug 最多的地方 —— 实际上没法测：只能验「朗读全失败时还走
/// 不走得动」，验不了时序。
///
/// 把这几个调用收进一个接口，真实实现转发给 tts.dart，测试注入假实现，就能
/// 确定性地断言「读了几遍」「什么语言」「stop 有没有排在 speak 前面」。
abstract class SpeechPort {
  const SpeechPort();

  /// 停掉当前朗读。调度器会 await 它再开下一段 —— 顺序反了会掐掉开头。
  Future<void> stop();

  /// 朗读一段文本，返回是否正常读完。[lang] 为空时按内容判定。
  Future<bool> speak(String text, {String? lang});

  /// 后台预取音频，不阻塞播放。
  Future<void> prefetch(String text);

  /// 读一次「朗读中文释义」开关。
  Future<bool> loadReadTranslation();

  /// 同步读开关，供热路径使用。
  bool get readTranslationEnabled;
}

/// 走真实 TTS 的实现。
class SystemSpeechPort extends SpeechPort {
  const SystemSpeechPort();

  @override
  Future<void> stop() => tts.stopSpeech();

  @override
  Future<bool> speak(String text, {String? lang}) =>
      tts.speakWord(text, lang: lang);

  @override
  Future<void> prefetch(String text) async {
    // 预取失败无所谓：播放时会回落到系统 TTS。
    try {
      await tts.prefetchWordAudio(text);
    } catch (_) {
      // 忽略
    }
  }

  @override
  Future<bool> loadReadTranslation() => tts.loadReadTranslation();

  @override
  bool get readTranslationEnabled => tts.isReadTranslationEnabled();
}

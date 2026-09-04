import 'dart:async';

import 'package:audio_session/audio_session.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:just_audio/just_audio.dart';

import 'abort.dart';
import 'dictation.dart';
import 'logger.dart';
import 'storage.dart';
import 'tts_cache.dart';

/// 单词发音。优先播放已缓存的有道词典音频，否则回落到系统 TTS。
///
/// 对应 RN 版 src/lib/tts.ts：
/// - expo-speech       → flutter_tts
/// - expo-audio        → just_audio (+ audio_session 管音频会话)
/// - expo-file-system  → tts_cache.dart（按平台条件导入，Web 上是空实现）
const _log = Logger('TTS');

const TtsCacheApi _cache = TtsCache();

double _currentSpeechRate = kDefaultSpeechRate;

AbortSignal? _currentAbort;
AudioPlayer? _wordPlayer;
FlutterTts? _tts;
Future<void>? _audioSessionReady;
final Map<String, Future<String?>> _pendingDownloads = {};

// ---------------------------------------------------------------------------
// 音频会话 / 播放器 / TTS 引擎
// ---------------------------------------------------------------------------

/// 配置音频会话。对应 RN 版的 setAudioModeAsync：
/// 静音键按下时也要出声、可后台播放、与其他音频不混音。
Future<void> _ensureAudioSession() {
  return _audioSessionReady ??= () async {
    try {
      final session = await AudioSession.instance;
      await session.configure(
        const AudioSessionConfiguration(
          avAudioSessionCategory: AVAudioSessionCategory.playback,
          avAudioSessionCategoryOptions:
              AVAudioSessionCategoryOptions.duckOthers,
          avAudioSessionMode: AVAudioSessionMode.spokenAudio,
          androidAudioAttributes: AndroidAudioAttributes(
            contentType: AndroidAudioContentType.speech,
            usage: AndroidAudioUsage.media,
          ),
          androidAudioFocusGainType:
              AndroidAudioFocusGainType.gainTransientMayDuck,
          androidWillPauseWhenDucked: false,
        ),
      );
      await session.setActive(true);
    } catch (e) {
      _log.warn('配置音频会话失败: $e');
    }
  }();
}

AudioPlayer _getPlayer() => _wordPlayer ??= AudioPlayer();

Future<FlutterTts> _getTts() async {
  final existing = _tts;
  if (existing != null) return existing;

  final tts = FlutterTts();
  await tts.setLanguage('en-US');
  // 让 speak() 等到朗读结束才返回 —— 调度器依赖这个语义。
  await tts.awaitSpeakCompletion(true);
  _tts = tts;
  return tts;
}

// ---------------------------------------------------------------------------
// 有道下载 + 本地缓存
// ---------------------------------------------------------------------------

String _cacheKeyFor(String text) => text.trim().toLowerCase();

/// 预取单词音频（不阻塞播放）。返回本地文件路径或 null。
Future<String?> prefetchWordAudio(String word) async {
  final text = speakTextFromEntry(word);
  if (text.isEmpty || !_cache.canUseDiskCache) return null;

  final ready = await _cache.readyPath(text);
  if (ready != null) return ready;

  final key = _cacheKeyFor(text);
  final pending = _pendingDownloads[key];
  if (pending != null) return pending;

  final download =
      _cache.download(text, AbortSignal()).catchError((Object _) => null);
  _pendingDownloads[key] = download;

  try {
    return await download;
  } finally {
    if (identical(_pendingDownloads[key], download)) {
      _pendingDownloads.remove(key);
    }
  }
}

/// 清空发音缓存，返回删除的文件数。
Future<int> clearTtsCache() => _cache.clear();

// ---------------------------------------------------------------------------
// 播放
// ---------------------------------------------------------------------------

void setSpeechRate(double rate) {
  _currentSpeechRate = rate;
}

Future<void> stopSpeech() async {
  _currentAbort?.abort();
  _currentAbort = null;
  try {
    await _wordPlayer?.pause();
  } catch (_) {}
  try {
    await _tts?.stop();
  } catch (_) {}
}

/// 播放一个本地音频文件，返回是否播放完成。
Future<bool> _playAudioFile(String path, AbortSignal signal) async {
  await _ensureAudioSession();
  if (signal.aborted) return false;

  try {
    await _tts?.stop();
  } catch (_) {}

  final player = _getPlayer();
  try {
    await player.pause();
  } catch (_) {}

  final completer = Completer<bool>();
  var settled = false;
  var seenPlaying = false;

  Timer? hardCap;
  Timer? durationCap;
  StreamSubscription<PlayerState>? stateSub;
  late void Function() onAbort;

  void finish(bool ok) {
    if (settled) return;
    settled = true;
    hardCap?.cancel();
    durationCap?.cancel();
    stateSub?.cancel();
    signal.removeListener(onAbort);
    completer.complete(ok);
  }

  onAbort = () {
    try {
      player.pause();
    } catch (_) {}
    finish(false);
  };
  signal.addListener(onAbort);

  // 兜底：15 秒还没结束就按「是否真的播过」判定。
  hardCap = Timer(const Duration(seconds: 15), () => finish(seenPlaying));

  stateSub = player.playerStateStream.listen((state) {
    if (signal.aborted) {
      finish(false);
      return;
    }
    if (state.playing) {
      seenPlaying = true;
      final duration = player.duration;
      if (durationCap == null && duration != null && duration > Duration.zero) {
        durationCap = Timer(
          duration + const Duration(milliseconds: 400),
          () => finish(true),
        );
      }
    }
    if (state.processingState == ProcessingState.completed) {
      finish(true);
    }
  });

  try {
    await player.setLoopMode(LoopMode.off);
    await player.setVolume(1);
    await player.setFilePath(path);
    if (signal.aborted) {
      finish(false);
    } else {
      player.play();
    }
  } catch (e) {
    _log.warn('音频播放失败: $e');
    finish(false);
  }

  return completer.future;
}

/// 用系统 TTS 朗读，返回是否正常读完。
Future<bool> _speakWithSystemTts(String text, AbortSignal signal) async {
  await _ensureAudioSession();
  final tts = await _getTts();
  await tts.stop();
  if (signal.aborted) return false;

  final completer = Completer<bool>();
  var settled = false;
  late void Function() onAbort;

  // 兜底超时：与 RN 版一致，按文本长度估算上限。
  final maxMs = (text.length * 250).clamp(4000, 60000);
  Timer? timer;

  void finish(bool ok) {
    if (settled) return;
    settled = true;
    timer?.cancel();
    signal.removeListener(onAbort);
    completer.complete(ok);
  }

  onAbort = () {
    tts.stop();
    finish(false);
  };
  signal.addListener(onAbort);
  timer = Timer(Duration(milliseconds: maxMs), () => finish(true));

  try {
    await tts.setSpeechRate(_normalizedRate(_currentSpeechRate));
    // awaitSpeakCompletion(true) 让这里等到读完才返回。
    await tts.speak(text);
    finish(!signal.aborted);
  } catch (_) {
    finish(false);
  }

  return completer.future;
}

/// expo-speech 的 rate 是「1.0 = 正常语速」；flutter_tts 各平台的取值区间不同。
/// 这里把 0.5–1.5 的用户区间映射到各平台的实际取值。
///
/// 用 defaultTargetPlatform 而不是 dart:io 的 Platform —— 后者会让 web 构建失败。
double _normalizedRate(double rate) {
  if (kIsWeb) return rate;
  switch (defaultTargetPlatform) {
    case TargetPlatform.iOS:
    case TargetPlatform.macOS:
      // AVSpeechUtteranceDefaultSpeechRate ≈ 0.5
      return (rate * 0.5).clamp(0.0, 1.0);
    case TargetPlatform.android:
    case TargetPlatform.fuchsia:
    case TargetPlatform.linux:
    case TargetPlatform.windows:
      // Android: TextToSpeech.setSpeechRate，1.0 为正常语速
      return rate.clamp(0.1, 3.0);
  }
}

/// 只在已缓存时使用有道免费发音；播放开始时绝不等待下载，
/// 直接回落到系统 TTS。`you're = you are` 这类条目读左侧。
Future<bool> speakWord(String word) async {
  _currentAbort?.abort();
  _currentAbort = null;

  final text = speakTextFromEntry(word);
  if (text.isEmpty) return false;

  final signal = AbortSignal();
  _currentAbort = signal;

  try {
    final path = await _cache.readyPath(text);

    if (path != null) {
      final ok = await _playAudioFile(path, signal);
      if (ok || signal.aborted) return ok;
      _log.debug('有道播放失败，回落到系统 TTS: $text');
    }

    return await _speakWithSystemTts(text, signal);
  } catch (e) {
    if (signal.aborted) return false;
    _log.warn('speakWord 失败: $text $e');
    try {
      return await _speakWithSystemTts(text, signal);
    } catch (_) {
      return false;
    }
  } finally {
    if (identical(_currentAbort, signal)) {
      _currentAbort = null;
    }
  }
}

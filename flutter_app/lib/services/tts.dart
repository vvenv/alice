import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_tts/flutter_tts.dart';
import 'package:http/http.dart' as http;
import 'package:just_audio/just_audio.dart';
import 'package:path_provider/path_provider.dart';

import 'abort.dart';
import 'dictation.dart';
import 'logger.dart';
import 'storage.dart';

/// 单词发音。优先播放已缓存的有道词典音频，否则回落到系统 TTS。
///
/// 对应 RN 版 src/lib/tts.ts：
/// - expo-speech       → flutter_tts
/// - expo-audio        → just_audio
/// - expo-file-system  → path_provider + dart:io
const _log = Logger('TTS');

const int _minAudioBytes = 256;
const String _cacheDirName = 'tts';
const Map<String, String> _downloadHeaders = {
  'User-Agent':
      'Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15',
};

double _currentSpeechRate = kDefaultSpeechRate;

AbortSignal? _currentAbort;
AudioPlayer? _wordPlayer;
FlutterTts? _tts;
Directory? _cacheDir;
final Map<String, Future<String?>> _pendingDownloads = {};

// ---------------------------------------------------------------------------
// 播放器 / TTS 引擎
// ---------------------------------------------------------------------------

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

/// 新的 FileSystem API 在 Web 上是空壳，存不下音频文件。
bool _canUseDiskCache() => !kIsWeb;

// ---------------------------------------------------------------------------
// 有道下载 + 本地缓存
// ---------------------------------------------------------------------------

Future<Directory> _ensureCacheDir() async {
  final cached = _cacheDir;
  if (cached != null && cached.existsSync()) return cached;

  final tmp = await getTemporaryDirectory();
  final dir = Directory('${tmp.path}/$_cacheDirName');
  if (!dir.existsSync()) {
    dir.createSync(recursive: true);
  }
  _cacheDir = dir;
  return dir;
}

String _cacheKeyFor(String text) => text.trim().toLowerCase();

String _cacheFileName(String text) {
  final safe = Uri.encodeComponent(_cacheKeyFor(text)).replaceAll('%', '_');
  return '${safe.isEmpty ? 'unknown' : safe}.mp3';
}

Future<File> _cacheFileFor(String text) async {
  final dir = await _ensureCacheDir();
  return File('${dir.path}/${_cacheFileName(text)}');
}

List<String> _youdaoUrls(String text) {
  final q = Uri.encodeComponent(text);
  // 优先美音 (type=2)，其次英音 (type=1)
  return [
    'https://dict.youdao.com/dictvoice?audio=$q&type=2',
    'https://dict.youdao.com/dictvoice?audio=$q&type=1',
  ];
}

bool _isValidCachedFile(File file) {
  if (!file.existsSync()) return false;
  return file.lengthSync() >= _minAudioBytes;
}

Future<String?> _downloadYoudaoAudio(String text, AbortSignal signal) async {
  if (!_canUseDiskCache()) return null;

  final dest = await _cacheFileFor(text);
  if (_isValidCachedFile(dest)) return dest.path;

  for (final url in _youdaoUrls(text)) {
    if (signal.aborted) return null;

    final client = http.Client();
    void closeOnAbort() => client.close();
    signal.addListener(closeOnAbort);

    try {
      if (dest.existsSync()) {
        try {
          dest.deleteSync();
        } catch (_) {}
      }

      final response = await client.get(Uri.parse(url), headers: _downloadHeaders);
      if (signal.aborted) return null;

      if (response.statusCode == 200 &&
          response.bodyBytes.length >= _minAudioBytes) {
        dest.writeAsBytesSync(response.bodyBytes);
        return dest.path;
      }
    } catch (e) {
      if (signal.aborted) return null;
      _log.debug('有道音频下载失败: $url $e');
    } finally {
      signal.removeListener(closeOnAbort);
      client.close();
    }
  }

  return null;
}

Future<String?> _getReadyYoudaoPath(String text) async {
  if (!_canUseDiskCache()) return null;
  final cached = await _cacheFileFor(text);
  return _isValidCachedFile(cached) ? cached.path : null;
}

/// 预取单词音频（不阻塞播放）。返回本地文件路径或 null。
Future<String?> prefetchWordAudio(String word) async {
  final text = speakTextFromEntry(word);
  if (text.isEmpty || !_canUseDiskCache()) return null;

  final ready = await _getReadyYoudaoPath(text);
  if (ready != null) return ready;

  final key = _cacheKeyFor(text);
  final pending = _pendingDownloads[key];
  if (pending != null) return pending;

  final download = _downloadYoudaoAudio(text, AbortSignal())
      .catchError((_) => null as String?);
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
Future<int> clearTtsCache() async {
  if (!_canUseDiskCache()) return 0;

  final tmp = await getTemporaryDirectory();
  final dir = Directory('${tmp.path}/$_cacheDirName');
  if (!dir.existsSync()) return 0;

  var count = 0;
  try {
    for (final entry in dir.listSync()) {
      if (entry is File) count += 1;
    }
    dir.deleteSync(recursive: true);
    _cacheDir = null;
  } catch (e) {
    _log.warn('clearTtsCache 失败: $e');
    rethrow;
  }
  return count;
}

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
      return completer.future;
    }
    player.play();
  } catch (e) {
    _log.warn('音频播放失败: $e');
    finish(false);
  }

  return completer.future;
}

/// 用系统 TTS 朗读，返回是否正常读完。
Future<bool> _speakWithSystemTts(String text, AbortSignal signal) async {
  final tts = await _getTts();
  await tts.stop();
  if (signal.aborted) return false;

  final completer = Completer<bool>();
  var settled = false;
  late void Function() onAbort;

  // 兜底超时：与 RN 版一致，按文本长度估算上限。
  final maxMs = (text.length * 250).clamp(4000, 1 << 30);
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

/// expo-speech 的 rate 是「1.0 = 正常语速」；flutter_tts 在 Android 上
/// 0.5 才是正常语速，iOS 用的是 AVSpeechUtterance 的 0..1 区间。
/// 这里把 0.5–1.5 的用户区间映射到各平台的实际取值。
double _normalizedRate(double rate) {
  if (kIsWeb) return rate;
  if (Platform.isIOS || Platform.isMacOS) {
    // AVSpeechUtteranceDefaultSpeechRate ≈ 0.5
    return (rate * 0.5).clamp(0.0, 1.0);
  }
  // Android: TextToSpeech.setSpeechRate，1.0 为正常语速
  return rate.clamp(0.1, 3.0);
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
    final path = await _getReadyYoudaoPath(text);

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

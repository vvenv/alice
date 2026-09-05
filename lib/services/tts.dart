import 'dart:async';
import 'dart:convert';

import 'package:audio_session/audio_session.dart';
import 'package:http/http.dart' as http;
import 'package:flutter/foundation.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:just_audio/just_audio.dart';

import 'abort.dart';
import 'dictation.dart';
import 'logger.dart';
import 'ocr_config.dart' show buildChatCompletionsUrl;
import 'prefs.dart';
import 'storage.dart';
import 'tts_cache.dart';
import 'tts_config.dart';

/// 单词发音。优先播放已缓存的有道词典音频，否则回落到系统 TTS。
///
/// 对应 RN 版 src/lib/tts.ts：
/// - expo-speech       → flutter_tts
/// - expo-audio        → just_audio (+ audio_session 管音频会话)
/// - expo-file-system  → tts_cache.dart（按平台条件导入，Web 上是空实现）
const _log = Logger('TTS');

const TtsCacheApi _cache = TtsCache();

double _currentSpeechRate = kDefaultSpeechRate;

/// 朗读语言。有道词典发音只有英文，中文只能走系统 TTS。
const String kLangEn = 'en-US';
const String kLangZh = 'zh-CN';

final RegExp _cjkRe = RegExp(r'[一-鿿]');

bool _isCjk(String text) => _cjkRe.hasMatch(text);

String _langFor(String text) => _isCjk(text) ? kLangZh : kLangEn;

// --- 「读中文释义」开关 -------------------------------------------------------

const String _readTranslationKey = 'alice_read_translation';

bool _readTranslation = false;
bool _readTranslationLoaded = false;
Future<bool>? _readTranslationLoad;

/// 当前是否要在两遍单词之间朗读中文释义。同步读，供调度器在热路径上用。
bool isReadTranslationEnabled() => _readTranslation;

/// 从存储读一次开关。重复调用共享同一个 Future。
Future<bool> loadReadTranslation() {
  if (_readTranslationLoaded) return Future.value(_readTranslation);
  return _readTranslationLoad ??= Prefs.getString(_readTranslationKey)
      .then((v) {
        // 读盘期间用户手动切过的话，以用户的操作为准。
        if (!_readTranslationLoaded) _readTranslation = v == 'on';
        return _readTranslation;
      })
      .catchError((Object _) => _readTranslation)
      .whenComplete(() {
        _readTranslationLoaded = true;
        _readTranslationLoad = null;
      });
}

void setReadTranslationEnabled(bool value) {
  _readTranslation = value;
  _readTranslationLoaded = true;
  Prefs.setString(_readTranslationKey, value ? 'on' : 'off')
      .catchError((Object _) {});
}

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
  await tts.setLanguage(kLangEn);
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

  // 选了自定义服务商就由它生成 —— 它中英文都能读。
  await ensureTtsSettingsLoaded();
  final provider = _activeProviderConfig();
  if (provider != null) return _prefetchProviderAudio(text, provider);

  // 有道 dictvoice 是英文词典发音（type=1/2 是英音/美音），拿中文去问它只会
  // 缓存下一段错的音频，而且会盖过系统中文 TTS。中文一律走系统 TTS。
  if (_isCjk(text)) return null;

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
// 自定义 TTS 服务商（OpenAI 兼容）
// ---------------------------------------------------------------------------

/// 已在生成的片段最多等这么久，避免同一个词先用系统音、下一遍换服务商音。
const Duration _providerWaitTimeout = Duration(milliseconds: 1500);

const int _minAudioBytes = 256;

final Map<String, Future<String?>> _pendingProviderDownloads = {};

String _providerVoiceFor(TtsProviderConfig cfg, String text) =>
    (_isCjk(text) ? cfg.voiceZh : cfg.voiceEn).trim();

String _providerFormatFor(TtsProviderConfig cfg) {
  if (cfg.api == TtsApiKind.chat) return 'wav';
  final fmt = (cfg.responseFormat ?? 'mp3').trim().toLowerCase();
  return fmt.isEmpty ? 'mp3' : fmt;
}

/// MiMo 的 TTS 把要朗读的文本放在 assistant 轮；通用 chat.completions
/// （以及自定义端点）期望的是 user 消息。
String _chatContentRole(TtsProviderConfig cfg) =>
    RegExp(r'xiaomimimo\.com', caseSensitive: false).hasMatch(cfg.baseUrl)
        ? 'assistant'
        : 'user';

/// 服务商 / 模型 / 音色 / 格式（speech 形态还含语速）的 8 位十六进制哈希。
/// 其中任何一项变了，缓存文件名就变，片段自动重新生成。
String _providerClipHash(TtsProviderConfig cfg, String text) {
  // chat 形态不发 speed，把语速算进去会让每次拖动滑块都重生成同一段音频。
  final rateQ = cfg.api == TtsApiKind.speech
      ? (_currentSpeechRate * 10).round().toString()
      : '-';
  final seed = '${cfg.api.name}|${cfg.model}|'
      '${_providerVoiceFor(cfg, text)}|${_providerFormatFor(cfg)}|$rateQ';
  var h = 5381;
  for (final unit in seed.codeUnits) {
    h = ((h << 5) + h + unit) & 0xffffffff;
  }
  return h.toRadixString(16).padLeft(8, '0');
}

String _providerClipName(String text, TtsProviderConfig cfg) {
  final trimmed = text.trim().toLowerCase();
  final safe = Uri.encodeComponent(trimmed).replaceAll('%', '_');
  return '${safe.isEmpty ? 'unknown' : safe}'
      '.${_providerClipHash(cfg, text)}.${_providerFormatFor(cfg)}';
}

Future<String?> _readyProviderClip(String text, TtsProviderConfig cfg) =>
    _cache.readyClipPath(_providerClipName(text, cfg));

String _apiErrorMessage(http.Response res) {
  try {
    final decoded = json.decode(utf8.decode(res.bodyBytes, allowMalformed: true));
    if (decoded is Map && decoded['error'] is Map) {
      final message = (decoded['error'] as Map)['message'];
      if (message is String && message.isNotEmpty) return message;
    }
  } catch (_) {
    // 落到下面的通用文案
  }
  return 'HTTP ${res.statusCode}';
}

/// 从 chat.completions 的响应里取 `choices[0].message.audio.data`。
String? _chatAudioData(Object? decoded) {
  if (decoded is! Map) return null;
  final choices = decoded['choices'];
  if (choices is! List || choices.isEmpty) return null;
  final first = choices.first;
  if (first is! Map) return null;
  final message = first['message'];
  if (message is! Map) return null;
  final audio = message['audio'];
  if (audio is! Map) return null;
  final data = audio['data'];
  return data is String ? data : null;
}

/// 向服务商请求一段音频并写入缓存，返回本地路径。失败返回 null。
Future<String?> _downloadProviderAudio(
  String text,
  TtsProviderConfig cfg,
  AbortSignal signal, {
  bool rethrowError = false,
}) async {
  final headers = {
    'Content-Type': 'application/json',
    'Authorization': 'Bearer ${cfg.apiKey}',
  };
  final voice = _providerVoiceFor(cfg, text);
  List<int> bytes;

  final client = http.Client();
  void closeOnAbort() => client.close();
  signal.addListener(closeOnAbort);

  try {
    if (cfg.api == TtsApiKind.chat) {
      // MiMo 风格：走 chat.completions 合成，base64 音频在回复里。
      final audio = <String, String>{'format': 'wav'};
      if (voice.isNotEmpty) audio['voice'] = voice;
      final res = await client.post(
        Uri.parse(buildChatCompletionsUrl(cfg.baseUrl)),
        headers: headers,
        body: json.encode({
          'model': cfg.model,
          'messages': [
            {'role': _chatContentRole(cfg), 'content': text},
          ],
          'audio': audio,
        }),
      );
      if (res.statusCode < 200 || res.statusCode >= 300) {
        throw Exception(_apiErrorMessage(res));
      }
      final decoded =
          json.decode(utf8.decode(res.bodyBytes, allowMalformed: true));
      final b64 = _chatAudioData(decoded);
      if (b64 == null || b64.isEmpty) {
        throw Exception('响应中没有音频数据');
      }
      // 各家对 base64 的换行/填充处理不一，先洗掉非字母表字符再补齐。
      bytes = base64.decode(
        base64.normalize(b64.replaceAll(RegExp(r'[^A-Za-z0-9+/=]'), '')),
      );
    } else {
      // 标准 /audio/speech：响应体就是二进制音频。
      final body = <String, dynamic>{
        'model': cfg.model,
        'input': text,
        'response_format': _providerFormatFor(cfg),
        'speed': _currentSpeechRate.clamp(0.25, 4.0),
      };
      if (voice.isNotEmpty) body['voice'] = voice;
      final res = await client.post(
        Uri.parse(buildSpeechUrl(cfg.baseUrl)),
        headers: headers,
        body: json.encode(body),
      );
      if (res.statusCode < 200 || res.statusCode >= 300) {
        throw Exception(_apiErrorMessage(res));
      }
      bytes = res.bodyBytes;
    }
  } catch (e) {
    if (signal.aborted) return null;
    _log.debug('TTS 服务商请求失败: $text $e');
    if (rethrowError) rethrow;
    return null;
  } finally {
    signal.removeListener(closeOnAbort);
    client.close();
  }

  if (signal.aborted || bytes.length < _minAudioBytes) {
    if (rethrowError && bytes.length < _minAudioBytes) {
      throw Exception('返回的音频过短，可能不是有效音频');
    }
    return null;
  }

  return _cache.writeClip(_providerClipName(text, cfg), bytes);
}

Future<String?> _prefetchProviderAudio(String text, TtsProviderConfig cfg) {
  final key = '${_providerClipHash(cfg, text)}:${_cacheKeyFor(text)}';
  final pending = _pendingProviderDownloads[key];
  if (pending != null) return pending;

  final download = _downloadProviderAudio(text, cfg, AbortSignal())
      .catchError((Object _) => null);
  _pendingProviderDownloads[key] = download;
  unawaited(download.whenComplete(() {
    if (identical(_pendingProviderDownloads[key], download)) {
      _pendingProviderDownloads.remove(key);
    }
  }));
  return download;
}

/// 有界地等一次正在进行的生成。用来吃掉「同一个词两遍用了两种嗓音」的竞态：
/// 第一遍最多等 1.5 秒，等不到就照常回落系统 TTS。
Future<String?> _waitForProviderClip(String text, TtsProviderConfig cfg) async {
  final ready = await _readyProviderClip(text, cfg);
  if (ready != null) return ready;

  final pending = _prefetchProviderAudio(text, cfg);
  await Future.any<Object?>([
    pending,
    Future<Object?>.delayed(_providerWaitTimeout),
  ]);
  return _readyProviderClip(text, cfg);
}

/// 当前生效的服务商配置；没选自定义或配置不完整时返回 null。
TtsProviderConfig? _activeProviderConfig() {
  if (getCachedTtsSource() != TtsSource.custom) return null;
  final cfg = getCachedTtsProviderConfig();
  return isTtsProviderConfigSet(cfg) ? cfg : null;
}

/// 试听一段中英文，验证服务商配置是否可用。失败抛出带描述的异常。
Future<void> testTtsConfig(TtsProviderConfig cfg) async {
  var played = false;
  for (final sample in ['apple', '苹果，一种很常见的水果']) {
    final path = await _downloadProviderAudio(
      sample,
      cfg,
      AbortSignal(),
      rethrowError: true,
    );
    if (path == null) {
      throw Exception('无法生成试听音频，请检查接口地址、密钥和模型');
    }
    final ok =
        await _playAudioFile(path, AbortSignal()).catchError((Object _) => false);
    if (ok) played = true;
  }
  if (!played) throw Exception('音频已生成，但本机播放失败');
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
    // ★ 必须等 seenPlaying。playerStateStream 会把**当前**状态重放给新订阅者，
    //   而播放器是复用的：上一次朗读结束后它停在 completed，这次一订阅就先收到
    //   那个陈旧的 completed，于是本次朗读被判定为「秒完成」。调度器随即进入
    //   700ms 间隙、再开下一次朗读，而下一次开头的 player.pause() 正好把还在
    //   响的这一遍尾音掐掉 —— 表现就是「两遍发音里，前一遍的尾音没了」。
    //   （RN 版的 expo-audio 用的是事件发射器，不重放，所以没这个问题。）
    if (state.processingState == ProcessingState.completed && seenPlaying) {
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
Future<bool> _speakWithSystemTts(
  String text,
  AbortSignal signal,
  String lang,
) async {
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
    // 语言逐句设置：同一段听写里英文单词和中文释义会交替出现。
    await tts.setLanguage(lang);
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
///
/// [lang] 不传时按文本内容判定（含汉字即中文）—— 听写中文释义时调用方
/// 会显式传 [kLangZh]。
Future<bool> speakWord(String word, {String? lang}) async {
  _currentAbort?.abort();
  _currentAbort = null;

  final text = speakTextFromEntry(word);
  if (text.isEmpty) return false;

  final speechLang = lang ?? _langFor(text);
  final signal = AbortSignal();
  _currentAbort = signal;

  try {
    await ensureTtsSettingsLoaded();
    final provider = _activeProviderConfig();

    // 自定义服务商：中英文都由它生成，第一遍最多等 1.5 秒，
    // 免得同一个词两遍用了两种嗓音。
    // 有道：只有英文，且只用已经缓存好的，绝不在播放时等下载。
    final path = provider != null
        ? await _waitForProviderClip(text, provider)
        : (speechLang == kLangEn ? await _cache.readyPath(text) : null);

    if (path != null) {
      final ok = await _playAudioFile(path, signal);
      if (ok || signal.aborted) return ok;
      _log.debug(
        '${provider != null ? '服务商' : '有道'}播放失败，回落到系统 TTS: $text',
      );
    }

    return await _speakWithSystemTts(text, signal, speechLang);
  } catch (e) {
    if (signal.aborted) return false;
    _log.warn('speakWord 失败: $text $e');
    try {
      return await _speakWithSystemTts(text, signal, speechLang);
    } catch (_) {
      return false;
    }
  } finally {
    if (identical(_currentAbort, signal)) {
      _currentAbort = null;
    }
  }
}

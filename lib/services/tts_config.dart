import 'dart:async';
import 'dart:convert';

import 'prefs.dart';

/// 听写发音的来源与自定义 TTS 服务商配置。
/// 对应 Expo 版 src/lib/ttsConfig.ts。

/// 单词音频从哪里来。
enum TtsSource { youdao, custom }

/// 已配置的 OpenAI 兼容 TTS 接口的两种形态：
///
/// - [TtsApiKind.speech]：标准的 `POST {base}/audio/speech`，直接返回二进制音频
///   （OpenAI TTS、智谱 GLM-TTS、硅基流动…）。
/// - [TtsApiKind.chat]：`POST {base}/chat/completions` 带 `audio` 参数，
///   base64 音频放在 `choices[0].message.audio.data` 里（小米 MiMo）。
enum TtsApiKind { chat, speech }

TtsApiKind? _apiKindFromName(Object? name) => switch (name) {
      'chat' => TtsApiKind.chat,
      'speech' => TtsApiKind.speech,
      _ => null,
    };

class TtsProviderConfig {
  const TtsProviderConfig({
    required this.api,
    required this.baseUrl,
    required this.apiKey,
    required this.model,
    this.voiceEn = '',
    this.voiceZh = '',
    this.responseFormat,
  });

  final TtsApiKind api;
  final String baseUrl;
  final String apiKey;
  final String model;

  /// 英文朗读用的音色；空串表示用服务商默认音色。
  final String voiceEn;

  /// 中文朗读用的音色；空串表示用服务商默认音色。
  final String voiceZh;

  /// `speech` 形态的返回格式（默认 mp3）。
  final String? responseFormat;

  TtsProviderConfig copyWith({
    TtsApiKind? api,
    String? baseUrl,
    String? apiKey,
    String? model,
    String? voiceEn,
    String? voiceZh,
    String? responseFormat,
  }) {
    return TtsProviderConfig(
      api: api ?? this.api,
      baseUrl: baseUrl ?? this.baseUrl,
      apiKey: apiKey ?? this.apiKey,
      model: model ?? this.model,
      voiceEn: voiceEn ?? this.voiceEn,
      voiceZh: voiceZh ?? this.voiceZh,
      responseFormat: responseFormat ?? this.responseFormat,
    );
  }

  Map<String, dynamic> toJson() => {
        'api': api.name,
        'baseUrl': baseUrl,
        'apiKey': apiKey,
        'model': model,
        'voiceEn': voiceEn,
        'voiceZh': voiceZh,
        if (responseFormat != null) 'responseFormat': responseFormat,
      };

  static TtsProviderConfig? fromJson(Map<String, dynamic> json) {
    final api = _apiKindFromName(json['api']);
    if (api == null) return null;
    if (json['baseUrl'] is! String ||
        json['apiKey'] is! String ||
        json['model'] is! String) {
      return null;
    }
    return TtsProviderConfig(
      api: api,
      baseUrl: json['baseUrl'] as String,
      apiKey: json['apiKey'] as String,
      model: json['model'] as String,
      voiceEn: json['voiceEn'] is String ? json['voiceEn'] as String : '',
      voiceZh: json['voiceZh'] is String ? json['voiceZh'] as String : '',
      responseFormat:
          json['responseFormat'] is String ? json['responseFormat'] as String : null,
    );
  }
}

class TtsProviderPreset {
  const TtsProviderPreset({
    required this.id,
    required this.label,
    required this.api,
    required this.baseUrl,
    required this.model,
    required this.voiceEn,
    required this.voiceZh,
    this.responseFormat,
    this.hint,
  });

  final String id;
  final String label;
  final TtsApiKind api;
  final String baseUrl;
  final String model;
  final String voiceEn;
  final String voiceZh;
  final String? responseFormat;

  /// 预设下方的一行提示，比如去哪里申请 key。
  final String? hint;
}

/// OpenAI 兼容的 TTS 服务商。目前只有 MiMo 免费，其余是填好的便捷预设，
/// 每个字段仍然可改。
const List<TtsProviderPreset> kTtsProviderPresets = [
  TtsProviderPreset(
    id: 'mimo',
    label: '小米 MiMo',
    api: TtsApiKind.chat,
    baseUrl: 'https://api.xiaomimimo.com/v1',
    model: 'mimo-v2.5-tts',
    voiceEn: 'Chloe',
    voiceZh: '冰糖',
    hint: '限时免费 · mimo.mi.com',
  ),
  TtsProviderPreset(
    id: 'zhipu',
    label: '智谱 GLM',
    api: TtsApiKind.speech,
    baseUrl: 'https://open.bigmodel.cn/api/paas/v4',
    model: 'glm-tts',
    voiceEn: 'tongtong',
    voiceZh: 'tongtong',
    responseFormat: 'wav',
    hint: 'open.bigmodel.cn',
  ),
  TtsProviderPreset(
    id: 'siliconflow',
    label: '硅基流动',
    api: TtsApiKind.speech,
    baseUrl: 'https://api.siliconflow.cn/v1',
    model: 'FunAudioLLM/CosyVoice2-0.5B',
    voiceEn: 'FunAudioLLM/CosyVoice2-0.5B:alex',
    voiceZh: 'FunAudioLLM/CosyVoice2-0.5B:anna',
    hint: 'siliconflow.cn',
  ),
  TtsProviderPreset(
    id: 'openai',
    label: 'OpenAI',
    api: TtsApiKind.speech,
    baseUrl: 'https://api.openai.com/v1',
    model: 'gpt-4o-mini-tts',
    voiceEn: 'alloy',
    voiceZh: 'alloy',
    hint: '需可访问 OpenAI 的网络',
  ),
  TtsProviderPreset(
    id: 'custom',
    label: '自定义',
    api: TtsApiKind.speech,
    baseUrl: '',
    model: '',
    voiceEn: '',
    voiceZh: '',
  ),
];

const String _ttsSourceKey = 'alice_tts_source';
const String _ttsConfigKey = 'alice_tts_provider_config';

TtsSource _cachedSource = TtsSource.youdao;
TtsProviderConfig? _cachedConfig;
bool _loaded = false;
Future<TtsSettings>? _inflight;

/// 每次保存 +1，防止还在飞的读盘把刚保存的值盖回去。
int _saveGen = 0;

class TtsSettings {
  const TtsSettings({required this.source, required this.config});

  final TtsSource source;
  final TtsProviderConfig? config;
}

TtsProviderConfig? _parseStoredConfig(String raw) {
  try {
    final decoded = json.decode(raw);
    if (decoded is! Map<String, dynamic>) return null;
    return TtsProviderConfig.fromJson(decoded);
  } catch (_) {
    return null;
  }
}

Future<TtsSettings> _readFromStorage() async {
  final gen = _saveGen;
  var source = TtsSource.youdao;
  TtsProviderConfig? config;
  try {
    final storedSource = await Prefs.getString(_ttsSourceKey);
    final raw = await Prefs.getString(_ttsConfigKey);
    source = storedSource == 'custom' ? TtsSource.custom : TtsSource.youdao;
    config = raw != null ? _parseStoredConfig(raw) : null;
  } catch (_) {
    // 读不到就用默认值
  }
  if (gen == _saveGen) {
    _cachedSource = source;
    _cachedConfig = config;
    _loaded = true;
  }
  return TtsSettings(source: _cachedSource, config: _cachedConfig);
}

Future<TtsSettings> loadTtsSettings() {
  final inflight = _inflight;
  if (inflight != null) return inflight;
  final future = _readFromStorage().whenComplete(() => _inflight = null);
  _inflight = future;
  return future;
}

/// 第一次读盘完成后 resolve；之后的调用几乎是同步的。
Future<TtsSettings> ensureTtsSettingsLoaded() {
  if (_loaded) {
    return Future.value(
      TtsSettings(source: _cachedSource, config: _cachedConfig),
    );
  }
  return loadTtsSettings();
}

/// 同步读取；首次加载完成之前一律是 [TtsSource.youdao]。
TtsSource getCachedTtsSource() => _loaded ? _cachedSource : TtsSource.youdao;

/// 同步读取；首次加载完成之前是 null。
TtsProviderConfig? getCachedTtsProviderConfig() => _loaded ? _cachedConfig : null;

/// 接口地址、密钥、模型三样都非空才算可用。
bool isTtsProviderConfigSet(TtsProviderConfig? cfg) =>
    cfg != null &&
    cfg.baseUrl.trim().isNotEmpty &&
    cfg.apiKey.trim().isNotEmpty &&
    cfg.model.trim().isNotEmpty;

Future<void> saveTtsSource(TtsSource source) async {
  _saveGen += 1;
  _cachedSource = source;
  _loaded = true;
  try {
    await Prefs.setString(_ttsSourceKey, source.name);
  } catch (_) {
    // 存不下也不影响本次会话
  }
}

Future<void> saveTtsProviderConfig(TtsProviderConfig? cfg) async {
  _saveGen += 1;
  _cachedConfig = cfg;
  _loaded = true;
  try {
    if (cfg != null) {
      await Prefs.setString(_ttsConfigKey, json.encode(cfg.toJson()));
    } else {
      await Prefs.remove(_ttsConfigKey);
    }
  } catch (_) {
    // 同上
  }
}

/// 从 base URL 拼出 `/audio/speech`。允许用户直接粘贴完整端点。
String buildSpeechUrl(String baseUrl) {
  final trimmed = baseUrl.trim().replaceAll(RegExp(r'/+$'), '');
  if (RegExp(r'/audio/speech$').hasMatch(trimmed)) return trimmed;
  return '$trimmed/audio/speech';
}

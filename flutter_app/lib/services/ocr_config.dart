import 'dart:convert';

import 'package:flutter/foundation.dart' show kIsWeb;

import 'prefs.dart';

/// 自定义 OCR 服务商配置（BYOK）。对应 RN 版 src/lib/ocrConfig.ts。
const String _ocrConfigKey = 'alice_ocr_provider_config';

/// Web 构建永不内嵌共享 OCR 密钥 —— 用户必须自备。
bool requiresCustomOcrConfig() => kIsWeb;

class OcrProviderConfig {
  const OcrProviderConfig({
    required this.baseUrl,
    required this.apiKey,
    required this.model,
  });

  final String baseUrl;
  final String apiKey;
  final String model;

  Map<String, dynamic> toJson() => {
        'baseUrl': baseUrl,
        'apiKey': apiKey,
        'model': model,
      };

  static OcrProviderConfig? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final baseUrl = raw['baseUrl'];
    final apiKey = raw['apiKey'];
    final model = raw['model'];
    if (baseUrl is! String || apiKey is! String || model is! String) {
      return null;
    }
    return OcrProviderConfig(baseUrl: baseUrl, apiKey: apiKey, model: model);
  }
}

class OcrProviderPreset {
  const OcrProviderPreset({
    required this.id,
    required this.label,
    required this.baseUrl,
    required this.model,
    this.hint,
  });

  final String id;
  final String label;
  final String baseUrl;

  /// 该预设推荐的视觉模型。
  final String model;

  /// 简短提示，比如去哪儿拿 key。
  final String? hint;
}

/// 主流 OpenAI 兼容视觉服务商。它们都暴露接受 `image_url` 内容块的
/// `/chat/completions`，所以同一份请求体在各家之间通用 —— 只有
/// base URL、key 和模型名不同。
const List<OcrProviderPreset> kOcrProviderPresets = [
  OcrProviderPreset(
    id: 'zhipu',
    label: '智谱 GLM',
    baseUrl: 'https://open.bigmodel.cn/api/paas/v4',
    model: 'glm-4v-flash',
    hint: 'open.bigmodel.cn',
  ),
  OcrProviderPreset(
    id: 'openai',
    label: 'OpenAI',
    baseUrl: 'https://api.openai.com/v1',
    model: 'gpt-4o-mini',
    hint: 'platform.openai.com',
  ),
  OcrProviderPreset(
    id: 'qwen',
    label: '通义千问 VL',
    baseUrl: 'https://dashscope.aliyuncs.com/compatible-mode/v1',
    model: 'qwen-vl-plus',
    hint: 'dashscope.aliyuncs.com',
  ),
  OcrProviderPreset(
    id: 'moonshot',
    label: 'Kimi (Moonshot)',
    baseUrl: 'https://api.moonshot.cn/v1',
    model: 'moonshot-v1-8k-vision-preview',
    hint: 'platform.moonshot.cn',
  ),
  OcrProviderPreset(
    id: 'siliconflow',
    label: '硅基流动',
    baseUrl: 'https://api.siliconflow.cn/v1',
    model: 'Qwen/Qwen2-VL-7B-Instruct',
    hint: 'siliconflow.cn',
  ),
  OcrProviderPreset(
    id: 'openrouter',
    label: 'OpenRouter',
    baseUrl: 'https://openrouter.ai/api/v1',
    model: 'google/gemini-flash-1.5',
    hint: 'openrouter.ai',
  ),
  OcrProviderPreset(
    id: 'ollama',
    label: 'Ollama (本地)',
    baseUrl: 'http://localhost:11434/v1',
    model: 'llama3.2-vision',
    hint: '无需 KEY，需开启本地服务',
  ),
  OcrProviderPreset(
    id: 'custom',
    label: '自定义',
    baseUrl: '',
    model: '',
  ),
];

/// 三个字段都非空时配置才可用。
bool isCustomOcrConfigSet(OcrProviderConfig? cfg) {
  return cfg != null &&
      cfg.baseUrl.trim().isNotEmpty &&
      cfg.apiKey.trim().isNotEmpty &&
      cfg.model.trim().isNotEmpty;
}

OcrProviderConfig? _cached;
bool _loaded = false;

Future<OcrProviderConfig?> loadOcrProviderConfig() async {
  try {
    final data = await Prefs.getString(_ocrConfigKey);
    if (data == null || data.isEmpty) {
      _cached = null;
      _loaded = true;
      return null;
    }
    _cached = OcrProviderConfig.fromJson(json.decode(data));
    _loaded = true;
    return _cached;
  } catch (_) {
    _cached = null;
    _loaded = true;
    return null;
  }
}

/// 同步读取缓存值；loadOcrProviderConfig() 跑过之前为 null。
OcrProviderConfig? getCachedOcrProviderConfig() => _loaded ? _cached : null;

Future<void> saveOcrProviderConfig(OcrProviderConfig? cfg) async {
  _cached = cfg;
  _loaded = true;
  try {
    if (cfg != null) {
      await Prefs.setString(_ocrConfigKey, json.encode(cfg.toJson()));
    } else {
      await Prefs.remove(_ocrConfigKey);
    }
  } catch (_) {
    // 忽略 —— 内存里仍然是对的
  }
}

/// 从 base URL 拼出 `/chat/completions`。
/// 容忍已经带上该路径的写法，用户可以直接粘贴完整端点。
String buildChatCompletionsUrl(String baseUrl) {
  final trimmed = baseUrl.trim().replaceAll(RegExp(r'/+$'), '');
  if (RegExp(r'/chat/completions$').hasMatch(trimmed)) return trimmed;
  return '$trimmed/chat/completions';
}

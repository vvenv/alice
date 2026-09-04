import 'dart:convert';

import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';

import 'config.dart';
import 'credits.dart';
import 'ocr_config.dart';

/// 拍照识词。对应 RN 版 src/lib/ocr.ts。
///
/// - expo-image-picker      → image_picker
/// - expo-image-manipulator → flutter_image_compress
/// - fetch                  → package:http
const int _ocrMaxEdge = 1600;
const int _ocrJpegQuality = 82;

/// OCR 入口处统一展示的免责声明，让用户知道结果可能有误。
const String kOcrDisclaimer = 'AI 识图可能存在误差，请核对识别结果';

/// 选中高级内置模型但余额不足时抛出。
/// UI 捕获它来打开充值流程，而不是弹一个通用错误 toast。
class InsufficientCreditsError implements Exception {
  const InsufficientCreditsError(this.cost);

  final int cost;

  @override
  String toString() => 'Credits 不足，请充值后使用高级识别';
}

/// 进行中的阶段（顶栏）。终态文案在 OcrOutcomeMessages。
enum OcrProgressPhase {
  preparingPhoto,
  preparingAlbum,
  compressing,
  recognizing
}

const Map<OcrProgressPhase, String> kOcrProgressMessages = {
  OcrProgressPhase.preparingPhoto: '已拍摄，准备识别…',
  OcrProgressPhase.preparingAlbum: '已选图，准备识别…',
  OcrProgressPhase.compressing: '处理图片中…',
  OcrProgressPhase.recognizing: '识别中…',
};

class OcrOutcomeMessages {
  const OcrOutcomeMessages._();

  static String success(int count) => '已识别 $count 个单词';
  static const String empty = '未识别到英文单词，请换一张更清晰的图片再试';
  static const String emptyUnparsed = '未能从识别结果中提取英文单词，请换一张更清晰的单词列表再试';
  static const String failed = '识别失败';
}

class OcrUiState {
  const OcrUiState({required this.busy, required this.message});

  final bool busy;
  final String message;

  static const OcrUiState idle = OcrUiState(busy: false, message: '');
}

final ImagePicker _picker = ImagePicker();

Future<String?> takePhoto() async {
  final file = await _picker.pickImage(
    source: ImageSource.camera,
    imageQuality: 100,
  );
  return file?.path;
}

Future<String?> pickFromAlbum() async {
  final file = await _picker.pickImage(
    source: ImageSource.gallery,
    imageQuality: 100,
  );
  return file?.path;
}

class _CompressedImage {
  const _CompressedImage(this.base64, this.mimeType);

  final String base64;
  final String mimeType;
}

Future<_CompressedImage> _compressImageForOcr(String path) async {
  final bytes = await FlutterImageCompress.compressWithFile(
    path,
    minWidth: _ocrMaxEdge,
    minHeight: _ocrMaxEdge,
    quality: _ocrJpegQuality,
    format: CompressFormat.jpeg,
  );

  if (bytes == null) {
    throw Exception('读取图片失败');
  }
  return _CompressedImage(base64Encode(bytes), 'image/jpeg');
}

class _OcrRequestConfig {
  const _OcrRequestConfig({
    required this.baseUrl,
    required this.apiKey,
    required this.model,
    required this.premiumCost,
  });

  final String baseUrl;
  final String apiKey;
  final String model;

  /// 成功后要扣的 credits，免费/BYOK 为 0。
  final int premiumCost;
}

/// 决定这一次识别用哪个服务：
///  1. 完整的 BYOK 自定义配置优先（用户自己的 key —— 永不扣费）。
///  2. 否则用选中的内置模型 + App 内置密钥。高级内置模型需要预先有余额。
Future<_OcrRequestConfig> _resolveOcrRequest() async {
  final custom = await loadOcrProviderConfig();
  if (isCustomOcrConfigSet(custom)) {
    return _OcrRequestConfig(
      baseUrl: custom!.baseUrl.trim(),
      apiKey: custom.apiKey.trim(),
      model: custom.model.trim(),
      premiumCost: 0,
    );
  }

  if (requiresCustomOcrConfig()) {
    throw Exception('请先在设置中配置 OCR 服务（Web 版需自备 API Key）');
  }
  if (AppConfig.zhipuApiKey.trim().isEmpty) {
    throw Exception('请先在设置中配置 OCR 服务');
  }

  final selected = getBuiltinModel(await loadSelectedModelId());
  if (selected.tier == ModelTier.premium) {
    final balance = await ensureCreditsLoaded();
    if (balance < selected.creditCost) {
      throw InsufficientCreditsError(selected.creditCost);
    }
    return _OcrRequestConfig(
      baseUrl: AppConfig.zhipuBaseUrl,
      apiKey: AppConfig.zhipuApiKey,
      model: selected.model,
      premiumCost: selected.creditCost,
    );
  }

  return _OcrRequestConfig(
    baseUrl: AppConfig.zhipuBaseUrl,
    apiKey: AppConfig.zhipuApiKey,
    model: selected.model,
    premiumCost: 0,
  );
}

class OcrResult {
  const OcrResult({required this.words, required this.rawText});

  final List<String> words;
  final String rawText;
}

const String _ocrPrompt = '这是一张包含英文单词列表的图片。'
    '请识别图中所有英文单词或词组。'
    '如果单词旁边标注了词性和中文释义，请一并提取，每行格式：单词 | 词性 | 中文释义'
    '如果图中没有词性或释义信息，只输出单词本身。'
    '像 actor / actress 这样的斜杠词组应作为一整行输出，不要拆开。'
    '不要用逗号连接、不要编号、不要输出其他标点或解释。';

Future<OcrResult> ocrWordsFromImage(
  String imagePath, {
  void Function(OcrProgressPhase phase)? onProgress,
}) async {
  onProgress?.call(OcrProgressPhase.compressing);
  final image = await _compressImageForOcr(imagePath);
  final dataUrl = 'data:${image.mimeType};base64,${image.base64}';

  onProgress?.call(OcrProgressPhase.recognizing);

  final cfg = await _resolveOcrRequest();
  final endpoint = buildChatCompletionsUrl(cfg.baseUrl);

  http.Response response;
  try {
    response = await http.post(
      Uri.parse(endpoint),
      headers: {
        'Authorization': 'Bearer ${cfg.apiKey}',
        'Content-Type': 'application/json',
      },
      body: json.encode({
        'model': cfg.model,
        'temperature': 0.1,
        'messages': [
          {
            'role': 'user',
            'content': [
              {
                'type': 'image_url',
                'image_url': {'url': dataUrl},
              },
              {'type': 'text', 'text': _ocrPrompt},
            ],
          },
        ],
      }),
    );
  } catch (_) {
    throw Exception('网络请求失败，请检查网络后重试');
  }

  if (response.statusCode < 200 || response.statusCode >= 300) {
    final detail = utf8.decode(response.bodyBytes, allowMalformed: true);
    throw Exception(detail.isNotEmpty ? '视觉识别失败: $detail' : '视觉识别服务异常');
  }

  // 只在 API 返回成功之后才扣 credits，失败/异常不消耗余额。
  // 单飞（ocrBusy）保证不会并发扣费。
  if (cfg.premiumCost > 0) {
    await trySpendCredits(cfg.premiumCost);
  }

  final payload =
      json.decode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
  final choices = payload['choices'];
  String rawText = '';
  if (choices is List && choices.isNotEmpty) {
    final message = (choices.first as Map)['message'];
    if (message is Map && message['content'] is String) {
      rawText = (message['content'] as String).trim();
    }
  }

  return OcrResult(words: extractWordsFromOcrText(rawText), rawText: rawText);
}

/// 用一个最小的纯文本 chat/completions 请求验证候选 OCR 配置。
/// 失败时抛出带描述的异常。OCR 设置面板保存前会调用它。
Future<void> testOcrConfig({
  required String baseUrl,
  required String apiKey,
  required String model,
}) async {
  final endpoint = buildChatCompletionsUrl(baseUrl);

  http.Response response;
  try {
    response = await http.post(
      Uri.parse(endpoint),
      headers: {
        'Authorization': 'Bearer $apiKey',
        'Content-Type': 'application/json',
      },
      body: json.encode({
        'model': model,
        'temperature': 0,
        'max_tokens': 1,
        'messages': [
          {'role': 'user', 'content': 'hi'},
        ],
      }),
    );
  } catch (_) {
    throw Exception('网络请求失败，请检查 URL 与网络');
  }

  final status = response.statusCode;
  if (status >= 200 && status < 300) return;

  var detail = '';
  try {
    final text = utf8.decode(response.bodyBytes, allowMalformed: true);
    try {
      final j = json.decode(text);
      if (j is Map && j['error'] is Map && j['error']['message'] is String) {
        detail = j['error']['message'] as String;
      } else {
        detail = text;
      }
    } catch (_) {
      detail = text;
    }
  } catch (_) {
    // 忽略
  }

  final hint = detail.isNotEmpty
      ? ': ${detail.length > 160 ? detail.substring(0, 160) : detail}'
      : '';
  if (status == 401 || status == 403) {
    throw Exception('认证失败（$status）$hint');
  }
  if (status == 404) {
    throw Exception('未找到接口（404），请检查 URL$hint');
  }
  throw Exception('请求失败（$status）$hint');
}

/// 真实听写词组几乎不会超过这么多个空格分隔的 token
/// （如 "ice cream"、"look forward to"、"actor / actress"）。
/// 更长的串按「视觉模型把结果堆成一行」处理。
const int _maxPhraseTokens = 4;

/// 去掉列表标记、外层引号和尾部标点。
String _cleanToken(String s) {
  return s
      .replaceFirst(RegExp(r'^[\d.)\-•*、]+\s*'), '')
      .replaceAll(RegExp(r'''^["'`“”‘’]+|["'`“”‘’]+$'''), '')
      .replaceAll(RegExp(r'[.。:：]+$'), '')
      .trim();
}

final RegExp _wordRe = RegExp(r"^[a-zA-Z][a-zA-Z'/\-\s]*$");

/// 视觉模型经常无视「每行一个」，返回逗号或空格分隔的列表。
/// 这个函数把输出归一化成干净的单词表。
///
/// 支持带 `|` 词性/释义的条目：
///   `apple | n. | 苹果` —— 校验单词部分，保留元数据。
/// 纯条目（无 `|`）沿用原来的逗号切分 + token 展平逻辑。
List<String> extractWordsFromOcrText(String rawText) {
  final cleaned = rawText
      .replaceAllMapped(
        RegExp(r'```[\s\S]*?```'),
        (m) => m
            .group(0)!
            .replaceFirst(RegExp(r'^```\w*\n?'), '')
            .replaceFirst(RegExp(r'\n?```$'), ''),
      )
      .replaceAll(RegExp(r'\r\n?'), '\n');

  // 先按换行切，保住带释义的整行条目
  final lines =
      cleaned.split('\n').map((l) => l.trim()).where((l) => l.isNotEmpty);

  final seen = <String>{};
  final words = <String>[];

  for (final line in lines) {
    final pipeIdx = line.indexOf('|');

    if (pipeIdx != -1) {
      // 带释义的条目：清洗并校验单词部分，元数据原样保留
      final rawWord = line.substring(0, pipeIdx);
      final metaParts = line
          .substring(pipeIdx + 1)
          .split('|')
          .map((s) => s.trim())
          .where((s) => s.isNotEmpty)
          .toList();

      final wordPart = _cleanToken(rawWord);
      if (wordPart.isEmpty || !_wordRe.hasMatch(wordPart)) continue;

      final key = wordPart.toLowerCase();
      if (!seen.add(key)) continue;

      // 用统一的间距重新拼装
      words.add([wordPart, ...metaParts].join(' | '));
    } else {
      // 纯单词：先按逗号/分号切（视觉模型可能忽略每行一个），
      // 再把过长的串展平成单个 token
      final candidates = <String>[];
      for (final part in line.split(RegExp(r'[,，;；、]+'))) {
        final candidate = _cleanToken(part);
        if (candidate.isEmpty) continue;
        final tokens =
            candidate.split(RegExp(r'\s+')).where((t) => t.isNotEmpty).toList();
        if (tokens.length <= _maxPhraseTokens) {
          candidates.add(candidate);
        } else {
          candidates.addAll(tokens);
        }
      }

      for (final word in candidates) {
        if (!_wordRe.hasMatch(word)) continue;
        final key = word.toLowerCase();
        if (!seen.add(key)) continue;
        words.add(word);
      }
    }
  }

  return words;
}

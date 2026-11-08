import 'package:flutter/foundation.dart';

import 'config.dart';
import 'ocr_config.dart';
import 'prefs.dart';

/// 内置 OCR 模型（App 密钥提供）。对应原 RN 版 credits.ts 里的模型表，
/// 积分 / 高级档已移除 —— 只保留免费内置模型；自备密钥走自定义配置。
@immutable
class BuiltinModel {
  const BuiltinModel({
    required this.id,
    required this.label,
    required this.model,
    required this.description,
  });

  final String id;
  final String label;

  /// 传给 chat/completions 端点的 API 模型名。
  final String model;

  final String description;
}

const List<BuiltinModel> kBuiltinModels = [
  BuiltinModel(
    id: 'glm-4v-flash',
    label: 'GLM-4V Flash',
    model: 'glm-4v-flash',
    description: '快速识别，日常单词列表够用',
  ),
];

const String kDefaultModelId = 'glm-4v-flash';

BuiltinModel getBuiltinModel(String id) {
  for (final m in kBuiltinModels) {
    if (m.id == id) return m;
  }
  return kBuiltinModels.first;
}

const String _selectedModelKey = 'alice_ocr_selected_model';

Future<String> loadSelectedModelId() async {
  try {
    final id = await Prefs.getString(_selectedModelKey);
    if (id != null && kBuiltinModels.any((m) => m.id == id)) return id;
  } catch (_) {
    // 忽略
  }
  return kDefaultModelId;
}

Future<void> saveSelectedModelId(String id) async {
  try {
    await Prefs.setString(_selectedModelKey, id);
  } catch (_) {
    // 忽略
  }
}

/// 打开相机/相册之前的预检。
class OcrGateResult {
  const OcrGateResult.ok()
      : allowed = true,
        needsCustomConfig = false;

  const OcrGateResult.needsCustomConfig()
      : allowed = false,
        needsCustomConfig = true;

  final bool allowed;
  final bool needsCustomConfig;
}

/// 打开相机/相册之前的预检。
///
/// - 已有 BYOK 自定义配置：放行。
/// - 当前平台必须自备 OCR（Web）或没有内置密钥：未配置时拦截。
///
/// [customConfigRequired] 仅供测试覆盖 Web 路径；生产代码不要传。
Future<OcrGateResult> canRunOcrNow({bool? customConfigRequired}) async {
  final custom = await loadOcrProviderConfig();
  if (isCustomOcrConfigSet(custom)) return const OcrGateResult.ok();
  final needsCustom = customConfigRequired ?? requiresCustomOcrConfig();
  if (needsCustom) return const OcrGateResult.needsCustomConfig();
  if (AppConfig.zhipuApiKey.trim().isEmpty) {
    return const OcrGateResult.needsCustomConfig();
  }
  return const OcrGateResult.ok();
}

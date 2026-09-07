import 'package:flutter/foundation.dart';

import 'config.dart';
import 'ocr_config.dart';
import 'prefs.dart';

/// OCR 模型分档与 Credits 账本。对应 RN 版 src/lib/credits.ts。
enum ModelTier { free, premium }

/// 由 App 内置密钥提供服务的视觉模型。
///
/// - `free` 档对所有人无限使用。
/// - `premium` 档每次成功识别扣除 `creditCost` credits；余额不足不能用。
///
/// `creditCost` 就是每次扣减量 —— 调这里即可调整套餐经济。
/// 新增一档只需要往列表里加一项。
@immutable
class BuiltinModel {
  const BuiltinModel({
    required this.id,
    required this.label,
    required this.model,
    required this.tier,
    required this.creditCost,
    required this.description,
  });

  final String id;
  final String label;

  /// 传给 chat/completions 端点的 API 模型名。
  final String model;

  final ModelTier tier;

  /// 每次成功识别扣除的 credits，免费档为 0。
  final int creditCost;

  final String description;
}

const List<BuiltinModel> kBuiltinModels = [
  BuiltinModel(
    id: 'glm-4v-flash',
    label: 'GLM-4V Flash',
    model: 'glm-4v-flash',
    tier: ModelTier.free,
    creditCost: 0,
    description: '快速识别，日常单词列表够用',
  ),
  BuiltinModel(
    id: 'glm-4v-plus',
    label: 'GLM-4V Plus',
    model: 'glm-4v-plus',
    tier: ModelTier.premium,
    creditCost: 1,
    description: '更高精度，适合复杂或模糊图片',
  ),
];

const String kDefaultModelId = 'glm-4v-flash';

BuiltinModel getBuiltinModel(String id) {
  for (final m in kBuiltinModels) {
    if (m.id == id) return m;
  }
  return kBuiltinModels.first;
}

bool isPremiumModel(String id) => getBuiltinModel(id).tier == ModelTier.premium;

// --- 充值包 ---------------------------------------------------------------
// 模拟购买包。每个包把价格映射到 credits 数量（+ 可选赠送）。
// 这里是将来接真实 IAP（StoreKit / Google Play / RevenueCat）的接缝：
// 把 purchasePack 换成平台流程，并且只在交易验证通过后调用 addCredits。

@immutable
class CreditPack {
  const CreditPack({
    required this.id,
    required this.label,
    required this.credits,
    required this.bonus,
    required this.price,
    this.highlight = false,
  });

  final String id;
  final String label;
  final int credits;
  final int bonus;
  final String price;
  final bool highlight;

  int get total => credits + bonus;
}

const List<CreditPack> kCreditPacks = [
  CreditPack(
    id: 'pack_20',
    label: '20 Credits',
    credits: 20,
    bonus: 0,
    price: '¥6',
  ),
  CreditPack(
    id: 'pack_60',
    label: '60 Credits',
    credits: 60,
    bonus: 6,
    price: '¥15',
    highlight: true,
  ),
  CreditPack(
    id: 'pack_200',
    label: '200 Credits',
    credits: 200,
    bonus: 30,
    price: '¥45',
  ),
];

// --- 余额持久化 -----------------------------------------------------------

const String _creditsKey = 'alice_ocr_credits';
const String _selectedModelKey = 'alice_ocr_selected_model';

int? _cachedCredits;

Future<int> loadCreditBalance() async {
  try {
    final data = await Prefs.getString(_creditsKey);
    final n = data != null && data.isNotEmpty ? num.tryParse(data) : null;
    _cachedCredits = (n != null && n.isFinite && n > 0) ? n.floor() : 0;
  } catch (_) {
    _cachedCredits = 0;
  }
  return _cachedCredits!;
}

/// 确保缓存已填充后返回它。
Future<int> ensureCreditsLoaded() async {
  return _cachedCredits ?? await loadCreditBalance();
}

int getCachedCredits() => _cachedCredits ?? 0;

Future<int> addCredits(int amount) async {
  final next = getCachedCredits() + (amount < 0 ? 0 : amount);
  _cachedCredits = next;
  try {
    await Prefs.setString(_creditsKey, next.toString());
  } catch (_) {
    // 忽略 —— 本次会话的余额仍在内存里
  }
  return next;
}

/// 扣除 credits。成功返回 true，余额不足返回 false。
///
/// 只在高级识别成功之后调用，失败的 API 请求不扣用户余额。
Future<bool> trySpendCredits(int cost) async {
  if (cost <= 0) return true;
  final balance = await ensureCreditsLoaded();
  if (balance < cost) return false;
  _cachedCredits = balance - cost;
  try {
    await Prefs.setString(_creditsKey, _cachedCredits!.toString());
  } catch (_) {
    // 忽略
  }
  return true;
}

/// 模拟购买：立即到账。接真实 IAP 时替换这里。
Future<int> purchasePack(CreditPack pack) => addCredits(pack.total);

// --- 已选内置模型 ---------------------------------------------------------

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

// --- OCR 运行前置检查 -----------------------------------------------------

class OcrGateResult {
  const OcrGateResult.ok()
      : allowed = true,
        needsCustomConfig = false,
        cost = 0,
        balance = 0,
        model = null;

  const OcrGateResult.insufficientCredits({
    required this.cost,
    required this.balance,
    required this.model,
  })  : allowed = false,
        needsCustomConfig = false;

  const OcrGateResult.needsCustomConfig()
      : allowed = false,
        needsCustomConfig = true,
        cost = 0,
        balance = 0,
        model = null;

  final bool allowed;
  final bool needsCustomConfig;
  final int cost;
  final int balance;
  final BuiltinModel? model;
}

/// 打开相机/相册之前的预检。
///
/// - 已有 BYOK 自定义配置：放行。
/// - 当前平台必须自备 OCR（Web）：未配置时拦截，别让用户白拍一张。
/// - 高级内置模型需要足够余额；否则调用方应该提示充值，而不是先拍照。
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

  final selected = getBuiltinModel(await loadSelectedModelId());
  if (selected.tier == ModelTier.premium) {
    final balance = await ensureCreditsLoaded();
    if (balance < selected.creditCost) {
      return OcrGateResult.insufficientCredits(
        cost: selected.creditCost,
        balance: balance,
        model: selected,
      );
    }
  }
  return const OcrGateResult.ok();
}

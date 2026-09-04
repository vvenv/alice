import 'package:flutter/foundation.dart';

import '../services/credits.dart';
import '../services/ocr_config.dart';

/// OCR 额度状态：credits 余额、选中的内置模型，以及是否有 BYOK 自定义配置
/// 覆盖内置服务。涉及 OCR 的界面（首页、设置）用它来渲染余额、切换模型和充值。
///
/// 对应 RN 版 src/hooks/useOcrQuota.ts。
class OcrQuotaController extends ChangeNotifier {
  OcrQuotaController() {
    refresh();
  }

  int _credits = 0;
  String _modelId = kDefaultModelId;
  bool _hasCustomConfig = false;
  bool _ready = false;
  bool _disposed = false;

  int get credits => _credits;
  String get modelId => _modelId;
  bool get hasCustomConfig => _hasCustomConfig;
  bool get ready => _ready;

  BuiltinModel get model => getBuiltinModel(_modelId);

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  Future<void> refresh() async {
    final results = await Future.wait([
      loadCreditBalance(),
      loadSelectedModelId(),
      loadOcrProviderConfig(),
    ]);
    _credits = results[0] as int;
    _modelId = results[1] as String;
    _hasCustomConfig = isCustomOcrConfigSet(results[2] as OcrProviderConfig?);
    _ready = true;
    _notify();
  }

  Future<void> selectModel(String id) async {
    _modelId = id;
    _notify();
    await saveSelectedModelId(id);
  }

  Future<int> recharge(CreditPack pack) async {
    final next = await purchasePack(pack);
    _credits = next;
    _notify();
    return next;
  }

  Future<int> grantCredits(int amount) async {
    final next = await addCredits(amount);
    _credits = next;
    _notify();
    return next;
  }

  /// OCR 跑完后把本地余额与内存缓存对齐。
  void syncFromCache() {
    _credits = getCachedCredits();
    _notify();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}

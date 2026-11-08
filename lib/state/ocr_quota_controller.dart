import 'package:flutter/foundation.dart';

import '../services/ocr_config.dart';
import '../services/ocr_models.dart';

/// OCR 设置状态：选中的内置模型，以及是否有 BYOK 自定义配置覆盖内置服务。
///
/// 涉及 OCR 的界面（首页、设置）用它来切换免费内置模型与自定义服务。
/// 文件名沿用 `ocr_quota_controller`（历史遗留）；积分系统已移除。
class OcrQuotaController extends ChangeNotifier {
  OcrQuotaController() {
    refresh();
  }

  String _modelId = kDefaultModelId;
  bool _hasCustomConfig = false;
  bool _ready = false;
  bool _disposed = false;

  String get modelId => _modelId;
  bool get hasCustomConfig => _hasCustomConfig;
  bool get ready => _ready;

  BuiltinModel get model => getBuiltinModel(_modelId);

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  Future<void> refresh() async {
    final results = await Future.wait([
      loadSelectedModelId(),
      loadOcrProviderConfig(),
    ]);
    _modelId = results[0] as String;
    _hasCustomConfig = isCustomOcrConfigSet(results[1] as OcrProviderConfig?);
    _ready = true;
    _notify();
  }

  Future<void> selectModel(String id) async {
    _modelId = id;
    _notify();
    await saveSelectedModelId(id);
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}

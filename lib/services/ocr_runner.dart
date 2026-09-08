import '../services/credits.dart';
import 'abort.dart';
import 'ocr.dart';

/// [ocrWordsFromImage] 的形状，供 [OcrRunner] 替换。
typedef OcrRecognize = Future<OcrResult> Function(
  XFile file, {
  void Function(OcrProgressPhase phase)? onProgress,
  AbortSignal? signal,
});

/// 选图之后的裁切 / 旋转。返回 null 视为用户取消，不进入识别。
typedef OcrEditImage = Future<XFile?> Function(XFile file);

/// 拍照/相册 → 编辑 → 识别 → 回调的一次完整流程。
///
/// 对应 Expo 版 src/components/OcrSection.tsx —— 那边是个「不渲染任何东西、
/// 只通过 ref 暴露 processPhoto / processAlbum」的组件（hideActions 时直接
/// return null）。Flutter 侧没必要为此造一个 widget，直接做成普通类。
class OcrRunner {
  OcrRunner({
    required this.onResult,
    required this.onStateChange,
    required this.onOutcome,
    required this.onInsufficientCredits,
    required this.onNeedsOcrConfig,
    Future<XFile?> Function()? pickPhoto,
    Future<XFile?> Function()? pickAlbum,
    OcrEditImage? editImage,
    OcrRecognize? recognize,
  })  : _pickPhoto = pickPhoto ?? takePhoto,
        _pickAlbum = pickAlbum ?? pickFromAlbum,
        _editImage = editImage,
        _recognize = recognize ?? ocrWordsFromImage;

  /// 拍照 / 相册 / 编辑 / 识别都能换掉。
  ///
  /// 不是为了「可测试性」而抽象：取消与超时这条路径在真机之外没别的地方能
  /// 走到，插件在测试环境里直接抛 MissingPluginException。
  final Future<XFile?> Function() _pickPhoto;
  final Future<XFile?> Function() _pickAlbum;
  final OcrEditImage? _editImage;
  final OcrRecognize _recognize;

  /// 识别出的单词列表。
  final void Function(List<String> words) onResult;

  /// 进行中的 UI 状态（顶栏的转圈 + 文案）。
  final void Function(OcrUiState state) onStateChange;

  /// 终态提示（成功 / 空结果 / 报错），交给 toast。
  final void Function(String message) onOutcome;

  /// 高级模型余额不足 —— 调用方应该打开充值流程。
  final void Function() onInsufficientCredits;

  /// Web / 无内置密钥且未配置 BYOK —— 调用方应该打开 OCR 设置。
  final void Function() onNeedsOcrConfig;

  bool _busy = false;
  AbortSignal? _signal;

  /// runOcr 的同步重入锁。
  ///
  /// [_busy] 不够用：它要等 [_setUiState] 才置位，而那发生在 `await
  /// canRunOcrNow()` 之后 —— 两次快速点击会双双穿过去，高级模型就被扣两次费。
  /// 这个标志在第一个 await **之前**同步占位。
  bool _running = false;

  bool get busy => _busy;

  /// 中止正在进行的识别。
  ///
  /// 请求本身现在有超时兜底，但 60 秒对着一个转圈等下去仍然是坏体验 ——
  /// 用户往往当场就知道自己拍糊了。
  void cancel() {
    _signal?.abort();
    _signal = null;
  }

  void _setUiState(OcrUiState state) {
    _busy = state.busy;
    onStateChange(state);
  }

  void _reportProgress(OcrProgressPhase phase) {
    _setUiState(OcrUiState(busy: true, message: kOcrProgressMessages[phase]!));
  }

  Future<void> _run(
    Future<XFile?> Function() pick,
    OcrProgressPhase preparingPhase,
  ) async {
    // 重入锁在第一个 await 之前同步占位，见 [_running]。
    if (_running) return;
    _running = true;
    try {
      // 选图必须在任何 await 之前启动。
      //
      // Web 的 image_picker 是往 DOM 里插一个 <input type="file"> 再
      // `input.click()`。浏览器要求这次 click 落在用户手势的同步调用栈里，
      // 否则文件框被静默吞掉 —— 用户点了「拍摄照片 / 从相册选取」，
      // 抽屉关上，然后什么都不发生。
      //
      // 预检（canRunOcrNow）自己就要 await，所以不能再放在选图前面。
      // 抽屉已经把未配置 OCR 的入口换成「去配置」；真被预检拦下来，
      // 就丢掉这次选图结果。
      final pickFuture = pick();

      final gate = await canRunOcrNow();
      if (!gate.allowed) {
        try {
          await pickFuture;
        } catch (_) {}
        if (gate.needsCustomConfig) {
          onNeedsOcrConfig();
        } else {
          onInsufficientCredits();
        }
        return;
      }

      _setUiState(const OcrUiState(busy: true, message: ''));
      try {
        final file = await pickFuture;
        if (file == null) {
          _setUiState(OcrUiState.idle);
          return;
        }

        // 编辑页是交互，不是识别。转圈文案先收起来，取消编辑等同没选图。
        XFile ready = file;
        final edit = _editImage;
        if (edit != null) {
          _setUiState(OcrUiState.idle);
          final edited = await edit(file);
          if (edited == null) {
            _setUiState(OcrUiState.idle);
            return;
          }
          ready = edited;
        }

        _reportProgress(preparingPhase);
        final signal = AbortSignal();
        _signal = signal;
        final result = await _recognize(
          ready,
          onProgress: _reportProgress,
          signal: signal,
        );

        if (result.words.isEmpty) {
          onOutcome(
            result.rawText.isNotEmpty
                ? OcrOutcomeMessages.emptyUnparsed
                : OcrOutcomeMessages.empty,
          );
          return;
        }

        onResult(result.words);
        onOutcome(OcrOutcomeMessages.success(result.words.length));
      } on InsufficientCreditsError {
        onInsufficientCredits();
      } catch (error) {
        // 用户自己按的取消，不算失败，也不用再提示一次
        // —— 取消那一下已经给过反馈了。
        final message = _message(error);
        if (message != kOcrCancelled) onOutcome(message);
      } finally {
        _signal = null;
        _setUiState(OcrUiState.idle);
      }
    } finally {
      _running = false;
    }
  }

  String _message(Object error) {
    final text = error.toString();
    if (text.startsWith('Exception: ')) return text.substring(11);
    return text.isNotEmpty ? text : OcrOutcomeMessages.failed;
  }

  Future<void> processPhoto() =>
      _run(_pickPhoto, OcrProgressPhase.preparingPhoto);

  Future<void> processAlbum() =>
      _run(_pickAlbum, OcrProgressPhase.preparingAlbum);
}

import '../services/credits.dart';
import 'ocr.dart';

/// 拍照/相册 → 识别 → 回调的一次完整流程。
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
  });

  /// 识别出的单词列表。
  final void Function(List<String> words) onResult;

  /// 进行中的 UI 状态（顶栏的转圈 + 文案）。
  final void Function(OcrUiState state) onStateChange;

  /// 终态提示（成功 / 空结果 / 报错），交给 toast。
  final void Function(String message) onOutcome;

  /// 高级模型余额不足 —— 调用方应该打开充值流程。
  final void Function() onInsufficientCredits;

  bool _busy = false;

  /// runOcr 的同步重入锁。
  ///
  /// [_busy] 不够用：它要等 [_setUiState] 才置位，而那发生在 `await
  /// canRunOcrNow()` 之后 —— 两次快速点击会双双穿过去，高级模型就被扣两次费。
  /// 这个标志在第一个 await **之前**同步占位。
  bool _running = false;

  bool get busy => _busy;

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
      // 预检：高级内置模型需要余额。余额不够时直接跳过整个拍照流程，
      // 转交充值 UI，别让用户白拍一张。
      final gate = await canRunOcrNow();
      if (!gate.allowed) {
        onInsufficientCredits();
        return;
      }

      _setUiState(const OcrUiState(busy: true, message: ''));
      try {
        final file = await pick();
        if (file == null) {
          _setUiState(OcrUiState.idle);
          return;
        }

        _reportProgress(preparingPhase);
        final result =
            await ocrWordsFromImage(file, onProgress: _reportProgress);

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
        onOutcome(_message(error));
      } finally {
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
      _run(takePhoto, OcrProgressPhase.preparingPhoto);

  Future<void> processAlbum() =>
      _run(pickFromAlbum, OcrProgressPhase.preparingAlbum);
}

/// 极简的取消信号 —— 对应 Web/RN 侧的 AbortController / AbortSignal。
///
/// Dart 没有内置等价物，播放调度器（PlaybackController）和 TTS 都依赖
/// 「随时打断当前这一轮」的语义，所以这里补一个最小实现。
class AbortSignal {
  AbortSignal();

  bool _aborted = false;
  final List<void Function()> _listeners = <void Function()>[];

  bool get aborted => _aborted;

  void abort() {
    if (_aborted) return;
    _aborted = true;
    final snapshot = List<void Function()>.from(_listeners);
    _listeners.clear();
    for (final listener in snapshot) {
      listener();
    }
  }

  void addListener(void Function() listener) {
    if (_aborted) {
      listener();
      return;
    }
    _listeners.add(listener);
  }

  void removeListener(void Function() listener) {
    _listeners.remove(listener);
  }
}

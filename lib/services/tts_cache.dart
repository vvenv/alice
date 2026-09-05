/// 按平台选择发音缓存实现。
///
/// 有 `dart:io` 的平台（iOS / Android / desktop）用真正落盘的版本；
/// Web 没有 `dart:io`，落到空实现 —— 发音直接走系统 TTS。
library;

export 'tts_cache_api.dart';
export 'tts_cache_noop.dart' if (dart.library.io) 'tts_cache_io.dart';

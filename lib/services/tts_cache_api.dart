import 'abort.dart';

/// 有道发音 mp3 的本地磁盘缓存接口。
///
/// RN 版在 tts.ts 里用运行时判断 `Platform.OS !== "web"` 关掉磁盘缓存；
/// Dart 不行 —— 只要 import 了 `dart:io`，整个 web 构建就编译失败。
/// 所以按平台条件导入两套实现（见 tts_cache.dart）：
///
/// - `tts_cache_io.dart`   原生端：path_provider + dart:io，真正落盘
/// - `tts_cache_noop.dart` Web 端：全部空操作，直接回落到系统 TTS
abstract class TtsCacheApi {
  /// 该平台是否支持磁盘缓存。Web 上为 false。
  bool get canUseDiskCache;

  /// 已缓存且有效时返回本地路径，否则 null。不发起下载。
  Future<String?> readyPath(String text);

  /// 下载并写入缓存，返回本地路径；失败或被打断返回 null。
  Future<String?> download(String text, AbortSignal signal);

  /// 清空缓存目录，返回删除的文件数。
  Future<int> clear();
}

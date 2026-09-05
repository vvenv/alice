import 'abort.dart';

/// 发音音频的本地磁盘缓存接口。
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

  /// 按给定文件名取一段已缓存的音频，有效时返回路径。
  ///
  /// 与 [readyPath] 的区别：那个按朗读文本推导文件名、只管有道 mp3；
  /// 这个由调用方给出完整文件名，用来存自定义 TTS 服务商生成的片段
  /// （文件名里带服务商/模型/音色的哈希，换配置即换文件）。
  Future<String?> readyClipPath(String name);

  /// 把一段音频字节写进缓存，返回本地路径；写不了返回 null。
  Future<String?> writeClip(String name, List<int> bytes);
}

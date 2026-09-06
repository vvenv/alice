/// 按平台选择 Edge TTS 实现。
///
/// 有 `dart:io` 的平台（iOS / Android / desktop）用真正建 WebSocket 的版本；
/// web 上只有空实现 —— 浏览器不让改握手的 Origin / User-Agent，那个端点
/// 一定 403，发音直接回落有道 / 系统 TTS。
library;

export 'tts_edge_api.dart';
export 'tts_edge_noop.dart' if (dart.library.io) 'tts_edge_io.dart';

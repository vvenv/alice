import 'dart:typed_data';

import 'abort.dart';
import 'tts_edge_api.dart';

/// Web 端的 Edge TTS：不可用。
///
/// 浏览器的 WebSocket 构造器不允许自定义 Origin / User-Agent / Cookie，
/// 而这三样正是那个端点校验的东西，连也是白连。调用方看到
/// `isSupported == false` 就会跳过 Edge，直接走有道 / 系统 TTS。
class EdgeTts implements EdgeTtsApi {
  const EdgeTts();

  @override
  bool get isSupported => false;

  @override
  Future<Uint8List?> synthesize(
    String text, {
    required String voice,
    required AbortSignal signal,
    bool rethrowError = false,
  }) async {
    if (rethrowError) throw Exception('当前平台不支持 Edge 发音');
    return null;
  }
}

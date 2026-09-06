import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import 'abort.dart';
import 'logger.dart';
import 'tts_edge_api.dart';

/// 原生端（iOS / Android / desktop）的 Edge TTS 实现。
///
/// 每次合成开一条 WebSocket：发一条 speech.config、一条 ssml，然后把二进制
/// 帧里的 mp3 拼起来，收到 turn.end 收工。协议细节见 tts_edge_api.dart。
const _log = Logger('EdgeTTS');

const int _minAudioBytes = 256;
const Duration _connectTimeout = Duration(seconds: 8);
const Duration _synthesisTimeout = Duration(seconds: 20);

final Random _random = Random();

String _connectionId() {
  const hex = '0123456789abcdef';
  return List.generate(32, (_) => hex[_random.nextInt(16)]).join();
}

class EdgeTts implements EdgeTtsApi {
  const EdgeTts();

  /// 设备时钟与服务端的偏差（秒）。握手用的 token 按 5 分钟取整，手机
  /// 时间偏了就一路 403；第一次 403 时用服务端的 Date 头校正后重试。
  static int _skewSeconds = 0;

  @override
  bool get isSupported => true;

  @override
  Future<Uint8List?> synthesize(
    String text, {
    required String voice,
    required AbortSignal signal,
    bool rethrowError = false,
  }) async {
    try {
      return await _synthesizeOnce(text, voice, signal);
    } catch (e) {
      if (signal.aborted) return null;

      // 只有 403 值得重试：多半是时钟偏差，校正后还能救回来。
      if (e is WebSocketException && e.message.contains('403')) {
        if (await _syncClockSkew()) {
          try {
            return await _synthesizeOnce(text, voice, signal);
          } catch (e2) {
            if (signal.aborted) return null;
            _log.debug('Edge 合成重试仍失败: $text $e2');
            if (rethrowError) throw Exception(_describe(e2));
            return null;
          }
        }
      }

      _log.debug('Edge 合成失败: $text $e');
      if (rethrowError) throw Exception(_describe(e));
      return null;
    }
  }

  static String _describe(Object error) {
    if (error is WebSocketException) {
      return error.message.contains('403')
          ? 'Edge 服务拒绝了连接（403），可能是设备时间不准或网络受限'
          : 'Edge 连接失败：${error.message}';
    }
    if (error is TimeoutException) return 'Edge 服务响应超时';
    if (error is SocketException) return '网络不可用：${error.message}';
    return error.toString();
  }

  Future<Uint8List?> _synthesizeOnce(
    String text,
    String voice,
    AbortSignal signal,
  ) async {
    if (signal.aborted) return null;

    final now = DateTime.now().toUtc();
    final url = edgeWssUrl(
      secMsGec: edgeSecMsGec(now, skewSeconds: _skewSeconds),
      connectionId: _connectionId(),
    );

    // ★ 必须用自定义 HttpClient 设 userAgent。dart:io 会先塞一个
    //   `Dart/x.y (dart:io)` 的 User-Agent，headers 里再给一个只会**追加**成
    //   第二个值，服务端看到 Dart 的那个就直接 403。改 HttpClient.userAgent
    //   才是覆盖。（这一条卡了很久，别改回去。）
    final client = HttpClient()..userAgent = kEdgeUserAgent;
    WebSocket? socket;
    try {
      socket = await WebSocket.connect(
        url,
        customClient: client,
        headers: {
          'Origin': kEdgeOrigin,
          'Pragma': 'no-cache',
          'Cache-Control': 'no-cache',
          'Accept-Language': 'en-US,en;q=0.9',
        },
      ).timeout(_connectTimeout);

      if (signal.aborted) return null;

      final ws = socket;
      void closeOnAbort() {
        try {
          ws.close();
        } catch (_) {}
      }

      signal.addListener(closeOnAbort);
      try {
        ws.add(edgeSpeechConfigMessage(now));
        ws.add(edgeSsmlMessage(
          requestId: _connectionId(),
          nowUtc: DateTime.now().toUtc(),
          voice: voice,
          text: text,
        ));

        final audio = BytesBuilder(copy: false);
        await for (final message in ws.timeout(_synthesisTimeout)) {
          if (signal.aborted) return null;
          if (message is String) {
            // 文本帧只有 turn.start / response / turn.end 这几种，
            // 元数据在 config 里已经关掉了。
            if (message.contains('Path:turn.end')) break;
          } else if (message is List<int>) {
            audio.add(edgeAudioChunk(message));
          }
        }

        final bytes = audio.takeBytes();
        if (bytes.length < _minAudioBytes) {
          throw Exception('Edge 返回的音频过短，可能不是有效音频');
        }
        return bytes;
      } finally {
        signal.removeListener(closeOnAbort);
      }
    } finally {
      try {
        await socket?.close();
      } catch (_) {}
      client.close();
    }
  }

  /// 用声音列表接口的响应头对一次表，把偏差记进 [_skewSeconds]。
  /// 对不上就返回 false，调用方不再重试。
  static Future<bool> _syncClockSkew() async {
    try {
      final res = await http
          .head(
            Uri.parse(edgeVoiceListUrl()),
            headers: const {'User-Agent': kEdgeUserAgent},
          )
          .timeout(_connectTimeout);
      final date = res.headers['date'];
      if (date == null) return false;
      final serverTime = HttpDate.parse(date);
      final skew =
          serverTime.difference(DateTime.now().toUtc()).inSeconds;
      if (skew == _skewSeconds) return false;
      _log.debug('Edge 时钟偏差校正: $skew 秒');
      _skewSeconds = skew;
      return true;
    } catch (e) {
      _log.debug('Edge 时钟校正失败: $e');
      return false;
    }
  }
}

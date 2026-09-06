import 'package:alice_dictation/services/tts_edge.dart';
import 'package:flutter_test/flutter_test.dart';

/// Edge TTS 的协议细节。
///
/// 这些全是「差一个字节就 403 / 没声音」的东西，而且线上失败的样子是静音、
/// 不是异常 —— 只能在这里钉住。参照实现是 Python 的 edge-tts。
void main() {
  // 2026-09-06T14:23:38Z 落在 5 分钟窗口 134331780000000000 里，
  // 期望值由 edge-tts 的 DRM.generate_sec_ms_gec 算出。
  final sample = DateTime.utc(2026, 9, 6, 14, 23, 38);

  group('Sec-MS-GEC', () {
    test('与 edge-tts 的参照实现逐字节一致', () {
      expect(
        edgeSecMsGec(sample),
        '9FF4FC569323F98DA03A9546C9315243F25ED81EE0801BD0B7FA7A45EA0CA2E7',
      );
    });

    test('同一个 5 分钟窗口内不变，跨窗口才变', () {
      final within = DateTime.utc(2026, 9, 6, 14, 24, 59);
      final next = DateTime.utc(2026, 9, 6, 14, 25, 1);
      expect(edgeSecMsGec(within), edgeSecMsGec(sample));
      expect(edgeSecMsGec(next), isNot(edgeSecMsGec(sample)));
    });

    test('时钟偏差补偿会把 token 推回服务端所在的窗口', () {
      // 设备慢了 10 分钟：补回来就应该和真实时间算出来的一样。
      final slow = sample.subtract(const Duration(minutes: 10));
      expect(edgeSecMsGec(slow, skewSeconds: 600), edgeSecMsGec(sample));
    });
  });

  test('握手 URL 带齐四个查询参数', () {
    final uri = Uri.parse(
      edgeWssUrl(secMsGec: 'ABC', connectionId: 'deadbeef'),
    );
    expect(uri.scheme, 'wss');
    expect(uri.host, kEdgeHost);
    expect(uri.queryParameters['TrustedClientToken'], kEdgeTrustedClientToken);
    expect(uri.queryParameters['ConnectionId'], 'deadbeef');
    expect(uri.queryParameters['Sec-MS-GEC'], 'ABC');
    expect(uri.queryParameters['Sec-MS-GEC-Version'], kEdgeSecMsGecVersion);
  });

  test('时间戳是服务端认的 JavaScript Date 格式', () {
    expect(
      edgeDateString(sample),
      'Sun Sep 06 2026 14:23:38 GMT+0000 (Coordinated Universal Time)',
    );
  });

  group('消息', () {
    test('speech.config 声明的输出格式就是我们按 mp3 解析的那个', () {
      final message = edgeSpeechConfigMessage(sample);
      expect(message, startsWith('X-Timestamp:'));
      expect(message, contains('Path:speech.config'));
      expect(message, contains('"outputFormat":"$kEdgeOutputFormat"'));
      // 边界元数据关掉：开着只会多收一堆用不上的文本帧。
      expect(message, contains('"wordBoundaryEnabled":"false"'));
    });

    test('ssml 头部齐全，音色和文本落在 SSML 里', () {
      final message = edgeSsmlMessage(
        requestId: 'req1',
        nowUtc: sample,
        voice: 'en-US-AriaNeural',
        text: 'apple',
      );
      expect(message, contains('X-RequestId:req1'));
      expect(message, contains('Content-Type:application/ssml+xml'));
      // 时间戳后面这个 Z 是 Edge 自己的 bug，但服务端认它。
      expect(message, contains('(Coordinated Universal Time)Z'));
      expect(message, contains('Path:ssml'));
      expect(message, contains("<voice name='en-US-AriaNeural'>"));
      expect(message, contains('>apple<'));
      // 语速固定 +0%：快慢由播放器调，否则每换一档语速缓存全失效。
      expect(message, contains("rate='+0%'"));
    });

    test('文本里的尖括号与控制字符不会毁掉 SSML', () {
      final message = edgeSsmlMessage(
        requestId: 'req1',
        nowUtc: sample,
        voice: 'zh-CN-XiaoxiaoNeural',
        text: 'a & b <c>',
      );
      expect(message, contains('a &amp; b &lt;c&gt;'));
      expect(message, isNot(contains('<c>')));
    });
  });

  group('二进制帧', () {
    test('按头长度切掉文本头，只留音频', () {
      final header = 'Path:audio'.codeUnits;
      final frame = <int>[0, header.length, ...header, 1, 2, 3];
      expect(edgeAudioChunk(frame), [1, 2, 3]);
    });

    test('残帧不会抛异常，只返回空', () {
      expect(edgeAudioChunk(const [0]), isEmpty);
      expect(edgeAudioChunk(const [0, 40, 1, 2]), isEmpty);
    });
  });
}

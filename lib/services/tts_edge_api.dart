import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

import 'abort.dart';

/// 微软 Edge 「大声朗读」TTS 的协议细节与平台接口。
///
/// 这里只放纯 Dart 的部分（拼 URL / 拼消息 / 算 token / 拆帧），不碰
/// `dart:io`，所以能在测试里直接断言，也不会拖累 web 构建。真正建连接的
/// 实现按平台条件导入，见 tts_edge.dart。
///
/// 协议本身没有公开文档，是 Edge 浏览器朗读功能用的那个 WebSocket 端点：
/// 免费、不需要账号，但也没有 SLA —— 微软改了握手要求（比如下面这个
/// Sec-MS-GEC 就是 2024 年底加的），这条路就会整条失效。所以调用方必须
/// 保留回落：Edge 失败 → 有道 → 系统 TTS。

/// 端点写死的客户端令牌，Edge 浏览器里就是这个常量。
const String kEdgeTrustedClientToken = '6A5AA1D4EAFF4E9FB37E23D68491D6F4';

/// 握手时报的 Chromium 版本。太旧会被 403 —— 服务端确实在看这个值。
const String kEdgeChromiumFullVersion = '143.0.3650.75';
const String kEdgeChromiumMajorVersion = '143';
const String kEdgeSecMsGecVersion = '1-$kEdgeChromiumFullVersion';

const String kEdgeUserAgent =
    'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
    '(KHTML, like Gecko) Chrome/$kEdgeChromiumMajorVersion.0.0.0 '
    'Safari/537.36 Edg/$kEdgeChromiumMajorVersion.0.0.0';

/// 朗读功能是 Edge 内置扩展发起的，Origin 必须是它。
const String kEdgeOrigin =
    'chrome-extension://jdiccldimpdaibmpdkjnbmckianbfold';

const String kEdgeHost = 'speech.platform.bing.com';
const String kEdgeBasePath = '/consumer/speech/synthesize/readaloud';

/// 24kHz / 48kbps 单声道 mp3 —— just_audio 直接能放，也够听写用。
const String kEdgeOutputFormat = 'audio-24khz-48kbitrate-mono-mp3';

/// Windows 文件时间的纪元（1601-01-01）与 Unix 纪元相差的秒数。
const int _winEpochOffsetSeconds = 11644473600;

/// 取声音列表的地址。这里只用来读响应头里的 Date 校正时钟，见 [edgeSecMsGec]。
String edgeVoiceListUrl() =>
    'https://$kEdgeHost$kEdgeBasePath/voices/list'
    '?trustedclienttoken=$kEdgeTrustedClientToken';

/// 生成握手要带的 Sec-MS-GEC。
///
/// 规则：Unix 秒 → Windows 文件时间纪元 → 向下取整到 5 分钟 → 换算成
/// 100 纳秒单位 → 与令牌拼接后取 SHA256 大写十六进制。
///
/// 因为按 5 分钟取整，设备时钟偏差超过 5 分钟就会被服务端 403。
/// [skew] 是从服务端 Date 头算出的补偿秒数，见 tts_edge_io.dart。
String edgeSecMsGec(DateTime nowUtc, {int skewSeconds = 0}) {
  var ticks = nowUtc.millisecondsSinceEpoch ~/ 1000 +
      skewSeconds +
      _winEpochOffsetSeconds;
  ticks -= ticks % 300;
  final hundredNanos = BigInt.from(ticks) * BigInt.from(10000000);
  final digest = sha256.convert(
    ascii.encode('$hundredNanos$kEdgeTrustedClientToken'),
  );
  return digest.toString().toUpperCase();
}

String edgeWssUrl({required String secMsGec, required String connectionId}) =>
    'wss://$kEdgeHost$kEdgeBasePath/edge/v1'
    '?TrustedClientToken=$kEdgeTrustedClientToken'
    '&ConnectionId=$connectionId'
    '&Sec-MS-GEC=$secMsGec'
    '&Sec-MS-GEC-Version=$kEdgeSecMsGecVersion';

const List<String> _weekdays = [
  'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun', //
];
const List<String> _months = [
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', //
  'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
];

String _two(int v) => v.toString().padLeft(2, '0');

/// 协议里的时间戳是 JavaScript `Date.toString()` 的样子，服务端认这个格式。
String edgeDateString(DateTime nowUtc) {
  final d = nowUtc.toUtc();
  return '${_weekdays[d.weekday - 1]} ${_months[d.month - 1]} '
      '${_two(d.day)} ${d.year} '
      '${_two(d.hour)}:${_two(d.minute)}:${_two(d.second)} '
      'GMT+0000 (Coordinated Universal Time)';
}

/// 连接后要先发的一条配置消息：声明输出格式、关掉用不上的边界元数据。
String edgeSpeechConfigMessage(DateTime nowUtc) =>
    'X-Timestamp:${edgeDateString(nowUtc)}\r\n'
    'Content-Type:application/json; charset=utf-8\r\n'
    'Path:speech.config\r\n\r\n'
    '{"context":{"synthesis":{"audio":{"metadataoptions":{'
    '"sentenceBoundaryEnabled":"false","wordBoundaryEnabled":"false"},'
    '"outputFormat":"$kEdgeOutputFormat"}}}}\r\n';

/// SSML 只认 XML 转义，另外服务端会被垂直制表符之类的控制字符噎住。
String edgeEscapeText(String text) {
  final buffer = StringBuffer();
  for (final rune in text.runes) {
    if ((rune >= 0 && rune <= 8) ||
        (rune >= 11 && rune <= 12) ||
        (rune >= 14 && rune <= 31)) {
      buffer.write(' ');
      continue;
    }
    buffer.write(switch (rune) {
      0x26 => '&amp;',
      0x3c => '&lt;',
      0x3e => '&gt;',
      _ => String.fromCharCode(rune),
    });
  }
  return buffer.toString();
}

/// 朗读请求。语速固定 `+0%` —— 播放时由 just_audio 调速，这样换语速不必
/// 重新生成音频，缓存也就不用把语速算进文件名。
String edgeSsmlMessage({
  required String requestId,
  required DateTime nowUtc,
  required String voice,
  required String text,
}) {
  final ssml =
      "<speak version='1.0' xmlns='http://www.w3.org/2001/10/synthesis' "
      "xml:lang='en-US'><voice name='$voice'>"
      "<prosody pitch='+0Hz' rate='+0%' volume='+0%'>"
      '${edgeEscapeText(text)}'
      '</prosody></voice></speak>';
  return 'X-RequestId:$requestId\r\n'
      'Content-Type:application/ssml+xml\r\n'
      // 末尾这个 Z 是 Edge 自己的 bug，但服务端认它，照抄。
      'X-Timestamp:${edgeDateString(nowUtc)}Z\r\n'
      'Path:ssml\r\n\r\n$ssml';
}

/// 从一帧二进制消息里取音频数据。
///
/// 帧结构：2 字节大端头长度 + 文本头 + 音频。头里是 `Path:audio`，
/// 这里不解析，长度不对就当空帧丢掉。
Uint8List edgeAudioChunk(List<int> frame) {
  if (frame.length < 2) return Uint8List(0);
  final headerLength = (frame[0] << 8) | frame[1];
  final start = headerLength + 2;
  if (start >= frame.length) return Uint8List(0);
  return Uint8List.fromList(frame.sublist(start));
}

/// Edge TTS 合成接口。原生端见 tts_edge_io.dart，web 端是空实现。
abstract class EdgeTtsApi {
  /// 该平台能不能用。web 上为 false —— 浏览器改不了 WebSocket 握手的
  /// Origin / User-Agent，那个端点必然 403。
  bool get isSupported;

  /// 合成一段音频，返回 mp3 字节；失败或被打断返回 null。
  Future<Uint8List?> synthesize(
    String text, {
    required String voice,
    required AbortSignal signal,
    bool rethrowError = false,
  });
}

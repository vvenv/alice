import 'package:flutter/services.dart';

import 'logger.dart';

const _log = Logger('Share');

/// 「分享到 Alice」送进来的纯文本。
///
/// 从微信 / 浏览器 / 备忘录里选中一段单词，分享过来直接成词表 —— 比拍照识别
/// 更快，也不消耗 credits。原生侧见 android/.../MainActivity.kt。
///
/// 目前只有 Android。iOS 要一个独立的 Share Extension（自己的 target、
/// App Group、签名），是另一件事；这边拿不到就当没有分享。
class ShareIntake {
  const ShareIntake._();

  static const MethodChannel _channel = MethodChannel('alice/share');

  /// 冷启动时取一次：分享意图在 Dart 侧起来之前就到了，原生那边先存着。
  ///
  /// 取走即清空，重复调用不会拿到同一份。拿不到（iOS、Web、测试环境）返回 null。
  static Future<String?> takePending() async {
    try {
      return await _channel.invokeMethod<String>('takeSharedText');
    } on MissingPluginException {
      return null;
    } catch (e) {
      _log.debug('取分享文本失败：$e');
      return null;
    }
  }

  /// 应用已经在运行时又分享进来一份。
  static void listen(void Function(String text) onText) {
    _channel.setMethodCallHandler((call) async {
      if (call.method != 'sharedText') return null;
      final text = call.arguments;
      if (text is String && text.trim().isNotEmpty) onText(text);
      return null;
    });
  }

  static void stopListening() {
    _channel.setMethodCallHandler(null);
  }
}

import 'package:flutter/foundation.dart';

/// 带命名空间的日志。对应 RN 版 src/lib/logger.ts。
///
/// Release 构建里 debug / info 是空实现；warn / error 始终输出。
class Logger {
  const Logger(this.namespace);

  final String namespace;

  String get _prefix => '[$namespace]';

  void debug(Object? message) {
    if (kDebugMode) debugPrint('$_prefix $message');
  }

  void info(Object? message) {
    if (kDebugMode) debugPrint('$_prefix $message');
  }

  void warn(Object? message) {
    debugPrint('$_prefix WARN $message');
  }

  void error(Object? message) {
    debugPrint('$_prefix ERROR $message');
  }
}

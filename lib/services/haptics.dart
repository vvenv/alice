import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// 触感反馈。对应 RN 版 src/lib/haptics.ts（那边包了一层 expo-haptics）。
///
/// Flutter 的 HapticFeedback 在 Web 和不支持的设备上本身就是空操作，
/// 不需要 RN 版那种 try/require 防御，但仍然吞掉异常保证不崩。
class Haptics {
  const Haptics._();

  static bool get _enabled => !kIsWeb;

  /// 普通按钮点击的轻微震动。
  static void tapLight() {
    if (!_enabled) return;
    HapticFeedback.lightImpact().catchError((Object _) {});
  }

  /// 听写完成时的庆祝反馈。
  ///
  /// Flutter 没有 iOS 的 notification feedback 直接映射，
  /// 用 heavyImpact 作为最接近的等价物。
  static void notifySuccess() {
    if (!_enabled) return;
    HapticFeedback.heavyImpact().catchError((Object _) {});
  }

  /// 标记错词时的反馈。
  static void notifyWarning() {
    if (!_enabled) return;
    HapticFeedback.mediumImpact().catchError((Object _) {});
  }
}

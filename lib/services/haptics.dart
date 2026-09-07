import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'prefs.dart';

/// 触感反馈。对应 RN 版 src/lib/haptics.ts（那边包了一层 expo-haptics）。
///
/// Flutter 的 HapticFeedback 在 Web 和不支持的设备上本身就是空操作，
/// 不需要 RN 版那种 try/require 防御，但仍然吞掉异常保证不崩。
///
/// 可以关：提示音一直有开关，震动没有 —— 安静场合两个都得能关掉。
/// 开关的读取放在 main() 里，别只在设置页读（提示音以前就是这么漏的：
/// 关掉之后重启，设置页没打开过之前又开始响）。
const String _hapticsKey = 'alice_haptics_enabled';

class Haptics {
  const Haptics._();

  static bool _userEnabled = true;

  static bool isEnabled() => _userEnabled;

  static Future<bool> load() async {
    try {
      final v = await Prefs.getString(_hapticsKey);
      _userEnabled = v != 'off';
    } catch (_) {
      // 保持当前值
    }
    return _userEnabled;
  }

  static void setEnabled(bool value) {
    _userEnabled = value;
    Prefs.setString(_hapticsKey, value ? 'on' : 'off')
        .catchError((Object _) {});
  }

  static bool get _enabled => !kIsWeb && _userEnabled;

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

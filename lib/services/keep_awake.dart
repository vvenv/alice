import 'package:wakelock_plus/wakelock_plus.dart';

import 'logger.dart';

const _log = Logger('KeepAwake');

/// 听写过程中的屏幕常亮。对应 RN 版能用而这边一直缺的 expo-keep-awake。
///
/// 为什么需要：听写的标准姿势是手机放桌上、人在纸上写字。系统息屏时间通常
/// 30 秒，一轮听写里没人会去碰屏幕 —— 屏幕黑掉之后倒计时看不见、「标记错词」
/// 点不到，得解锁才能继续。
///
/// 所有调用都吞异常：测试环境没有插件实现（MissingPluginException），
/// Web 上浏览器也可能拒绝 Screen Wake Lock；亮不亮屏都不该把听写弄崩。
class KeepAwake {
  const KeepAwake._();

  static Future<void> enable() => _set(true);

  static Future<void> disable() => _set(false);

  static Future<void> _set(bool on) async {
    try {
      await WakelockPlus.toggle(enable: on);
    } catch (e) {
      // 测试环境每次构建听写页都会走到这里，用 debug 级别避免刷屏。
      _log.debug('屏幕常亮切换失败（on=$on）：$e');
    }
  }
}

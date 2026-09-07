import 'dart:async';

import 'package:audio_session/audio_session.dart';

import 'logger.dart';

const _log = Logger('AudioInterrupt');

/// 听写应该让路的原因。
enum PlaybackInterruption {
  /// 音频焦点被别人拿走：来电、导航播报、别的 App 开始放音。
  focusLost,

  /// 输出设备变了，音会从外放出去 —— 拔耳机、断开蓝牙。
  becameNoisy,
}

/// 音频中断事件源。
///
/// `tts.dart` 里那套 AudioSession 配置只管「我们去 duck 别人」
/// （duckOthers + gainTransientMayDuck），反过来没人管：来电把朗读打断、
/// 倒计时却照走，用户听到半个词就过去了；耳机一拔，下一个单词直接从外放
/// 喇叭喊出来 —— becomingNoisy 这个事件存在的唯一理由就是防这件事。
///
/// 拿不到会话（Web、测试环境）就返回一条空流：听写照常，只是没有这层保护。
Stream<PlaybackInterruption> audioInterruptions() {
  late final StreamController<PlaybackInterruption> controller;
  final subscriptions = <StreamSubscription<void>>[];

  Future<void> attach() async {
    try {
      final session = await AudioSession.instance;

      subscriptions.add(session.interruptionEventStream.listen((event) {
        // 只关心「开始被打断」。duck 是音量被压低，词还是能听见，
        // 停下来反而更打断节奏。
        if (!event.begin) return;
        if (event.type == AudioInterruptionType.duck) return;
        if (!controller.isClosed) controller.add(PlaybackInterruption.focusLost);
      }));

      subscriptions.add(session.becomingNoisyEventStream.listen((_) {
        if (!controller.isClosed) {
          controller.add(PlaybackInterruption.becameNoisy);
        }
      }));
    } catch (e) {
      // 测试环境没有插件实现，Web 上是空实现。
      _log.debug('订阅音频中断失败：$e');
    }
  }

  controller = StreamController<PlaybackInterruption>(
    onListen: () => unawaited(attach()),
    onCancel: () async {
      for (final s in subscriptions) {
        await s.cancel();
      }
      subscriptions.clear();
    },
  );

  return controller.stream;
}

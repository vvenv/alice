import 'package:just_audio/just_audio.dart';

import 'prefs.dart';

/// UI 提示音（倒计时末尾的怀表滴答、完成时的和弦）。
///
/// 音频文件与 RN 版共用同一份自制素材（assets/sounds）。每个调用都是防御性的：
/// 播放失败就静音，不抛异常。
///
/// 对应 RN 版 src/lib/sound.ts。
const String _soundKey = 'alice_sound_enabled';

bool _enabled = true;

bool isSoundEnabled() => _enabled;

Future<bool> loadSoundEnabled() async {
  try {
    final v = await Prefs.getString(_soundKey);
    _enabled = v != 'off';
  } catch (_) {
    // 保持当前值
  }
  return _enabled;
}

void setSoundEnabled(bool value) {
  _enabled = value;
  Prefs.setString(_soundKey, value ? 'on' : 'off').catchError((Object _) {});
}

AudioPlayer? _tickPlayer;
AudioPlayer? _chimePlayer;

Future<void> _play(
  AudioPlayer? Function() get,
  void Function(AudioPlayer) set,
  String asset,
  double volume,
) async {
  if (!_enabled) return;
  try {
    var player = get();
    if (player == null) {
      player = AudioPlayer();
      await player.setAsset(asset);
      await player.setVolume(volume);
      set(player);
    }
    await player.seek(Duration.zero);
    // 不 await play() —— 它要等播放结束才返回，会拖慢调用方。
    player.play();
  } catch (_) {
    // 没有音频后端 —— 保持安静
  }
}

/// 轻柔的怀表滴答 —— 单词倒计时的最后一秒。
void playTick() {
  _play(
    () => _tickPlayer,
    (p) => _tickPlayer = p,
    'assets/sounds/tick.wav',
    0.5,
  );
}

/// 两音和弦 —— 听写完成。
void playChime() {
  _play(
    () => _chimePlayer,
    (p) => _chimePlayer = p,
    'assets/sounds/chime.wav',
    0.6,
  );
}

/// 释放播放器（应用退出/测试清理时）。
Future<void> disposeSoundPlayers() async {
  await _tickPlayer?.dispose();
  await _chimePlayer?.dispose();
  _tickPlayer = null;
  _chimePlayer = null;
}

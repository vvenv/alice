import { useAudioPlayer } from "expo-audio";
import { useCallback, useEffect } from "react";

/**
 * Keeps the audio session alive while dictation is in progress.
 *
 * On Android (and iOS), the JS thread may be suspended when the app goes to
 * the background, which prevents `expo-speech` onDone callbacks and setTimeout
 * timers from firing.  By playing a silent loop through `expo-audio`, the
 * system recognises an active audio session and keeps the JS thread running.
 */
export function useBackgroundAudio() {
  const player = useAudioPlayer(require("../../assets/silent.wav"));

  useEffect(() => {
    player.loop = true;
    player.volume = 0;
    player.muted = true;
  }, [player]);

  const startSession = useCallback(() => {
    if (!player.playing) {
      player.play();
    }
  }, [player]);

  const stopSession = useCallback(() => {
    player.pause();
  }, [player]);

  return { startSession, stopSession };
}

import { setAudioModeAsync } from "expo-audio";
import * as Speech from "expo-speech";

import { createLogger } from "./logger";

const TTS_SPEED = 0.9;
const log = createLogger("TTS");

let currentAbort: (() => void) | null = null;

export async function stopSpeech(): Promise<void> {
  if (currentAbort) {
    currentAbort();
    currentAbort = null;
  }
  Speech.stop();
}

/** Speak a dictation word using the platform en-US TTS engine. */
export async function speakWord(word: string): Promise<boolean> {
  await stopSpeech();

  const text = word.trim();
  if (!text) return false;

  return new Promise((resolve) => {
    let settled = false;

    const finish = (ok: boolean) => {
      if (settled) return;
      settled = true;
      currentAbort = null;
      resolve(ok);
    };

    currentAbort = () => {
      Speech.stop();
      finish(false);
    };

    Speech.speak(text, {
      language: "en-US",
      rate: TTS_SPEED,
      onDone: () => finish(true),
      onStopped: () => finish(false),
      onError: () => finish(false),
    });
  });
}

/** Initialize audio session for playback. */
export async function initAudio(): Promise<void> {
  try {
    await setAudioModeAsync({
      playsInSilentMode: true,
      shouldPlayInBackground: false,
      shouldRouteThroughEarpiece: false,
    });
  } catch (e) {
    log.warn("Failed to set audio mode:", e);
  }
}

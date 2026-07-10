import * as Speech from "expo-speech";

import { createLogger } from "./logger";

const log = createLogger("TTS");

const TTS_SPEED = 0.9;

let currentAbort: AbortController | null = null;

// ---------------------------------------------------------------------------
// Speech — uses expo-speech (system TTS)
//
// Pronunciation always goes through the platform speech synthesizer
// (`Speech.speak`). An earlier implementation downloaded audio files from a
// dictionary service and cached them via expo-file-system, but expo-speech
// cannot play files, so that audio was never used. Worse, expo-file-system's
// legacy API is unavailable on web (its methods throw `UnavailabilityError`),
// which made `speakWord` fail before ever reaching the synthesizer. The
// download/cache path is therefore removed entirely.
// ---------------------------------------------------------------------------

export async function stopSpeech(): Promise<void> {
  if (currentAbort) {
    currentAbort.abort();
    currentAbort = null;
  }
  try {
    await Speech.stop();
  } catch {}
}

export async function speakWord(word: string): Promise<boolean> {
  if (currentAbort) {
    currentAbort.abort();
    currentAbort = null;
  }

  const text = word.trim();
  if (!text) return false;

  const abortController = new AbortController();
  currentAbort = abortController;
  const signal = abortController.signal;

  try {
    return await speakWithSystemTts(text, signal);
  } catch (e) {
    if (signal.aborted) return false;
    log.warn("speakWord failed:", text, e);
    return false;
  } finally {
    if (currentAbort === abortController) {
      currentAbort = null;
    }
  }
}

async function speakWithSystemTts(
  text: string,
  signal: AbortSignal,
): Promise<boolean> {
  await Speech.stop();
  if (signal.aborted) return false;

  return new Promise((resolve) => {
    let settled = false;
    const maxMs = Math.max(4000, text.length * 250);
    const timer = setTimeout(() => finish(true), maxMs);

    const finish = (ok: boolean) => {
      if (settled) return;
      settled = true;
      clearTimeout(timer);
      resolve(ok);
    };

    const onAbort = () => {
      signal.removeEventListener("abort", onAbort);
      Speech.stop();
      finish(false);
    };
    signal.addEventListener("abort", onAbort);

    Speech.speak(text, {
      language: "en-US",
      rate: TTS_SPEED,
      onDone: () => finish(true),
      onStopped: () => finish(false),
      onError: () => finish(false),
    });
  });
}

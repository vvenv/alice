import type { AudioPlayer } from "expo-audio";
import { setAudioModeAsync } from "expo-audio";
import * as Speech from "expo-speech";

import { createLogger } from "./logger";

const log = createLogger("TTS");

const TTS_SPEED = 0.9;
/** Approximate duration of assets/silent.wav (seconds). */
const SILENT_DURATION_S = 5;

// ---------------------------------------------------------------------------
// Module-level state (injected from React)
// ---------------------------------------------------------------------------

let wordPlayer: AudioPlayer | null = null;
let silentSrc: ReturnType<typeof require> | null = null;
let currentAbort: (() => void) | null = null;

export function setWordPlayer(player: AudioPlayer | null): void {
  wordPlayer = player;
}

export function setSilentSource(source: ReturnType<typeof require>): void {
  silentSrc = source;
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

function safeOp(fn: () => void): void {
  try {
    fn();
  } catch {}
}

/** Loop silent WAV quietly — keeps Android foreground service alive in background. */
export function playSilentKeepAlive(): void {
  if (!wordPlayer || !silentSrc) return;
  safeOp(() => {
    wordPlayer!.replace(silentSrc);
    wordPlayer!.loop = true;
    wordPlayer!.volume = 0.01;
    wordPlayer!.play();
  });
}

function waitForAbort(signal: AbortSignal): Promise<void> {
  if (signal.aborted) return Promise.resolve();
  return new Promise((resolve) => {
    const onAbort = () => {
      signal.removeEventListener("abort", onAbort);
      resolve();
    };
    signal.addEventListener("abort", onAbort);
  });
}

function waitForTimeout(ms: number, signal: AbortSignal): Promise<void> {
  if (ms <= 0) return Promise.resolve();
  return new Promise((resolve) => {
    const timer = setTimeout(() => {
      signal.removeEventListener("abort", onAbort);
      resolve();
    }, ms);
    const onAbort = () => {
      clearTimeout(timer);
      signal.removeEventListener("abort", onAbort);
      resolve();
    };
    signal.addEventListener("abort", onAbort);
  });
}

// ---------------------------------------------------------------------------
// Public API
// ---------------------------------------------------------------------------

export async function prefetchWordAudio(_word: string): Promise<string | null> {
  // System TTS does not need prefetching.
  return null;
}

export async function stopSpeech(): Promise<void> {
  if (currentAbort) {
    currentAbort();
    currentAbort = null;
  }
  try {
    await Speech.stop();
  } catch {}
}

/** Speak a dictation word using the platform en-US TTS engine. */
export async function speakWord(word: string): Promise<boolean> {
  await stopSpeech();

  const text = word.trim();
  if (!text) return false;

  // Keep the silent loop running so Android foreground service stays connected.
  playSilentKeepAlive();

  return new Promise((resolve) => {
    let settled = false;
    const maxMs = Math.max(4000, text.length * 250);
    const timer = setTimeout(() => finish(true), maxMs);

    const finish = (ok: boolean) => {
      if (settled) return;
      settled = true;
      clearTimeout(timer);
      currentAbort = null;
      playSilentKeepAlive();
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

export async function initAudio(): Promise<void> {
  try {
    await setAudioModeAsync({
      playsInSilentMode: true,
      shouldPlayInBackground: true,
      interruptionMode: "doNotMix",
      shouldRouteThroughEarpiece: false,
    });
  } catch (e) {
    log.warn("Failed to set audio mode:", e);
  }
}

/**
 * Wait `seconds` between words.
 *
 * - Foreground: setTimeout (accurate).
 * - Background: silent loop (loop=true) keeps the service alive; we also
 *   track currentTime wraps via native events when they arrive.
 * - If JS is frozen, the caller's AppState handler catches up on resume.
 */
export async function waitForSilentInterval(
  seconds: number,
  signal: AbortSignal,
): Promise<void> {
  if (!wordPlayer || seconds <= 0) return;

  playSilentKeepAlive();

  const deadline = Date.now() + seconds * 1000;
  let lastTime = 0;
  let elapsedS = 0;

  await Promise.race([
    waitForTimeout(seconds * 1000, signal),
    waitForAbort(signal),
    new Promise<void>((resolve) => {
      const sub = wordPlayer!.addListener("playbackStatusUpdate", (status) => {
        if (signal.aborted) {
          sub.remove();
          resolve();
          return;
        }

        if (status.currentTime + 0.5 < lastTime) {
          elapsedS += SILENT_DURATION_S;
        }
        lastTime = status.currentTime;

        if (elapsedS + status.currentTime >= seconds) {
          sub.remove();
          resolve();
          return;
        }

        if (Date.now() >= deadline) {
          sub.remove();
          resolve();
        }
      });
    }),
  ]);
}

import type { AudioPlayer } from "expo-audio";
import { setAudioModeAsync } from "expo-audio";
import * as FileSystem from "expo-file-system/legacy";

import { createLogger } from "./logger";

const log = createLogger("TTS");

/** Approximate duration of assets/silent.wav (seconds). */
const SILENT_DURATION_S = 5;

// ---------------------------------------------------------------------------
// Module-level state (injected from React)
// ---------------------------------------------------------------------------

let wordPlayer: AudioPlayer | null = null;
let silentSrc: ReturnType<typeof require> | null = null;
let currentAbort: AbortController | null = null;

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
// Cache helpers
// ---------------------------------------------------------------------------

const CACHE_DIR = `${FileSystem.cacheDirectory}tts/`;

async function ensureCacheDir(): Promise<void> {
  const dirInfo = await FileSystem.getInfoAsync(CACHE_DIR);
  if (!dirInfo.exists) {
    await FileSystem.makeDirectoryAsync(CACHE_DIR, { intermediates: true });
  }
}

function cachePath(word: string): string {
  const safe = word.replace(/[^a-zA-Z0-9_\- ]/g, "").trim() || "unknown";
  return `${CACHE_DIR}${encodeURIComponent(safe)}.mp3`;
}

export async function prefetchWordAudio(word: string): Promise<string | null> {
  const text = word.trim();
  if (!text) return null;

  await ensureCacheDir();
  const destPath = cachePath(text);
  const fileInfo = await FileSystem.getInfoAsync(destPath);
  if (fileInfo.exists) return destPath;

  try {
    return await downloadWordAudio(text, new AbortController().signal);
  } catch {
    return null;
  }
}

async function downloadWordAudio(
  word: string,
  signal: AbortSignal,
): Promise<string> {
  const ttsUrl = `https://translate.google.com/translate_tts?ie=UTF-8&client=tw-ob&tl=en&q=${encodeURIComponent(word)}`;
  const destPath = cachePath(word);

  const result = await FileSystem.downloadAsync(ttsUrl, destPath);

  if (signal.aborted) {
    FileSystem.deleteAsync(destPath, { idempotent: true }).catch(() => {});
    throw new DOMException("Aborted", "AbortError");
  }

  if (result.status !== 200) {
    FileSystem.deleteAsync(destPath, { idempotent: true }).catch(() => {});
    throw new Error(`TTS download failed with status ${result.status}`);
  }

  return destPath;
}

// ---------------------------------------------------------------------------
// Public API
// ---------------------------------------------------------------------------

export async function stopSpeech(): Promise<void> {
  if (currentAbort) {
    currentAbort.abort();
    currentAbort = null;
  }
  safeOp(() => wordPlayer?.pause());
}

export async function speakWord(word: string): Promise<boolean> {
  if (currentAbort) {
    currentAbort.abort();
    currentAbort = null;
  }

  const text = word.trim();
  if (!text) return false;
  if (!wordPlayer) {
    console.error("[TTS] wordPlayer is null");
    return false;
  }

  console.log("[TTS] speakWord:", text);

  const abortController = new AbortController();
  currentAbort = abortController;

  try {
    await ensureCacheDir();
    if (abortController.signal.aborted) return false;

    const destPath = cachePath(text);
    const fileInfo = await FileSystem.getInfoAsync(destPath);
    if (abortController.signal.aborted) return false;

    let audioUri: string;
    if (fileInfo.exists) {
      audioUri = destPath;
    } else {
      audioUri = await downloadWordAudio(text, abortController.signal);
    }
    if (abortController.signal.aborted) return false;

    safeOp(() => {
      wordPlayer!.loop = false;
      wordPlayer!.volume = 1.0;
      wordPlayer!.replace({ uri: audioUri });
      wordPlayer!.play();
    });
    if (abortController.signal.aborted) {
      playSilentKeepAlive();
      return false;
    }

    console.log("[TTS] playing:", text);

    const played = await new Promise<boolean>((resolve) => {
      let seenPlaying = false;
      let durationMs = 8000;

      const finish = (ok: boolean) => {
        sub.remove();
        clearTimeout(hardCap);
        clearTimeout(durationCap);
        resolve(ok);
      };

      const hardCap = setTimeout(() => finish(false), 15_000);

      const sub = wordPlayer!.addListener("playbackStatusUpdate", (status) => {
        if (abortController.signal.aborted) {
          finish(false);
          return;
        }
        if (status.duration > 0) {
          durationMs = Math.ceil(status.duration * 1000) + 300;
        }
        if (status.playing) {
          seenPlaying = true;
        }
        if (status.didJustFinish) {
          finish(true);
          return;
        }
        if (seenPlaying && !status.playing && status.isLoaded) {
          finish(true);
        }
      });

      const durationCap = setTimeout(() => {
        if (seenPlaying) finish(true);
      }, durationMs);
    });

    playSilentKeepAlive();
    return played;
  } catch (e) {
    if (abortController.signal.aborted) return false;
    console.error("[TTS] speakWord failed:", text, e);
    playSilentKeepAlive();
    return false;
  } finally {
    if (currentAbort === abortController) {
      currentAbort = null;
    }
  }
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

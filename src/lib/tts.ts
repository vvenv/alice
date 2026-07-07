import type { AudioPlayer } from "expo-audio";
import { setAudioModeAsync } from "expo-audio";
import * as FileSystem from "expo-file-system/legacy";

import { createLogger } from "./logger";

const log = createLogger("TTS");

// ---------------------------------------------------------------------------
// Module-level player (injected from React via setWordPlayer)
// ---------------------------------------------------------------------------

let wordPlayer: AudioPlayer | null = null;
let currentAbort: AbortController | null = null;

export function setWordPlayer(player: AudioPlayer | null): void {
  wordPlayer = player;
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

/**
 * Download the MP3 for `word` from Google Translate TTS and save it to the
 * cache directory.  Supports cancellation via `currentAbort`.
 */
async function downloadWordAudio(
  word: string,
  signal: AbortSignal,
): Promise<string> {
  const ttsUrl = `https://translate.google.com/translate_tts?ie=UTF-8&client=tw-ob&tl=en&q=${encodeURIComponent(word)}`;
  const destPath = cachePath(word);

  const result = await FileSystem.downloadAsync(ttsUrl, destPath);

  if (signal.aborted) {
    // Clean up the partially-downloaded file
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

/** Stop current TTS playback and cancel any in-flight download. */
export async function stopSpeech(): Promise<void> {
  if (currentAbort) {
    currentAbort.abort();
    currentAbort = null;
  }

  if (wordPlayer) {
    wordPlayer.pause();
    wordPlayer.seekTo(0);
  }
}

/**
 * Speak a dictation word aloud.
 *
 * Downloads the audio from Google Translate TTS on first use and caches it
 * locally.  Returns `true` when playback completes normally, `false` when
 * cancelled or on error.
 */
export async function speakWord(word: string): Promise<boolean> {
  await stopSpeech();

  const text = word.trim();
  if (!text) return false;

  if (!wordPlayer) {
    log.warn("speakWord called before setWordPlayer");
    return false;
  }

  const abortController = new AbortController();
  currentAbort = abortController;

  try {
    // 1. Ensure the cache directory exists
    await ensureCacheDir();
    if (abortController.signal.aborted) return false;

    // 2. Get or download the cached audio file
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

    // 3. Load and play the audio
    wordPlayer.replace({ uri: audioUri });
    wordPlayer.play();

    // 4. Wait for playback to finish
    const played = await new Promise<boolean>((resolve) => {
      const sub = wordPlayer!.addListener("playbackStatusUpdate", (status) => {
        if (abortController.signal.aborted) {
          sub.remove();
          resolve(false);
          return;
        }
        if (status.didJustFinish || (!status.playing && status.isLoaded)) {
          sub.remove();
          resolve(status.didJustFinish);
        }
      });
    });

    return played;
  } catch (e) {
    if (abortController.signal.aborted) return false;
    log.warn("speakWord error:", e);
    return false;
  } finally {
    if (currentAbort === abortController) {
      currentAbort = null;
    }
  }
}

/** Initialize audio session for background playback. */
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

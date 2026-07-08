import * as FileSystem from "expo-file-system/legacy";
import * as Speech from "expo-speech";

import { createLogger } from "./logger";

const log = createLogger("TTS");

const TTS_SPEED = 0.9;
const MIN_AUDIO_BYTES = 256;

let currentAbort: AbortController | null = null;

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

function ttsSources(word: string): string[] {
  const q = encodeURIComponent(word);
  return [
    `https://dict.youdao.com/dictvoice?audio=${q}&type=1`,
    `https://dict.youdao.com/dictvoice?audio=${q}&type=2`,
  ];
}

async function isValidAudioFile(path: string): Promise<boolean> {
  const info = await FileSystem.getInfoAsync(path);
  return info.exists && "size" in info && (info.size ?? 0) >= MIN_AUDIO_BYTES;
}

export async function prefetchWordAudio(word: string): Promise<string | null> {
  const text = word.trim();
  if (!text) return null;

  await ensureCacheDir();
  const destPath = cachePath(text);
  if (await isValidAudioFile(destPath)) return destPath;

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
  await ensureCacheDir();
  const destPath = cachePath(word);

  for (const url of ttsSources(word)) {
    if (signal.aborted) {
      throw new DOMException("Aborted", "AbortError");
    }

    try {
      const result = await FileSystem.downloadAsync(url, destPath);
      if (signal.aborted) {
        await FileSystem.deleteAsync(destPath, { idempotent: true });
        throw new DOMException("Aborted", "AbortError");
      }
      if (result.status === 200 && (await isValidAudioFile(destPath))) {
        return destPath;
      }
    } catch (e) {
      if (signal.aborted) throw e;
    }

    await FileSystem.deleteAsync(destPath, { idempotent: true });
  }

  throw new Error(`TTS download failed for "${word}"`);
}

// ---------------------------------------------------------------------------
// Speech — uses expo-speech (system TTS)
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
    // Try downloaded audio first via expo-speech (it can't play files, so we use system TTS)
    // Just download to cache for later, use system TTS for actual speech
    const destPath = cachePath(text);
    if (!(await isValidAudioFile(destPath))) {
      try {
        await downloadWordAudio(text, signal);
      } catch {
        // download failed — fall through to system TTS
      }
    }

    if (signal.aborted) return false;

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

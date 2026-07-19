import {
  createAudioPlayer,
  setAudioModeAsync,
  type AudioPlayer,
} from "expo-audio";
import { Directory, File, Paths } from "expo-file-system";
import * as Speech from "expo-speech";
import { Platform } from "react-native";

import { speakTextFromEntry } from "./dictation";
import { createLogger } from "./logger";

const log = createLogger("TTS");

const TTS_SPEED = 0.9;
const MIN_AUDIO_BYTES = 256;
const CACHE_DIR_NAME = "tts";
const DOWNLOAD_HEADERS = {
  "User-Agent":
    "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15",
};

let currentAbort: AbortController | null = null;
let wordPlayer: AudioPlayer | null = null;
let audioModeReady: Promise<void> | null = null;
const pendingDownloads = new Map<string, Promise<string | null>>();

// ---------------------------------------------------------------------------
// Audio session / player
// ---------------------------------------------------------------------------

function ensureAudioMode(): Promise<void> {
  if (!audioModeReady) {
    audioModeReady = setAudioModeAsync({
      playsInSilentMode: true,
      shouldPlayInBackground: true,
      interruptionMode: "doNotMix",
      shouldRouteThroughEarpiece: false,
    }).catch((e) => {
      log.warn("Failed to set audio mode:", e);
    });
  }
  return audioModeReady;
}

function getPlayer(): AudioPlayer {
  if (!wordPlayer) {
    wordPlayer = createAudioPlayer(null);
  }
  return wordPlayer;
}

function canUseDiskCache(): boolean {
  // New FileSystem APIs are stubs on web and cannot persist audio files.
  return Platform.OS !== "web";
}

// ---------------------------------------------------------------------------
// Youdao download + local cache
// ---------------------------------------------------------------------------

function getCacheDir(): Directory {
  return new Directory(Paths.cache, CACHE_DIR_NAME);
}

function ensureCacheDir(): Directory {
  const dir = getCacheDir();
  if (!dir.exists) {
    dir.create({ intermediates: true, idempotent: true });
  }
  return dir;
}

function cacheFileFor(text: string): File {
  const safe =
    encodeURIComponent(text.trim().toLowerCase()).replace(/%/g, "_") ||
    "unknown";
  return new File(ensureCacheDir(), `${safe}.mp3`);
}

function cacheKeyFor(text: string): string {
  return text.trim().toLowerCase();
}

function youdaoUrls(text: string): string[] {
  const q = encodeURIComponent(text);
  // Prefer US (type=2), then UK (type=1)
  return [
    `https://dict.youdao.com/dictvoice?audio=${q}&type=2`,
    `https://dict.youdao.com/dictvoice?audio=${q}&type=1`,
  ];
}

function isValidCachedFile(file: File): boolean {
  return file.exists && file.size >= MIN_AUDIO_BYTES;
}

async function downloadYoudaoAudio(
  text: string,
  signal: AbortSignal,
): Promise<string | null> {
  if (!canUseDiskCache()) return null;

  const dest = cacheFileFor(text);
  if (isValidCachedFile(dest)) return dest.uri;

  for (const url of youdaoUrls(text)) {
    if (signal.aborted) return null;

    try {
      if (dest.exists) {
        try {
          dest.delete();
        } catch {}
      }

      const downloaded = await File.downloadFileAsync(url, dest, {
        idempotent: true,
        headers: DOWNLOAD_HEADERS,
        signal,
      });

      if (signal.aborted) {
        try {
          downloaded.delete();
        } catch {}
        return null;
      }

      if (downloaded.size >= MIN_AUDIO_BYTES) {
        return downloaded.uri;
      }

      try {
        downloaded.delete();
      } catch {}
    } catch (e) {
      if (signal.aborted) return null;
      log.debug("Youdao download failed:", url, e);
    }
  }

  return null;
}

function getReadyYoudaoUri(text: string): string | null {
  if (!canUseDiskCache()) return null;
  const cached = cacheFileFor(text);
  return isValidCachedFile(cached) ? cached.uri : null;
}

export async function prefetchWordAudio(word: string): Promise<string | null> {
  const text = speakTextFromEntry(word);
  if (!text || !canUseDiskCache()) return null;

  const ready = getReadyYoudaoUri(text);
  if (ready) return ready;

  const key = cacheKeyFor(text);
  const pending = pendingDownloads.get(key);
  if (pending) return pending;

  const download = downloadYoudaoAudio(
    text,
    new AbortController().signal,
  ).catch(() => null);
  pendingDownloads.set(key, download);

  try {
    return await download;
  } finally {
    if (pendingDownloads.get(key) === download) {
      pendingDownloads.delete(key);
    }
  }
}

export async function clearTtsCache(): Promise<number> {
  if (!canUseDiskCache()) return 0;

  const dir = getCacheDir();
  if (!dir.exists) return 0;

  let count = 0;
  try {
    for (const entry of dir.list()) {
      if (entry instanceof File) count += 1;
    }
    dir.delete();
  } catch (e) {
    log.warn("clearTtsCache failed:", e);
    throw e;
  }
  return count;
}

// ---------------------------------------------------------------------------
// Playback
// ---------------------------------------------------------------------------

export async function stopSpeech(): Promise<void> {
  if (currentAbort) {
    currentAbort.abort();
    currentAbort = null;
  }
  try {
    wordPlayer?.pause();
  } catch {}
  try {
    await Speech.stop();
  } catch {}
}

async function playAudioUri(
  uri: string,
  signal: AbortSignal,
): Promise<boolean> {
  await ensureAudioMode();
  if (signal.aborted) return false;

  try {
    await Speech.stop();
  } catch {}

  const player = getPlayer();
  try {
    player.pause();
  } catch {}

  return new Promise((resolve) => {
    let settled = false;
    let seenPlaying = false;
    let durationCap: ReturnType<typeof setTimeout> | null = null;

    const finish = (ok: boolean) => {
      if (settled) return;
      settled = true;
      clearTimeout(hardCap);
      if (durationCap) clearTimeout(durationCap);
      sub.remove();
      signal.removeEventListener("abort", onAbort);
      resolve(ok);
    };

    const onAbort = () => {
      try {
        player.pause();
      } catch {}
      finish(false);
    };
    signal.addEventListener("abort", onAbort);

    const hardCap = setTimeout(() => finish(seenPlaying), 15_000);

    const sub = player.addListener("playbackStatusUpdate", (status) => {
      if (signal.aborted) {
        finish(false);
        return;
      }
      if (status.playing) {
        seenPlaying = true;
        if (!durationCap && status.duration > 0) {
          const ms = Math.ceil(status.duration * 1000) + 400;
          durationCap = setTimeout(() => finish(true), ms);
        }
      }
      if (status.didJustFinish) {
        finish(true);
      }
    });

    try {
      player.loop = false;
      player.volume = 1;
      player.replace({ uri });
      player.play();
    } catch (e) {
      log.warn("Audio play failed:", e);
      finish(false);
    }
  });
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
      signal.removeEventListener("abort", onAbort);
      resolve(ok);
    };

    const onAbort = () => {
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

/**
 * Use free Youdao dictionary audio only when it has already been cached.
 * Never wait for a download when playback starts; fall back to system TTS
 * immediately instead. Entries like `you're = you are` speak the left side.
 */
export async function speakWord(word: string): Promise<boolean> {
  if (currentAbort) {
    currentAbort.abort();
    currentAbort = null;
  }

  const text = speakTextFromEntry(word);
  if (!text) return false;

  const abortController = new AbortController();
  currentAbort = abortController;
  const signal = abortController.signal;

  try {
    const uri = getReadyYoudaoUri(text);

    if (uri) {
      const ok = await playAudioUri(uri, signal);
      if (ok || signal.aborted) return ok;
      log.debug("Youdao playback failed, falling back to system TTS:", text);
    }

    return await speakWithSystemTts(text, signal);
  } catch (e) {
    if (signal.aborted) return false;
    log.warn("speakWord failed:", text, e);
    try {
      return await speakWithSystemTts(text, signal);
    } catch {
      return false;
    }
  } finally {
    if (currentAbort === abortController) {
      currentAbort = null;
    }
  }
}

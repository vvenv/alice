import AsyncStorage from "@react-native-async-storage/async-storage";
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
import { buildChatCompletionsUrl } from "./ocrConfig";
import { DEFAULT_SPEECH_RATE } from "./storage";
import {
  buildSpeechUrl,
  getCachedTtsProviderConfig,
  getCachedTtsSource,
  isTtsProviderConfigSet,
  loadTtsSettings,
  type TtsProviderConfig,
} from "./ttsConfig";

const log = createLogger("TTS");

let currentSpeechRate = DEFAULT_SPEECH_RATE;
const MIN_AUDIO_BYTES = 256;
const CACHE_DIR_NAME = "tts";
const DOWNLOAD_HEADERS = {
  "User-Agent":
    "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15",
};

export type SpeechLang = "en-US" | "zh-CN";

// Preference: also read the Chinese meaning after the English word.
const READ_TRANSLATION_KEY = "alice_read_translation";
let readTranslation = false;
let readTranslationLoaded = false;

function ensureReadTranslationLoaded(): void {
  if (readTranslationLoaded) return;
  readTranslationLoaded = true;
  AsyncStorage.getItem(READ_TRANSLATION_KEY)
    .then((v) => {
      if (v === "on") readTranslation = true;
    })
    .catch(() => {});
}
ensureReadTranslationLoaded();

export function isReadTranslationEnabled(): boolean {
  return readTranslation;
}

export async function loadReadTranslation(): Promise<boolean> {
  try {
    const v = await AsyncStorage.getItem(READ_TRANSLATION_KEY);
    readTranslation = v === "on";
  } catch {
    // keep current value
  }
  return readTranslation;
}

export function setReadTranslationEnabled(value: boolean): void {
  readTranslation = value;
  AsyncStorage.setItem(READ_TRANSLATION_KEY, value ? "on" : "off").catch(
    () => {},
  );
}

// Eagerly load the TTS source setting so playback picks the right provider.
void loadTtsSettings().catch(() => {});
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
  if (!text) return null;

  const provider = getActiveProviderConfig();
  if (provider) return prefetchProviderAudio(text, provider);

  if (!canUseDiskCache()) return null;

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
  for (const url of memoryClips.values()) {
    try {
      URL.revokeObjectURL(url);
    } catch {}
  }
  memoryClips.clear();

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
// OpenAI-compatible provider download + local cache
// ---------------------------------------------------------------------------

const PROVIDER_WAIT_MS = 1500;

const B64_ALPHABET = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";
const B64_REV: Record<string, number> = {};
for (let i = 0; i < B64_ALPHABET.length; i += 1) {
  B64_REV[B64_ALPHABET[i]!] = i;
}

/**
 * Decode base64 audio without relying on atob availability (differs across
 * Hermes/web). Tolerates whitespace and data-URL padding.
 */
function decodeBase64(input: string): Uint8Array<ArrayBuffer> {
  const clean = input.replace(/[^A-Za-z0-9+/=]/g, "");
  const out = new Uint8Array(new ArrayBuffer(Math.floor((clean.length * 3) / 4)));
  let buffer = 0;
  let bits = 0;
  let pos = 0;
  for (let i = 0; i < clean.length; i += 1) {
    const ch = clean[i]!;
    if (ch === "=") break;
    buffer = (buffer << 6) | (B64_REV[ch] ?? 0);
    bits += 6;
    if (bits >= 8) {
      bits -= 8;
      out[pos++] = (buffer >> bits) & 0xff;
    }
  }
  return out.subarray(0, pos);
}

/** 汉字检测：provider 有中/英两个 voice 时按朗读内容选择。 */
const CJK_RE = /[\u4e00-\u9fff]/;

function providerVoiceFor(cfg: TtsProviderConfig, text: string): string {
  return (CJK_RE.test(text) ? cfg.voiceZh : cfg.voiceEn).trim();
}

function providerFormatFor(cfg: TtsProviderConfig): string {
  if (cfg.api === "chat") return "wav";
  return (cfg.responseFormat ?? "mp3").trim().toLowerCase() || "mp3";
}

const memoryClips = new Map<string, string>();
const pendingProviderDownloads = new Map<string, Promise<string | null>>();

/**
 * Stable 8-hex hash of provider/model/voice/format/speech-rate: changing any
 * of them regenerates clips instead of replaying stale audio.
 */
function providerClipHash(cfg: TtsProviderConfig, text: string): string {
  const rateQ = Math.round(currentSpeechRate * 10);
  const seed = `${cfg.api}|${cfg.model}|${providerVoiceFor(cfg, text)}|${providerFormatFor(cfg)}|${rateQ}`;
  let h = 5381;
  for (let i = 0; i < seed.length; i += 1) {
    h = ((h << 5) + h + seed.charCodeAt(i)) | 0;
  }
  return (h >>> 0).toString(16).padStart(8, "0");
}

function providerClipFileFor(text: string, cfg: TtsProviderConfig): File {
  const trimmed = text.trim().toLowerCase();
  const safe = encodeURIComponent(trimmed).replace(/%/g, "_") || "unknown";
  const name = `${safe}.${providerClipHash(cfg, text)}.${providerFormatFor(cfg)}`;
  return new File(ensureCacheDir(), name);
}

function getReadyProviderClip(
  text: string,
  cfg: TtsProviderConfig,
): string | null {
  if (canUseDiskCache()) {
    const file = providerClipFileFor(text, cfg);
    return isValidCachedFile(file) ? file.uri : null;
  }
  const key = `${providerClipHash(cfg, text)}:${cacheKeyFor(text)}`;
  return memoryClips.get(key) ?? null;
}

async function apiErrorMessage(res: Response): Promise<string> {
  try {
    const json = (await res.json()) as { error?: { message?: unknown } };
    const message = json?.error?.message;
    return typeof message === "string" && message
      ? message
      : `HTTP ${res.status}`;
  } catch {
    return `HTTP ${res.status}`;
  }
}

async function downloadProviderAudio(
  text: string,
  cfg: TtsProviderConfig,
  signal: AbortSignal,
): Promise<string | null> {
  const headers = {
    "Content-Type": "application/json",
    Authorization: `Bearer ${cfg.apiKey}`,
  };
  const voice = providerVoiceFor(cfg, text);
  let bytes: Uint8Array<ArrayBuffer>;

  try {
    let res: Response;
    if (cfg.api === "chat") {
      // MiMo-style: synthesis via chat.completions, base64 audio in the reply.
      const audio: Record<string, string> = { format: "wav" };
      if (voice) audio.voice = voice;
      res = await fetch(buildChatCompletionsUrl(cfg.baseUrl), {
        method: "POST",
        headers,
        signal,
        body: JSON.stringify({
          model: cfg.model,
          messages: [{ role: "assistant", content: text }],
          audio,
        }),
      });
      if (!res.ok) throw new Error(await apiErrorMessage(res));
      const json = (await res.json()) as {
        choices?: Array<{ message?: { audio?: { data?: unknown } } }>;
      };
      const data = json.choices?.[0]?.message?.audio?.data;
      if (typeof data !== "string" || data.length === 0) {
        throw new Error("响应中没有音频数据");
      }
      bytes = decodeBase64(data);
    } else {
      // Standard /audio/speech: binary audio in the response body.
      const format = providerFormatFor(cfg);
      const body: Record<string, unknown> = {
        model: cfg.model,
        input: text,
        response_format: format,
        speed: Math.min(4, Math.max(0.25, currentSpeechRate)),
      };
      if (voice) body.voice = voice;
      res = await fetch(buildSpeechUrl(cfg.baseUrl), {
        method: "POST",
        signal,
        body: JSON.stringify(body),
      });
      if (!res.ok) throw new Error(await apiErrorMessage(res));
      bytes = new Uint8Array(await res.arrayBuffer());
    }
  } catch (e) {
    if (!signal.aborted) log.debug("TTS provider request failed:", text, e);
    return null;
  }

  if (signal.aborted || bytes.byteLength < MIN_AUDIO_BYTES) return null;

  if (canUseDiskCache()) {
    const dest = providerClipFileFor(text, cfg);
    try {
      if (dest.exists) dest.delete();
      dest.write(bytes);
      return dest.uri;
    } catch (e) {
      log.debug("TTS provider cache write failed:", text, e);
      return null;
    }
  }

  // Web: no persistent cache dir here; keep the clip as a blob URL.
  const blobUrl = URL.createObjectURL(
    new Blob([bytes], {
      type: providerFormatFor(cfg) === "wav" ? "audio/wav" : "audio/mpeg",
    }),
  );
  memoryClips.set(
    `${providerClipHash(cfg, text)}:${cacheKeyFor(text)}`,
    blobUrl,
  );
  return blobUrl;
}

function prefetchProviderAudio(
  text: string,
  cfg: TtsProviderConfig,
): Promise<string | null> {
  const ready = getReadyProviderClip(text, cfg);
  if (ready) return Promise.resolve(ready);

  const key = `${providerClipHash(cfg, text)}:${cacheKeyFor(text)}`;
  const pending = pendingProviderDownloads.get(key);
  if (pending) return pending;

  const download = downloadProviderAudio(
    text,
    cfg,
    new AbortController().signal,
  ).catch(() => null);
  pendingProviderDownloads.set(key, download);

  void download.then(() => {
    if (pendingProviderDownloads.get(key) === download) {
      pendingProviderDownloads.delete(key);
    }
  });

  return download;
}

/**
 * Bounded wait for an in-flight generation. Eats the "same word spoken twice
 * with different voices" race: the first playback may wait up to 1.5 s for
 * the LLM clip instead of instantly using the system voice; any miss still
 * falls back to system TTS.
 */
async function waitForProviderClip(
  text: string,
  cfg: TtsProviderConfig,
): Promise<string | null> {
  const pending = prefetchProviderAudio(text, cfg);
  await Promise.race([
    pending,
    new Promise<null>((resolve) =>
      setTimeout(() => resolve(null), PROVIDER_WAIT_MS),
    ),
  ]);
  return getReadyProviderClip(text, cfg);
}

function getActiveProviderConfig(): TtsProviderConfig | null {
  if (getCachedTtsSource() !== "custom") return null;
  const cfg = getCachedTtsProviderConfig();
  return cfg && isTtsProviderConfigSet(cfg) ? cfg : null;
}

export async function testTtsConfig(cfg: TtsProviderConfig): Promise<void> {
  let played = false;
  for (const sample of ["apple", "苹果，一种很常见的水果"]) {
    const uri = await downloadProviderAudio(
      sample,
      cfg,
      new AbortController().signal,
    );
    if (!uri) {
      throw new Error("无法生成试听音频，请检查接口地址、密钥和模型");
    }
    const ok = await playAudioUri(uri, new AbortController().signal).catch(
      () => false,
    );
    if (ok) played = true;
  }
  if (!played) throw new Error("音频已生成，但本机播放失败");
}

// ---------------------------------------------------------------------------
// Playback
// ---------------------------------------------------------------------------

export function setSpeechRate(rate: number): void {
  currentSpeechRate = rate;
}

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
  lang: SpeechLang,
): Promise<boolean> {
  await Speech.stop();
  if (signal.aborted) return false;

  const { promise, resolve } = Promise.withResolvers<boolean>();
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
    language: lang,
    rate: currentSpeechRate,
    onDone: () => finish(true),
    onStopped: () => finish(false),
    onError: () => finish(false),
  });

  return promise;
}

/**
 * Play the selected source: a custom OpenAI-compatible provider (bounded wait
 * for the first generation so one word is not spoken in two voices), Youdao
 * dictionary audio when already cached, or system TTS. Entries like
 * `you're = you are` speak the left side.
 */
export async function speakWord(
  word: string,
  opts?: { lang?: SpeechLang },
): Promise<boolean> {
  if (currentAbort) {
    currentAbort.abort();
    currentAbort = null;
  }

  const text = speakTextFromEntry(word);
  if (!text) return false;

  const lang = opts?.lang ?? (CJK_RE.test(text) ? "zh-CN" : "en-US");
  const abortController = new AbortController();
  currentAbort = abortController;
  const signal = abortController.signal;

  try {
    const provider = getActiveProviderConfig();
    const uri = provider
      ? getReadyProviderClip(text, provider) ??
        (await waitForProviderClip(text, provider))
      : getReadyYoudaoUri(text);

    if (uri) {
      const ok = await playAudioUri(uri, signal);
      if (ok || signal.aborted) return ok;
      log.debug(
        provider ? "Provider" : "Youdao",
        "playback failed, falling back to system TTS:",
        text,
      );
    }

    return await speakWithSystemTts(text, signal, lang);
  } catch (e) {
    if (signal.aborted) return false;
    log.warn("speakWord failed:", text, e);
    try {
      return await speakWithSystemTts(text, signal, lang);
    } catch {
      return false;
    }
  } finally {
    if (currentAbort === abortController) {
      currentAbort = null;
    }
  }
}

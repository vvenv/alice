import { Platform } from "react-native";
import { createAudioPlayer, AudioPlayer, setAudioModeAsync } from "expo-audio";
import { Paths, File, Directory, EncodingType } from "expo-file-system";

import { config } from "./config";
import { createLogger } from "./logger";

const TTS_SPEED = 0.9;
const TTS_URL = `${config.zhipuBaseUrl}/audio/speech`;
const IS_WEB = Platform.OS === "web";
const TTS_CACHE_DIR = IS_WEB ? "" : `${Paths.cache.uri}tts_cache/`;

const log = createLogger("TTS");

export function ttsInputText(text: string): string {
  const word = text.trim();
  if (/^[a-zA-Z][a-zA-Z'-]*$/.test(word)) {
    return `"${word}"`;
  }
  return word;
}

function ttsCacheKey(text: string, voice: string): string {
  return `${ttsInputText(text).toLowerCase()}|${voice}|${TTS_SPEED}`;
}

/** Ensure cache directory exists. No-op on web. */
async function ensureCacheDir(): Promise<void> {
  if (IS_WEB) return;
  const dir = new Directory(TTS_CACHE_DIR);
  if (!dir.exists) {
    dir.create({ intermediates: true });
  }
}

/** Convert an ArrayBuffer to a base64 string. */
function arrayBufferToBase64(buffer: ArrayBuffer): string {
  const bytes = new Uint8Array(buffer);
  const chunkSize = 0x8000;
  let base64 = "";
  for (let i = 0; i < bytes.length; i += chunkSize) {
    const chunk = bytes.subarray(i, i + chunkSize);
    base64 += String.fromCharCode.apply(null, Array.from(chunk));
  }
  return btoa(base64);
}

/** Fetch TTS audio directly from Zhipu, caching to file system on native. Returns a URI. */
async function fetchTtsAudio(
  text: string,
  voice: string,
): Promise<string | null> {
  const key = ttsCacheKey(text, voice);
  const cachePath = IS_WEB ? "" : `${TTS_CACHE_DIR}${encodeURIComponent(key)}.mp3`;

  // Check cache first (native only)
  if (!IS_WEB) {
    try {
      const file = new File(cachePath);
      if (file.exists) return cachePath;
    } catch {
      // ignore cache errors
    }
  }

  try {
    await ensureCacheDir();

    const response = await fetch(TTS_URL, {
      method: "POST",
      headers: {
        Authorization: `Bearer ${config.zhipuApiKey}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({
        model: config.ttsModel,
        input: ttsInputText(text),
        voice,
        speed: TTS_SPEED,
        volume: 1.0,
        response_format: "wav",
      }),
    });

    if (!response.ok) {
      log.warn(`Zhipu TTS returned ${response.status} for "${text}"`);
      return null;
    }

    const arrayBuffer = await response.arrayBuffer();
    const blob = new Blob([arrayBuffer], { type: "audio/wav" });
    const dataUri = URL.createObjectURL(blob);

    if (!IS_WEB) {
      const base64 = arrayBufferToBase64(arrayBuffer);
      new File(cachePath).write(base64, { encoding: EncodingType.Base64 });
      return cachePath;
    }

    return dataUri;
  } catch (err) {
    log.warn(`Fetch failed for "${text}":`, err);
    return null;
  }
}

// ── Playback state ──
let currentPlayer: AudioPlayer | null = null;
let currentAbort: (() => void) | null = null;

export async function stopSpeech(): Promise<void> {
  if (currentAbort) {
    currentAbort();
    currentAbort = null;
  }
  if (currentPlayer) {
    try {
      currentPlayer.pause();
      currentPlayer.remove();
    } catch {
      // ignore
    }
    currentPlayer = null;
  }
}

/**
 * Speak a word using Zhipu TTS (with local file cache).
 * Returns false if the TTS service is unreachable or an error occurs.
 */
export async function speakWord(
  word: string,
  voice: string = "6f62ac26-895b-512e-990f-7a0bbf06e75e",
): Promise<boolean> {
  await stopSpeech();

  try {
    const audioUri = await fetchTtsAudio(word, voice);
    if (!audioUri) {
      log.warn(`Failed to fetch audio for: ${word}`);
      return false;
    }

    const player = createAudioPlayer({ uri: audioUri });

    currentPlayer = player;

    return new Promise<boolean>((resolve) => {
      let settled = false;

      currentAbort = () => {
        if (settled) return;
        settled = true;
        resolve(false);
      };

      player.addListener("playbackStatusUpdate", (status) => {
        if (status.error || settled) {
          if (!settled && status.error) {
            settled = true;
            currentAbort = null;
            currentPlayer = null;
            log.warn(`Playback error for "${word}":`, status.error);
            resolve(false);
          }
          return;
        }
        if (status.didJustFinish) {
          settled = true;
          currentAbort = null;
          currentPlayer = null;
          resolve(true);
        }
      });

      player.play();
    });
  } catch (err) {
    log.warn(`Unexpected error for "${word}":`, err);
    return false;
  }
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

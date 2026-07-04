import { Audio } from "expo-av";
import * as FileSystem from "expo-file-system";

import { apiFetch } from "./api";

const TTS_SPEED = 0.9;
const TTS_CACHE_DIR = `${FileSystem.documentDirectory}tts_cache/`;

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

/** Ensure cache directory exists. */
async function ensureCacheDir(): Promise<void> {
  const dirInfo = await FileSystem.getInfoAsync(TTS_CACHE_DIR);
  if (!dirInfo.exists) {
    await FileSystem.makeDirectoryAsync(TTS_CACHE_DIR, {
      intermediates: true,
    });
  }
}

/** Convert an ArrayBuffer to a base64 string. */
function arrayBufferToBase64(buffer: ArrayBuffer): string {
  const bytes = new Uint8Array(buffer);
  const chunkSize = 0x8000; // 32 KB chunks to avoid call-stack overflow on large files
  let base64 = "";
  for (let i = 0; i < bytes.length; i += chunkSize) {
    const chunk = bytes.subarray(i, i + chunkSize);
    base64 += String.fromCharCode.apply(null, Array.from(chunk));
  }
  return btoa(base64);
}

/** Fetch TTS audio from server, caching to file system. Returns local file URI. */
async function fetchTtsAudio(
  text: string,
  voice: string,
): Promise<string | null> {
  const key = ttsCacheKey(text, voice);
  const cachePath = `${TTS_CACHE_DIR}${encodeURIComponent(key)}.mp3`;

  // Check cache first
  try {
    const info = await FileSystem.getInfoAsync(cachePath);
    if (info.exists) return cachePath;
  } catch {
    // ignore cache errors
  }

  try {
    await ensureCacheDir();

    const response = await apiFetch("/api/tts/speech", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ text: ttsInputText(text), voice, speed: TTS_SPEED }),
    });

    if (!response.ok) {
      console.warn(`[TTS] Server returned ${response.status} for "${text}"`);
      return null;
    }

    // Use arrayBuffer instead of blob — blob+FileReader silently fails in React Native.
    const arrayBuffer = await response.arrayBuffer();
    const base64 = arrayBufferToBase64(arrayBuffer);

    await FileSystem.writeAsStringAsync(cachePath, base64, {
      encoding: FileSystem.EncodingType.Base64,
    });

    return cachePath;
  } catch (err) {
    console.warn(`[TTS] Fetch failed for "${text}":`, err);
    return null;
  }
}

// ── Playback state ──
let currentSound: Audio.Sound | null = null;
let currentAbort: (() => void) | null = null;

export async function stopSpeech(): Promise<void> {
  if (currentAbort) {
    currentAbort();
    currentAbort = null;
  }
  if (currentSound) {
    try {
      await currentSound.stopAsync();
      await currentSound.unloadAsync();
    } catch {
      // ignore
    }
    currentSound = null;
  }
}

/**
 * Speak a word using server TTS (with local file cache).
 * Returns false if the TTS server is unreachable or an error occurs.
 */
export async function speakWord(
  word: string,
  voice: string = "6f62ac26-895b-512e-990f-7a0bbf06e75e",
): Promise<boolean> {
  await stopSpeech();

  try {
    const audioUri = await fetchTtsAudio(word, voice);
    if (!audioUri) {
      console.warn(`[TTS] Failed to fetch audio for: ${word}`);
      return false;
    }

    const { sound } = await Audio.Sound.createAsync(
      { uri: audioUri },
      { shouldPlay: false },
    );

    currentSound = sound;

    return new Promise<boolean>((resolve) => {
      let settled = false;

      currentAbort = () => {
        if (settled) return;
        settled = true;
        resolve(false);
      };

      sound.setOnPlaybackStatusUpdate((status) => {
        if (!status.isLoaded || settled) return;
        if (status.didJustFinish) {
          settled = true;
          currentAbort = null;
          currentSound = null;
          resolve(true);
        }
      });

      sound.playAsync().catch((err) => {
        console.warn(`[TTS] Playback error for "${word}":`, err);
        if (settled) return;
        settled = true;
        currentAbort = null;
        currentSound = null;
        resolve(false);
      });
    });
  } catch (err) {
    console.warn(`[TTS] Unexpected error for "${word}":`, err);
    return false;
  }
}

/** Initialize audio session for playback. */
export async function initAudio(): Promise<void> {
  try {
    await Audio.setAudioModeAsync({
      allowsRecordingIOS: false,
      playsInSilentModeIOS: true,
      staysActiveInBackground: false,
      shouldDuckAndroid: true,
      playThroughEarpieceAndroid: false,
    });
  } catch (e) {
    console.warn("[Audio] Failed to set audio mode:", e);
  }
}

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

    if (!response.ok) return null;

    const blob = await response.blob();
    const reader = new FileReader();
    const base64 = await new Promise<string>((resolve, reject) => {
      reader.onload = () => {
        const result = reader.result as string;
        const commaIndex = result.indexOf(",");
        resolve(commaIndex >= 0 ? result.slice(commaIndex + 1) : result);
      };
      reader.onerror = () => reject(new Error("读取音频失败"));
      reader.readAsDataURL(blob);
    });

    await FileSystem.writeAsStringAsync(cachePath, base64, {
      encoding: FileSystem.EncodingType.Base64,
    });

    return cachePath;
  } catch {
    return null;
  }
}

// Track currently playing sound for stop/cancel
let currentSound: Audio.Sound | null = null;
let speakResolve: (() => void) | null = null;

function settleSpeak(): void {
  if (!speakResolve) return;
  const resolve = speakResolve;
  speakResolve = null;
  resolve();
}

export async function stopSpeech(): Promise<void> {
  if (currentSound) {
    try {
      await currentSound.stopAsync();
      await currentSound.unloadAsync();
    } catch {
      // ignore
    }
    currentSound = null;
  }
  settleSpeak();
}

let currentPlayId = 0;

/**
 * Speak a word using server TTS (with local file cache).
 * Falls back to returning false so the caller can use system TTS if available.
 */
export async function speakWord(
  word: string,
  voice: string = "6f62ac26-895b-512e-990f-7a0bbf06e75e",
): Promise<boolean> {
  await stopSpeech();

  const playId = ++currentPlayId;

  try {
    const audioUri = await fetchTtsAudio(word, voice);
    if (playId !== currentPlayId) return false;
    if (!audioUri) return false;

    const { sound } = await Audio.Sound.createAsync(
      { uri: audioUri },
      { shouldPlay: false },
    );
    if (playId !== currentPlayId) {
      await sound.unloadAsync();
      return false;
    }

    currentSound = sound;

    await new Promise<void>((resolve) => {
      speakResolve = () => {
        resolve();
      };

      sound.setOnPlaybackStatusUpdate((status) => {
        if (!status.isLoaded) return;
        if (status.didJustFinish) {
          currentSound = null;
          settleSpeak();
        }
      });

      sound.playAsync().catch(() => settleSpeak());
    });

    return true;
  } catch {
    return false;
  }
}

/** Initialize audio session for playback. */
export async function initAudio(): Promise<void> {
  try {
    await Audio.setAudioModeAsync({
      playsInSilentModeIOS: true,
      staysActiveInBackground: false,
      shouldDuckAndroid: true,
    });
  } catch {
    // non-critical
  }
}

import type { OcrWordsRequest, OcrWordsResponse } from "@alice/shared";

import { apiFetch } from "./api";

const TTS_SPEED = 0.9;
const TTS_CACHE_DB = "alice_tts_cache";
const TTS_CACHE_STORE = "audio";
/** Bumped when TTS input formatting changes (e.g. English-word quoting). */
const TTS_CACHE_VERSION = 2;
const TTS_VOICE_KEY = "dictation_tts_voice";

export type VoiceOption = { id: string; label: string };

/**
 * Cloned from textbook audio `Pronunciation_Listen_and_circle.mp3`
 * (account-bound Zhipu voice id).
 */
export const EXAM_TTS_VOICE = "6f62ac26-895b-512e-990f-7a0bbf06e75e";

/** Built-in voices: exam-style default + GLM-TTS system voices. */
export const SYSTEM_TTS_VOICES: VoiceOption[] = [
  { id: EXAM_TTS_VOICE, label: "考试" },
  { id: "tongtong", label: "彤彤" },
  { id: "chuichui", label: "锤锤" },
  { id: "xiaochen", label: "小陈" },
  // { id: "jam", label: "Jam" },
  // { id: "kazi", label: "Kazi" },
  // { id: "douji", label: "Douji" },
  // { id: "luodo", label: "Luodo" },
];

export const DEFAULT_TTS_VOICE = EXAM_TTS_VOICE;

const SYSTEM_VOICE_IDS = new Set(SYSTEM_TTS_VOICES.map((v) => v.id));

export function parseWords(text: string): string[] {
  return text
    .split(/[\n\r,，;；\t]+/)
    .flatMap((part) => part.trim().split(/\s+/))
    .map((word) => word.trim())
    .filter((word) => word.length > 0);
}

export function loadTtsVoice(): string {
  try {
    const stored = localStorage.getItem(TTS_VOICE_KEY);
    if (stored && SYSTEM_VOICE_IDS.has(stored)) return stored;
  } catch {
    // ignore
  }
  return DEFAULT_TTS_VOICE;
}

export function saveTtsVoice(voice: string): void {
  localStorage.setItem(TTS_VOICE_KEY, voice);
}

/**
 * GLM-TTS is Chinese-first and may translate isolated English words
 * (e.g. grape →「葡萄」). Quoting forces English reading.
 */
function ttsInputText(text: string): string {
  const word = text.trim();
  if (/^[a-zA-Z][a-zA-Z'-]*$/.test(word)) {
    return `"${word}"`;
  }
  return word;
}

function ttsCacheKey(text: string, voice: string): string {
  return `${ttsInputText(text).toLowerCase()}|${voice}|${TTS_SPEED}`;
}

function openTtsCache(): Promise<IDBDatabase> {
  return new Promise((resolve, reject) => {
    const request = indexedDB.open(TTS_CACHE_DB, TTS_CACHE_VERSION);
    request.onupgradeneeded = () => {
      const db = request.result;
      if (!db.objectStoreNames.contains(TTS_CACHE_STORE)) {
        db.createObjectStore(TTS_CACHE_STORE);
      }
    };
    request.onsuccess = () => resolve(request.result);
    request.onerror = () =>
      reject(request.error ?? new Error("打开音频缓存失败"));
  });
}

async function getCachedTtsAudio(key: string): Promise<Blob | null> {
  try {
    const db = await openTtsCache();
    try {
      return await new Promise((resolve, reject) => {
        const tx = db.transaction(TTS_CACHE_STORE, "readonly");
        const request = tx.objectStore(TTS_CACHE_STORE).get(key);
        request.onsuccess = () => {
          const value = request.result;
          resolve(value instanceof Blob ? value : null);
        };
        request.onerror = () =>
          reject(request.error ?? new Error("读取音频缓存失败"));
      });
    } finally {
      db.close();
    }
  } catch {
    return null;
  }
}

async function putCachedTtsAudio(key: string, blob: Blob): Promise<void> {
  try {
    const db = await openTtsCache();
    try {
      await new Promise<void>((resolve, reject) => {
        const tx = db.transaction(TTS_CACHE_STORE, "readwrite");
        tx.objectStore(TTS_CACHE_STORE).put(blob, key);
        tx.oncomplete = () => resolve();
        tx.onerror = () =>
          reject(tx.error ?? new Error("写入音频缓存失败"));
      });
    } finally {
      db.close();
    }
  } catch {
    // cache write is best-effort
  }
}

export async function fetchTtsAudio(
  text: string,
  voice: string = DEFAULT_TTS_VOICE,
  signal?: AbortSignal,
): Promise<Blob | null> {
  const input = ttsInputText(text);
  const key = ttsCacheKey(text, voice);
  const cached = await getCachedTtsAudio(key);
  if (signal?.aborted) return null;
  if (cached) return cached;

  const response = await apiFetch("/api/tts/speech", {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ text: input, voice, speed: TTS_SPEED }),
    signal,
  });
  if (!response.ok) {
    return null;
  }
  const blob = await response.blob();
  if (signal?.aborted) return null;
  void putCachedTtsAudio(key, blob);
  return blob;
}

let currentAudio: HTMLAudioElement | null = null;
let currentAbort: AbortController | null = null;
let speakResolve: (() => void) | null = null;

function settleSpeak(): void {
  if (!speakResolve) return;
  const resolve = speakResolve;
  speakResolve = null;
  resolve();
}

export function stopSpeech(): void {
  if (currentAbort) {
    currentAbort.abort();
    currentAbort = null;
  }
  if (currentAudio) {
    currentAudio.onended = null;
    currentAudio.onerror = null;
    currentAudio.pause();
    currentAudio = null;
  }
  window.speechSynthesis?.cancel();
  settleSpeak();
}

export async function speakWord(
  word: string,
  voice: string = DEFAULT_TTS_VOICE,
): Promise<void> {
  stopSpeech();

  const abort = new AbortController();
  currentAbort = abort;

  try {
    const blob = await fetchTtsAudio(word, voice, abort.signal);
    if (abort.signal.aborted) return;

    if (blob) {
      const url = URL.createObjectURL(blob);
      const audio = new Audio(url);
      currentAudio = audio;
      await new Promise<void>((resolve) => {
        speakResolve = () => {
          URL.revokeObjectURL(url);
          resolve();
        };
        audio.onended = () => {
          if (currentAudio === audio) currentAudio = null;
          settleSpeak();
        };
        audio.onerror = () => {
          if (currentAudio === audio) currentAudio = null;
          settleSpeak();
        };
        void audio.play().catch(() => settleSpeak());
      });
      return;
    }
  } catch {
    if (abort.signal.aborted) return;
    // fall through to Web Speech API
  }

  if (abort.signal.aborted) return;

  await new Promise<void>((resolve) => {
    speakResolve = resolve;
    if (!window.speechSynthesis) {
      settleSpeak();
      return;
    }
    const utter = new SpeechSynthesisUtterance(word);
    utter.lang = "en-US";
    utter.rate = TTS_SPEED;
    utter.onend = () => settleSpeak();
    utter.onerror = () => settleSpeak();
    window.speechSynthesis.speak(utter);
  });
}

const OCR_MAX_EDGE = 1600;
const OCR_JPEG_QUALITY = 0.82;
const OCR_TARGET_BYTES = 1.5 * 1024 * 1024;

function blobToBase64(blob: Blob): Promise<string> {
  return new Promise((resolve, reject) => {
    const reader = new FileReader();
    reader.onload = () => {
      const result = reader.result;
      if (typeof result !== "string") {
        reject(new Error("读取图片失败"));
        return;
      }
      const commaIndex = result.indexOf(",");
      resolve(commaIndex >= 0 ? result.slice(commaIndex + 1) : result);
    };
    reader.onerror = () => reject(reader.error ?? new Error("读取图片失败"));
    reader.readAsDataURL(blob);
  });
}

function canvasToJpegBlob(
  canvas: HTMLCanvasElement,
  quality: number,
): Promise<Blob> {
  return new Promise((resolve, reject) => {
    canvas.toBlob(
      (blob) => (blob ? resolve(blob) : reject(new Error("图片压缩失败"))),
      "image/jpeg",
      quality,
    );
  });
}

function loadImageElement(
  file: File,
): Promise<{ img: HTMLImageElement; url: string }> {
  return new Promise((resolve, reject) => {
    const url = URL.createObjectURL(file);
    const img = new Image();
    img.onload = () => resolve({ img, url });
    img.onerror = () => {
      URL.revokeObjectURL(url);
      reject(new Error("无法读取图片，请换 JPG 或 PNG"));
    };
    img.src = url;
  });
}

async function compressImageForOcr(
  file: File,
): Promise<{ base64: string; mimeType: string }> {
  const { img, url } = await loadImageElement(file);
  try {
    const longestEdge = Math.max(img.naturalWidth, img.naturalHeight);
    if (longestEdge === 0) {
      throw new Error("图片无效");
    }

    const scale = Math.min(1, OCR_MAX_EDGE / longestEdge);
    const width = Math.max(1, Math.round(img.naturalWidth * scale));
    const height = Math.max(1, Math.round(img.naturalHeight * scale));

    const canvas = document.createElement("canvas");
    canvas.width = width;
    canvas.height = height;
    const ctx = canvas.getContext("2d");
    if (!ctx) {
      throw new Error("无法处理图片");
    }
    ctx.drawImage(img, 0, 0, width, height);

    let quality = OCR_JPEG_QUALITY;
    let blob = await canvasToJpegBlob(canvas, quality);
    while (blob.size > OCR_TARGET_BYTES && quality > 0.5) {
      quality -= 0.1;
      blob = await canvasToJpegBlob(canvas, quality);
    }

    const base64 = await blobToBase64(blob);
    return { base64, mimeType: "image/jpeg" };
  } finally {
    URL.revokeObjectURL(url);
  }
}

export async function ocrWordsFromImage(
  file: File,
  onStatus?: (status: string) => void,
): Promise<{ words: string[]; rawText: string }> {
  onStatus?.("处理图片中…");
  const { base64, mimeType } = await compressImageForOcr(file);
  onStatus?.("识别中…");
  const body: OcrWordsRequest = {
    image_base64: base64,
    mime_type: mimeType,
  };

  let response: Response;
  try {
    response = await apiFetch("/api/ocr/words", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify(body),
    });
  } catch {
    throw new Error("图片上传失败，请检查网络后重试");
  }

  let payload: { data: OcrWordsResponse } | { error: string };
  try {
    payload = (await response.json()) as
      | { data: OcrWordsResponse }
      | { error: string };
  } catch {
    throw new Error(
      response.ok ? "识别失败" : "图片上传中断，请换一张较小的图片重试",
    );
  }

  if (!response.ok || "error" in payload) {
    const message = "error" in payload ? payload.error : "识别失败";
    if (response.status === 400 && message === "aborted") {
      throw new Error("图片上传中断，请重试");
    }
    throw new Error(message);
  }
  return {
    words: payload.data.words,
    rawText: payload.data.raw_text,
  };
}

const WRONG_WORDS_KEY = "dictation_wrong_words";

export function loadWrongWords(): string[] {
  try {
    const data = localStorage.getItem(WRONG_WORDS_KEY);
    if (!data) return [];
    const parsed = JSON.parse(data) as unknown;
    return Array.isArray(parsed)
      ? parsed.filter((item): item is string => typeof item === "string")
      : [];
  } catch {
    return [];
  }
}

export function saveWrongWords(words: string[]): void {
  localStorage.setItem(WRONG_WORDS_KEY, JSON.stringify(words));
}

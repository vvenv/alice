import type { OcrWordsRequest, OcrWordsResponse } from "@alice/shared";

import { apiUrl } from "./api";

export function parseWords(text: string): string[] {
  return text
    .split(/[\n\r,，\t]+/)
    .flatMap((part) => part.trim().split(/\s+/))
    .map((word) => word.trim())
    .filter((word) => word.length > 0);
}

export async function fetchTtsAudio(text: string): Promise<Blob | null> {
  const response = await fetch(apiUrl("/api/tts/speech"), {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ text, speed: 0.9 }),
  });
  if (!response.ok) {
    return null;
  }
  return response.blob();
}

export function speakWithWebSpeech(word: string): Promise<void> {
  return new Promise((resolve) => {
    if (!window.speechSynthesis) {
      resolve();
      return;
    }
    const utter = new SpeechSynthesisUtterance(word);
    utter.lang = "en-US";
    utter.rate = 0.9;
    utter.onend = () => resolve();
    utter.onerror = () => resolve();
    window.speechSynthesis.speak(utter);
  });
}

let currentAudio: HTMLAudioElement | null = null;

export function stopSpeech(): void {
  if (currentAudio) {
    currentAudio.pause();
    currentAudio = null;
  }
  window.speechSynthesis?.cancel();
}

export async function speakWord(word: string): Promise<void> {
  stopSpeech();
  try {
    const blob = await fetchTtsAudio(word);
    if (blob) {
      const url = URL.createObjectURL(blob);
      const audio = new Audio(url);
      currentAudio = audio;
      await new Promise<void>((resolve) => {
        audio.onended = () => {
          URL.revokeObjectURL(url);
          if (currentAudio === audio) currentAudio = null;
          resolve();
        };
        audio.onerror = () => {
          URL.revokeObjectURL(url);
          if (currentAudio === audio) currentAudio = null;
          resolve();
        };
        void audio.play();
      });
      return;
    }
  } catch {
    // fall through to Web Speech API
  }
  await speakWithWebSpeech(word);
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
    response = await fetch(apiUrl("/api/ocr/words"), {
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

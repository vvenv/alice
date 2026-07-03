import type { OcrWordsResponse } from "@alice/shared";

export function parseWords(text: string): string[] {
  return text
    .split(/[\n\r,，\t]+/)
    .flatMap((part) => part.trim().split(/\s+/))
    .map((word) => word.trim())
    .filter((word) => word.length > 0);
}

export async function fetchTtsAudio(text: string): Promise<Blob | null> {
  const response = await fetch("/api/tts/speech", {
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

export async function ocrWordsFromImage(file: File): Promise<string[]> {
  const formData = new FormData();
  formData.append("file", file);
  const response = await fetch("/api/ocr/words", {
    method: "POST",
    body: formData,
  });
  const payload = (await response.json()) as
    | { data: OcrWordsResponse }
    | { error: string };
  if (!response.ok || "error" in payload) {
    throw new Error("error" in payload ? payload.error : "识别失败");
  }
  return payload.data.words;
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

import AsyncStorage from "@react-native-async-storage/async-storage";

export type VoiceOption = { id: string; label: string };

export const EXAM_TTS_VOICE = "6f62ac26-895b-512e-990f-7a0bbf06e75e";

export const SYSTEM_TTS_VOICES: VoiceOption[] = [
  { id: EXAM_TTS_VOICE, label: "考试" },
  { id: "tongtong", label: "彤彤" },
  { id: "chuichui", label: "锤锤" },
  { id: "xiaochen", label: "小陈" },
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
  // Sync read uses the in-memory cache populated at boot.
  const stored = _cachedVoice;
  if (stored && SYSTEM_VOICE_IDS.has(stored)) return stored;
  return DEFAULT_TTS_VOICE;
}

let _cachedVoice: string | null = null;

export async function loadPersistedVoice(): Promise<string> {
  try {
    const stored = await AsyncStorage.getItem(TTS_VOICE_KEY);
    if (stored && SYSTEM_VOICE_IDS.has(stored)) {
      _cachedVoice = stored;
      return stored;
    }
  } catch {
    // ignore
  }
  _cachedVoice = DEFAULT_TTS_VOICE;
  return DEFAULT_TTS_VOICE;
}

export async function saveTtsVoice(voice: string): Promise<void> {
  _cachedVoice = voice;
  try {
    await AsyncStorage.setItem(TTS_VOICE_KEY, voice);
  } catch {
    // ignore
  }
}

const TTS_VOICE_KEY = "dictation_tts_voice";
const WRONG_WORDS_KEY = "dictation_wrong_words";
const WORD_INPUT_KEY = "dictation_word_input";

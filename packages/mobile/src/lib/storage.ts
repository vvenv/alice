import AsyncStorage from "@react-native-async-storage/async-storage";

const WRONG_WORDS_KEY = "dictation_wrong_words";
const WORD_INPUT_KEY = "dictation_word_input";

export function loadWrongWords(): string[] {
  // Sync read from memory cache
  return _cachedWrongWords;
}

let _cachedWrongWords: string[] = [];

export async function loadPersistedWrongWords(): Promise<string[]> {
  try {
    const data = await AsyncStorage.getItem(WRONG_WORDS_KEY);
    if (!data) {
      _cachedWrongWords = [];
      return [];
    }
    const parsed = JSON.parse(data) as unknown;
    const words = Array.isArray(parsed)
      ? parsed.filter((item): item is string => typeof item === "string")
      : [];
    _cachedWrongWords = words;
    return words;
  } catch {
    _cachedWrongWords = [];
    return [];
  }
}

export async function saveWrongWords(words: string[]): Promise<void> {
  _cachedWrongWords = words;
  try {
    await AsyncStorage.setItem(WRONG_WORDS_KEY, JSON.stringify(words));
  } catch {
    // ignore
  }
}

export async function loadWordInput(): Promise<string | null> {
  try {
    return await AsyncStorage.getItem(WORD_INPUT_KEY);
  } catch {
    return null;
  }
}

export async function saveWordInput(value: string): Promise<void> {
  try {
    await AsyncStorage.setItem(WORD_INPUT_KEY, value);
  } catch {
    // ignore
  }
}

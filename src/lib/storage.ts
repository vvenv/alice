import AsyncStorage from "@react-native-async-storage/async-storage";
import { DEFAULT_HISTORY } from "./defaultHistory";

const WRONG_WORDS_KEY = "dictation_wrong_words";
const WORD_INPUT_KEY = "dictation_word_input";
const WORD_HISTORY_KEY = "dictation_word_history";
const MAX_HISTORY_ENTRIES = 50;

export interface WordHistoryEntry {
  id: string;
  text: string;
  timestamp: number;
}

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

export async function loadWordHistory(): Promise<WordHistoryEntry[]> {
  try {
    const data = await AsyncStorage.getItem(WORD_HISTORY_KEY);
    if (!data) {
      // First launch or history was cleared: seed with defaults
      const defaults = DEFAULT_HISTORY.map((h) => h.entry);
      await AsyncStorage.setItem(WORD_HISTORY_KEY, JSON.stringify(defaults));
      return defaults;
    }
    const parsed = JSON.parse(data) as unknown;
    if (!Array.isArray(parsed)) {
      const defaults = DEFAULT_HISTORY.map((h) => h.entry);
      await AsyncStorage.setItem(WORD_HISTORY_KEY, JSON.stringify(defaults));
      return defaults;
    }
    const filtered = parsed.filter(
      (item): item is WordHistoryEntry =>
        typeof item === "object" &&
        item !== null &&
        typeof (item as WordHistoryEntry).id === "string" &&
        typeof (item as WordHistoryEntry).text === "string" &&
        typeof (item as WordHistoryEntry).timestamp === "number",
    );
    // If after filtering the array is empty, re-seed
    if (filtered.length === 0) {
      const defaults = DEFAULT_HISTORY.map((h) => h.entry);
      await AsyncStorage.setItem(WORD_HISTORY_KEY, JSON.stringify(defaults));
      return defaults;
    }
    return filtered;
  } catch {
    // On error, still try to seed defaults
    const defaults = DEFAULT_HISTORY.map((h) => h.entry);
    try {
      await AsyncStorage.setItem(WORD_HISTORY_KEY, JSON.stringify(defaults));
    } catch {
      // ignore
    }
    return defaults;
  }
}

export async function addWordHistory(text: string): Promise<void> {
  const trimmed = text.trim();
  if (!trimmed) return;
  try {
    const history = await loadWordHistory();
    // Remove duplicate (same text) if exists, to move it to top
    const filtered = history.filter((e) => e.text !== trimmed);
    const entry: WordHistoryEntry = {
      id: `${Date.now()}_${Math.random().toString(36).slice(2, 8)}`,
      text: trimmed,
      timestamp: Date.now(),
    };
    const updated = [entry, ...filtered].slice(0, MAX_HISTORY_ENTRIES);
    await AsyncStorage.setItem(WORD_HISTORY_KEY, JSON.stringify(updated));
  } catch {
    // ignore
  }
}

/**
 * Replace a history entry's text (used after dictation to update the original
 * plain-word entry with an enriched version containing pos/meaning).
 */
export async function replaceHistoryText(
  oldText: string,
  newText: string,
): Promise<void> {
  try {
    const history = await loadWordHistory();
    const updated = history.map((e) =>
      e.text === oldText ? { ...e, text: newText } : e,
    );
    await AsyncStorage.setItem(WORD_HISTORY_KEY, JSON.stringify(updated));
  } catch {
    // ignore
  }
}

export async function deleteWordHistory(id: string): Promise<void> {
  // Default entries are not deletable
  if (id.startsWith("default_")) return;
  try {
    const history = await loadWordHistory();
    const updated = history.filter((e) => e.id !== id);
    await AsyncStorage.setItem(WORD_HISTORY_KEY, JSON.stringify(updated));
  } catch {
    // ignore
  }
}

export async function clearWordHistory(): Promise<void> {
  try {
    const history = await loadWordHistory();
    // Keep default entries, remove only user-added ones
    const defaults = history.filter((e) => e.id.startsWith("default_"));
    await AsyncStorage.setItem(WORD_HISTORY_KEY, JSON.stringify(defaults));
  } catch {
    // ignore
  }
}

import AsyncStorage from "@react-native-async-storage/async-storage";

import { DEFAULT_HISTORY } from "./defaultHistory";
import { parseWords, speakTextFromEntry } from "./dictation";

const WRONG_WORDS_KEY = "dictation_wrong_words";
const WORD_INPUT_KEY = "dictation_word_input";
const WORD_HISTORY_KEY = "dictation_word_history";
/** Cap for user-added entries only — defaults are always kept separately. */
const MAX_USER_HISTORY_ENTRIES = 50;

export interface WordHistoryEntry {
  id: string;
  text: string;
  timestamp: number;
  /** Enriched version (word | pos | meaning) — stored as expansion data so
   *  the original plain-word `text` is preserved for history display. */
  enrichedText?: string;
}

export function isDefaultHistoryId(id: string): boolean {
  return id.startsWith("default_");
}

function defaultEntries(): WordHistoryEntry[] {
  // Always clone from the bundled source of truth — never mutate defaults.
  return DEFAULT_HISTORY.map((h) => ({ ...h.entry }));
}

/**
 * Normalize a word list for comparison: strip POS/meaning and keep speakable
 * headwords so enriched text still matches its plain default counterpart.
 */
export function plainWordList(text: string): string {
  return parseWords(text)
    .map((line) => speakTextFromEntry(line))
    .filter(Boolean)
    .join("\n");
}

function matchesDefaultPlainText(text: string): boolean {
  const plain = plainWordList(text);
  if (!plain) return false;
  return DEFAULT_HISTORY.some((h) => plainWordList(h.entry.text) === plain);
}

/**
 * Merge stored history with bundled defaults:
 * - Defaults always come from DEFAULT_HISTORY (label + plain text intact)
 * - User entries are capped; enriched copies of default lists are dropped
 */
function mergeWithDefaults(stored: WordHistoryEntry[]): WordHistoryEntry[] {
  const defaults = defaultEntries();
  const userEntries = stored
    .filter((e) => !isDefaultHistoryId(e.id))
    .filter((e) => !matchesDefaultPlainText(e.text))
    .filter(
      (e) =>
        !(e.enrichedText && matchesDefaultPlainText(e.enrichedText)),
    )
    .slice(0, MAX_USER_HISTORY_ENTRIES);
  return [...userEntries, ...defaults];
}

function sanitizeEntry(item: unknown): WordHistoryEntry | null {
  if (typeof item !== "object" || item === null) return null;
  const e = item as WordHistoryEntry;
  if (
    typeof e.id !== "string" ||
    typeof e.text !== "string" ||
    typeof e.timestamp !== "number"
  ) {
    return null;
  }
  return {
    id: e.id,
    text: e.text,
    timestamp: e.timestamp,
    enrichedText:
      typeof e.enrichedText === "string" && e.enrichedText.length > 0
        ? e.enrichedText
        : undefined,
  };
}

async function persistHistory(entries: WordHistoryEntry[]): Promise<void> {
  await AsyncStorage.setItem(WORD_HISTORY_KEY, JSON.stringify(entries));
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
      const defaults = defaultEntries();
      await persistHistory(defaults);
      return defaults;
    }
    const parsed = JSON.parse(data) as unknown;
    const stored = Array.isArray(parsed)
      ? parsed.map(sanitizeEntry).filter((e): e is WordHistoryEntry => e !== null)
      : [];
    const merged = mergeWithDefaults(stored);
    // Heal storage if defaults were truncated / mutated / duplicated as user rows
    await persistHistory(merged);
    return merged;
  } catch {
    const defaults = defaultEntries();
    try {
      await persistHistory(defaults);
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
    // Starting from a built-in list (plain or enriched) must not create a
    // user row or mutate the default entry — keep label + plain text intact.
    if (matchesDefaultPlainText(trimmed)) return;

    const history = await loadWordHistory();
    const users = history.filter((e) => !isDefaultHistoryId(e.id));

    const existing = users.find(
      (e) => e.text === trimmed || e.enrichedText === trimmed,
    );
    let nextUsers: WordHistoryEntry[];
    if (existing) {
      nextUsers = [
        { ...existing, timestamp: Date.now() },
        ...users.filter((e) => e.id !== existing.id),
      ].slice(0, MAX_USER_HISTORY_ENTRIES);
    } else {
      const entry: WordHistoryEntry = {
        id: `${Date.now()}_${Math.random().toString(36).slice(2, 8)}`,
        text: trimmed,
        timestamp: Date.now(),
      };
      nextUsers = [entry, ...users].slice(0, MAX_USER_HISTORY_ENTRIES);
    }

    await persistHistory([...nextUsers, ...defaultEntries()]);
  } catch {
    // ignore
  }
}

/**
 * Attach enriched text to a *user* history entry. Default entries are ignored.
 */
export async function enrichHistoryEntry(
  originalText: string,
  enrichedText: string,
): Promise<void> {
  try {
    if (matchesDefaultPlainText(originalText)) return;
    const history = await loadWordHistory();
    const updated = mergeWithDefaults(
      history.map((e) =>
        !isDefaultHistoryId(e.id) && e.text === originalText
          ? { ...e, enrichedText }
          : e,
      ),
    );
    await persistHistory(updated);
  } catch {
    // ignore
  }
}

export async function deleteWordHistory(id: string): Promise<void> {
  if (isDefaultHistoryId(id)) return;
  try {
    const history = await loadWordHistory();
    const updated = mergeWithDefaults(history.filter((e) => e.id !== id));
    await persistHistory(updated);
  } catch {
    // ignore
  }
}

export async function clearWordHistory(): Promise<void> {
  try {
    // Drop all user rows; re-seed defaults from the bundled source of truth
    await persistHistory(defaultEntries());
  } catch {
    // ignore
  }
}

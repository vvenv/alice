import AsyncStorage from "@react-native-async-storage/async-storage";

import { DEFAULT_HISTORY, type DefaultHistoryItem } from "./defaultHistory";
import { parseWords, speakTextFromEntry } from "./dictation";

const WRONG_WORDS_KEY = "dictation_wrong_words";
const WORD_INPUT_KEY = "dictation_word_input";
const WORD_HISTORY_KEY = "dictation_word_history";
/** Cap for user-added history entries. Defaults live in code, not storage. */
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

/**
 * Built-in library grouped by category, for the 词库 drawer.
 * Source of truth is DEFAULT_HISTORY (bundled in code); never mutated.
 */
export interface LibraryGroup {
  category: string;
  items: DefaultHistoryItem[];
}

export function getLibraryGroups(): LibraryGroup[] {
  const map = new Map<string, DefaultHistoryItem[]>();
  for (const item of DEFAULT_HISTORY) {
    if (!map.has(item.category)) map.set(item.category, []);
    map.get(item.category)!.push(item);
  }
  return [...map.entries()].map(([category, items]) => ({ category, items }));
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

/**
 * Sanitize stored rows into clean user entries:
 * - drop default-ID rows (left over from older versions that persisted defaults)
 * - drop rows whose text duplicates a built-in list
 * - cap to MAX_USER_HISTORY_ENTRIES
 */
function toUserEntries(stored: WordHistoryEntry[]): WordHistoryEntry[] {
  return stored
    .filter((e) => !isDefaultHistoryId(e.id))
    .filter((e) => !matchesDefaultPlainText(e.text))
    .filter(
      (e) => !(e.enrichedText && matchesDefaultPlainText(e.enrichedText)),
    )
    .slice(0, MAX_USER_HISTORY_ENTRIES);
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

/**
 * Load USER history only. Built-in lists are served via getLibraryGroups().
 * Older installs that persisted default rows are healed automatically.
 */
export async function loadWordHistory(): Promise<WordHistoryEntry[]> {
  try {
    const data = await AsyncStorage.getItem(WORD_HISTORY_KEY);
    if (!data) return [];
    const parsed = JSON.parse(data) as unknown;
    const stored = Array.isArray(parsed)
      ? parsed.map(sanitizeEntry).filter((e): e is WordHistoryEntry => e !== null)
      : [];
    const users = toUserEntries(stored);
    // Heal storage if stale default rows were found.
    if (users.length !== stored.length) {
      await persistHistory(users);
    }
    return users;
  } catch {
    return [];
  }
}

export async function addWordHistory(text: string): Promise<void> {
  const trimmed = text.trim();
  if (!trimmed) return;
  // Starting from a built-in list must not create a user row.
  if (matchesDefaultPlainText(trimmed)) return;
  try {
    const users = await loadWordHistory();
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
    await persistHistory(nextUsers);
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
    const users = await loadWordHistory();
    const updated = users.map((e) =>
      !isDefaultHistoryId(e.id) && e.text === originalText
        ? { ...e, enrichedText }
        : e,
    );
    await persistHistory(updated);
  } catch {
    // ignore
  }
}

export async function deleteWordHistory(id: string): Promise<void> {
  if (isDefaultHistoryId(id)) return;
  try {
    const users = await loadWordHistory();
    await persistHistory(users.filter((e) => e.id !== id));
  } catch {
    // ignore
  }
}

export async function clearWordHistory(): Promise<void> {
  try {
    await persistHistory([]);
  } catch {
    // ignore
  }
}

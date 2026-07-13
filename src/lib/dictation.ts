/**
 * Split multiline word-list input into entries (one per non-empty line).
 */
export function parseWords(text: string): string[] {
  return text
    .split(/[\n\r]+/)
    .map((word) => word.trim())
    .filter((word) => word.length > 0);
}

export interface WordEntry {
  /** 单词/词组（可能含 = 展开语法） */
  word: string;
  /** 词性，如 "n." "v." "adj." */
  pos?: string;
  /** 中文释义 */
  meaning?: string;
}

const PIPE = "|";
const FULLWIDTH_PIPE = "｜";

/**
 * Parse a single line into a structured entry.
 *
 * Format: `word | pos | meaning` (pipe-separated). Only `word` is required;
 * `pos` and `meaning` are optional. A line with no pipe is just a word.
 */
export function parseWordLine(line: string): WordEntry {
  const trimmed = line.trim();
  if (!trimmed) return { word: "" };

  const parts = trimmed.split(new RegExp(`[${PIPE}${FULLWIDTH_PIPE}]`));
  const word = parts[0]?.trim() ?? "";
  const pos = parts[1]?.trim() || undefined;
  const meaning = parts[2]?.trim() || undefined;

  return { word, pos, meaning };
}

/**
 * Parse multiline text into structured entries.
 */
export function parseWordEntries(text: string): WordEntry[] {
  return parseWords(text).map(parseWordLine);
}

/**
 * Serialize a WordEntry back to a line string.
 */
export function entryToLine(entry: WordEntry): string {
  const { word, pos, meaning } = entry;
  if (!pos && !meaning) return word;
  return [word, pos ?? "", meaning ?? ""].join(` ${PIPE} `);
}

/**
 * Text to speak for a list entry.
 *
 * - Strips `|`-delimited pos/meaning suffix (TTS must not read them).
 * - Supports expansion-style entries like `you're = you are`: speak the left
 *   side (`you're`), while the full line remains the display/answer text.
 */
export function speakTextFromEntry(entry: string): string {
  let text = entry.trim();
  if (!text) return "";

  // Strip pos/meaning after the pipe delimiter
  const pipe = text.indexOf(PIPE);
  if (pipe !== -1) text = text.slice(0, pipe).trim();
  if (!text) return "";

  const eq = text.search(/[=＝]/);
  if (eq === -1) return text;

  const left = text.slice(0, eq).trim();
  return left || text;
}

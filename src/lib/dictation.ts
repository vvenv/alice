/**
 * Split multiline word-list input into entries (one per non-empty line).
 */
export function parseWords(text: string): string[] {
  return text
    .split(/[\n\r]+/)
    .map((word) => word.trim())
    .filter((word) => word.length > 0);
}

/**
 * Text to speak for a list entry.
 *
 * Supports expansion-style entries like `you're = you are`: speak the left
 * side (`you're`), while the full line remains the display/answer text.
 */
export function speakTextFromEntry(entry: string): string {
  const text = entry.trim();
  if (!text) return "";

  const eq = text.search(/[=＝]/);
  if (eq === -1) return text;

  const left = text.slice(0, eq).trim();
  return left || text;
}

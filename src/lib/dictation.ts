export function parseWords(text: string): string[] {
  return text
    .split(/[\n\r]+/)
    .map((word) => word.trim())
    .filter((word) => word.length > 0);
}

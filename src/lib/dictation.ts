export function parseWords(text: string): string[] {
  return text
    .split(/[\n\r,，;；\t]+/)
    .flatMap((part) => part.trim().split(/\s+/))
    .map((word) => word.trim())
    .filter((word) => word.length > 0);
}

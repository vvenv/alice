/**
 * Module-level cache for passing enriched word text (with pos/meaning) from
 * the Dictation screen back to the Home screen.
 *
 * React Navigation params cannot carry functions, so we use this lightweight
 * singleton bridge. The Dictation screen sets the enriched text before
 * navigating back; HomeScreen consumes it on focus.
 */
let _enrichedText: string | null = null;

export function setEnrichedResult(text: string): void {
  _enrichedText = text;
}

export function consumeEnrichedResult(): string | null {
  const t = _enrichedText;
  _enrichedText = null;
  return t;
}

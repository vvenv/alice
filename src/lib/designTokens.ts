/**
 * Shared design tokens (non-color). Colors are provided via useThemeColors() from theme.ts.
 */

export const radii = {
  xs: 4,
  control: 8,
  surface: 12,
  button: 15,
  card: 18,
  shell: 24,
  full: 9999,
} as const;

export const spacing = {
  xs: 4,
  sm: 8,
  md: 12,
  lg: 16,
  xl: 20,
  "2xl": 24,
} as const;

/**
 * Bundled faces, registered in App.tsx before the splash is hidden.
 *
 * Each name is a specific TTF (weight/style baked in). On Android, pairing
 * these with StyleSheet `fontWeight` / `fontStyle` makes the resolver miss
 * the face and fall back to the system sans — omit those props.
 */
export const fonts = {
  /** English words, numerals and Latin display copy (Bold). */
  display: "PlayfairDisplay_700Bold",
  /** Latin italic display (Bold Italic). */
  displayItalic: "PlayfairDisplay_700Bold_Italic",
  /** Chinese display headings (Bold). */
  displayZh: "NotoSerifSC_700Bold",
  /** Chinese serif body copy (Medium). */
  serif: "NotoSerifSC_500Medium",
  /** System sans (default) — leave undefined to use the platform default. */
  sans: undefined,
} as const;

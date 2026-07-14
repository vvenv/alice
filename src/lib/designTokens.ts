/**
 * Shared design tokens (non-color). Colors are provided via useThemeColors() from theme.ts.
 */
import { Platform } from "react-native";

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
 * Typography tokens. The Wonderland identity pairs a serif display face with a
 * sans body — mirroring the marketing site's Playfair Display headings. We use
 * the platform's built-in serif (Georgia on iOS, `serif` elsewhere) so it works
 * offline with no font assets to bundle or gate behind the splash screen.
 */
export const fonts = {
  /** Serif display face — use for headings and the dictated word. */
  display: Platform.select({ ios: "Georgia", android: "serif", default: "serif" }),
  /** Serif body face. */
  serif: Platform.select({ ios: "Georgia", android: "serif", default: "serif" }),
  /** System sans (default) — leave undefined to use the platform default. */
  sans: undefined,
} as const;

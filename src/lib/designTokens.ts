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

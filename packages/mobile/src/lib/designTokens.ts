/**
 * Design tokens mapped from packages/client/src/index.css Tailwind v4 theme.
 * Used by all shared components to keep mobile styles aligned with the web client.
 */

export const colors = {
  primary: "#4f46e5",
  primaryLight: "#6366f1",
  primaryDark: "#4338ca",
  primarySoft: "#eef2ff",
  primaryRing: "#e0e7ff",
  primaryFocus: "#818cf8",

  danger: "#e11d48",
  dangerSoft: "#fff1f2",
  dangerHover: "#ffe4e6",
  dangerMuted: "#fb7185",

  foreground: "#000000",
  background: "#ffffff",

  muted: "#00000066",
  subtle: "#00000040",
  secondary: "#000000A6",

  border: "#0000001A",
  borderSubtle: "#0000000F",
  borderMuted: "#00000013",

  surface: "#00000008",
  surfaceRaised: "#0000000B",
  surfaceSunken: "#00000005",
  surfaceHover: "#0000000A",
  track: "#00000012",
} as const;

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

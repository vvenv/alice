import Constants from "expo-constants";

const EXTRA_API_BASE = Constants.expoConfig?.extra?.apiBaseUrl as
  | string
  | undefined;

/** Resolve API URL: use configured base in production, localhost in dev. */
export function apiUrl(path: string): string {
  if (typeof EXTRA_API_BASE === "string" && EXTRA_API_BASE.length > 0) {
    return `${EXTRA_API_BASE.replace(/\/$/, "")}${path}`;
  }
  // In dev / Expo Go, default to localhost:3600 (same as web dev server).
  // Adjust this IP if testing on a physical device.
  return `http://10.0.2.2:3600${path}`; // Android emulator → host machine
}

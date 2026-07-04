import Constants from "expo-constants";

const EXTRA_API_BASE = Constants.expoConfig?.extra?.apiBaseUrl as
  | string
  | undefined;

/** Resolve API URL: use configured base in production, localhost in dev. */
export function apiUrl(path: string): string {
  if (typeof EXTRA_API_BASE === "string" && EXTRA_API_BASE.length > 0) {
    return `${EXTRA_API_BASE.replace(/\/$/, "")}${path}`;
  }
  // Dev fallback: localhost works on iOS simulator and Expo Go.
  // For Android emulator use http://10.0.2.2:3600 instead.
  return `http://localhost:3600${path}`;
}

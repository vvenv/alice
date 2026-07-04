import { Platform } from "react-native";
import Constants from "expo-constants";

const EXTRA_API_BASE = Constants.expoConfig?.extra?.apiBaseUrl as
  | string
  | undefined;

/** Resolve API URL: use configured base in production, dev fallback auto-detects platform. */
export function apiUrl(path: string): string {
  if (typeof EXTRA_API_BASE === "string" && EXTRA_API_BASE.length > 0) {
    return `${EXTRA_API_BASE.replace(/\/$/, "")}${path}`;
  }
  // Android emulator can't reach localhost directly, needs 10.0.2.2.
  const host = Platform.OS === "web" ? "localhost" : "YOUR_SERVER_IP";
  return `http://${host}:3600${path}`;
}

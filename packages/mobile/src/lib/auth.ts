import AsyncStorage from "@react-native-async-storage/async-storage";

import { apiUrl } from "./api-url";
import { createLogger } from "./logger";

const log = createLogger("Auth");
const AUTH_KEY = "alice_access_code";

export function getAccessCode(): string | null {
  // AsyncStorage is always async, but we cache in memory for sync reads.
  // The app bootstraps by reading once.
  return _cachedCode;
}

let _cachedCode: string | null = null;

export function isAuthenticated(): boolean {
  return _cachedCode !== null;
}

export async function loadPersistedCode(): Promise<string | null> {
  try {
    _cachedCode = await AsyncStorage.getItem(AUTH_KEY);
    log.info(`loadPersistedCode: ${_cachedCode === null ? "no code found" : "code loaded"}`);
    return _cachedCode;
  } catch (e) {
    log.warn("Failed to load persisted code:", e);
    return null;
  }
}

export async function saveAccessCode(code: string): Promise<void> {
  _cachedCode = code;
  log.info("saveAccessCode: in-memory code cached");
  try {
    await AsyncStorage.setItem(AUTH_KEY, code);
    log.info("saveAccessCode: persisted to storage");
  } catch (e) {
    log.warn("Failed to persist access code to storage (will use in-memory):", e);
  }
}

export async function clearAccessCode(): Promise<void> {
  try {
    await AsyncStorage.removeItem(AUTH_KEY);
    _cachedCode = null;
  } catch {
    // ignore
  }
}

/** Verify code against server, then persist. */
export async function authenticate(code: string): Promise<boolean> {
  log.info(`authenticate called with code length=${code.length}`);
  let response: Response;
  try {
    response = await fetch(apiUrl("/api/auth/verify"), {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ code }),
    });
  } catch (e) {
    log.warn("authenticate network error:", e);
    return false;
  }
  log.info(`/api/auth/verify response status=${response.status}`);
  if (!response.ok) return false;
  await saveAccessCode(code);
  return true;
}

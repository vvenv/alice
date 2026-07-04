import AsyncStorage from "@react-native-async-storage/async-storage";

import { config } from "./config";
import { createLogger } from "./logger";

const log = createLogger("Auth");
const AUTH_KEY = "alice_access_code";

export function getAccessCode(): string | null {
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
  try {
    await AsyncStorage.setItem(AUTH_KEY, code);
  } catch {
    // ignore
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

/** Verify code locally against configured access code. */
export function authenticate(code: string): boolean {
  if (code === config.accessCode) {
    void saveAccessCode(code);
    return true;
  }
  return false;
}

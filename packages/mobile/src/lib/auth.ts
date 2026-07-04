import AsyncStorage from "@react-native-async-storage/async-storage";

import { apiUrl } from "./api-url";

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
    return _cachedCode;
  } catch {
    return null;
  }
}

export async function saveAccessCode(code: string): Promise<void> {
  try {
    await AsyncStorage.setItem(AUTH_KEY, code);
    _cachedCode = code;
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

/** Verify code against server, then persist. */
export async function authenticate(code: string): Promise<boolean> {
  let response: Response;
  try {
    response = await fetch(apiUrl("/api/auth/verify"), {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ code }),
    });
  } catch {
    return false;
  }
  if (!response.ok) return false;
  await saveAccessCode(code);
  return true;
}

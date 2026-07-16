import AsyncStorage from "@react-native-async-storage/async-storage";

import { config } from "./config";
import { hmacSha256Hex } from "./crypto";

const OCR_KEY = "alice_ocr_unlocked";
/** Hex prefix that a valid HMAC must start with. ~1/256 false positive rate. */
const VALID_PREFIX = "00";

let _ocrUnlocked = false;

export function isOcrUnlocked(): boolean {
  return _ocrUnlocked;
}

export async function loadOcrUnlockState(): Promise<boolean> {
  try {
    _ocrUnlocked = (await AsyncStorage.getItem(OCR_KEY)) === "true";
    return _ocrUnlocked;
  } catch {
    return false;
  }
}

/**
 * Verify an unlock code locally using HMAC-SHA256.
 *
 * A code is valid if:
 *   HMAC-SHA256(hmacSecret, code.toUpperCase()).startsWith("00")
 *
 * This means ~1/256 random 4-char codes will pass — low enough for casual
 * protection. The secret is embedded in the app; anyone who reverses the
 * binary can forge codes, but this is a pragmatic trade-off comparable to
 * most mobile paywalls.
 */
export function verifyUnlockCode(code: string): boolean {
  // No secret configured (e.g. building from source without .env) → stay locked.
  if (!config.hmacSecret) return false;
  const hex = hmacSha256Hex(config.hmacSecret, code.toUpperCase());
  const ok = hex.startsWith(VALID_PREFIX);
  if (ok) {
    _ocrUnlocked = true;
    // fire-and-forget persistence
    AsyncStorage.setItem(OCR_KEY, "true").catch(() => {});
  }
  return ok;
}

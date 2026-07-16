/**
 * Haptic feedback helpers. Wraps expo-haptics defensively: on web, or in a
 * native build that predates the expo-haptics module, every call is a no-op
 * instead of a crash.
 */
import { Platform } from "react-native";

type HapticsModule = typeof import("expo-haptics");

let Haptics: HapticsModule | null = null;
if (Platform.OS === "ios" || Platform.OS === "android") {
  try {
    // eslint-disable-next-line @typescript-eslint/no-var-requires
    Haptics = require("expo-haptics") as HapticsModule;
  } catch {
    Haptics = null;
  }
}

/** Subtle tick for ordinary button presses. */
export function tapLight(): void {
  Haptics?.impactAsync(Haptics.ImpactFeedbackStyle.Light).catch(() => {});
}

/** Firmer tap for primary actions (start dictation). */
export function tapMedium(): void {
  Haptics?.impactAsync(Haptics.ImpactFeedbackStyle.Medium).catch(() => {});
}

/** Celebration on completing a dictation session. */
export function notifySuccess(): void {
  Haptics?.notificationAsync(Haptics.NotificationFeedbackType.Success).catch(
    () => {},
  );
}

/** Feedback when marking a wrong word. */
export function notifyWarning(): void {
  Haptics?.notificationAsync(Haptics.NotificationFeedbackType.Warning).catch(
    () => {},
  );
}

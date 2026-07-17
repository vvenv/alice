/**
 * UI sound effects (watch tick near the end of a countdown, completion chime).
 * Synthesized in-house (assets/sounds), played via expo-audio. Every call is
 * defensive: a missing module or playback failure degrades to silence.
 */
import AsyncStorage from "@react-native-async-storage/async-storage";
import { createAudioPlayer, type AudioPlayer } from "expo-audio";

const SOUND_KEY = "alice_sound_enabled";

let enabled = true;
let loaded = false;

function ensureLoaded(): void {
  if (loaded) return;
  loaded = true;
  AsyncStorage.getItem(SOUND_KEY)
    .then((v) => {
      if (v === "off") enabled = false;
    })
    .catch(() => {});
}
ensureLoaded();

export function isSoundEnabled(): boolean {
  return enabled;
}

export async function loadSoundEnabled(): Promise<boolean> {
  try {
    const v = await AsyncStorage.getItem(SOUND_KEY);
    enabled = v !== "off";
  } catch {
    // keep current value
  }
  return enabled;
}

export function setSoundEnabled(value: boolean): void {
  enabled = value;
  AsyncStorage.setItem(SOUND_KEY, value ? "on" : "off").catch(() => {});
}

let tickPlayer: AudioPlayer | null = null;
let chimePlayer: AudioPlayer | null = null;

function play(getPlayer: () => AudioPlayer): void {
  if (!enabled) return;
  try {
    const player = getPlayer();
    player.seekTo(0);
    player.play();
  } catch {
    // no audio backend — stay silent
  }
}

/** Soft watch tick — final second of the word countdown. */
export function playTick(): void {
  play(() => {
    if (!tickPlayer) {
      // eslint-disable-next-line @typescript-eslint/no-var-requires
      tickPlayer = createAudioPlayer(require("../../assets/sounds/tick.wav"));
      tickPlayer.volume = 0.5;
    }
    return tickPlayer;
  });
}

/** Gentle two-note chime — dictation completed. */
export function playChime(): void {
  play(() => {
    if (!chimePlayer) {
      // eslint-disable-next-line @typescript-eslint/no-var-requires
      chimePlayer = createAudioPlayer(require("../../assets/sounds/chime.wav"));
      chimePlayer.volume = 0.6;
    }
    return chimePlayer;
  });
}

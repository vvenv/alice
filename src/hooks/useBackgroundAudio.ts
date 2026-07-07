import { useAudioPlayer } from "expo-audio";
import { useCallback, useEffect, useRef } from "react";

// ---------------------------------------------------------------------------
// Types
// ---------------------------------------------------------------------------

interface RemoteCallbacks {
  onTogglePlayPause: () => void;
  onSkipToNext: () => void;
  onSkipToPrevious: () => void;
}

// ---------------------------------------------------------------------------
// Constants
// ---------------------------------------------------------------------------

/**
 * When the playing-state changes we wait this long to confirm it's a
 * deliberate user action (lock-screen / notification centre), not a
 * transient fluke caused by the 5 s silent file looping.
 */
const TOGGLE_DEBOUNCE_MS = 500;

/**
 * A seek jump larger than this is treated as a skip-forward / skip-backward
 * command.  We deliberately exclude the ~5 s drop that happens when the
 * silent file loops naturally, so only genuine OS-level seek commands fire.
 */
const SEEK_MIN_JUMP_S = 0.4;
/** A natural loop wrap-around is roughly 0 → 5 or 5 → 0 — exclude those. */
const SEEK_MAX_JUMP_S = 4.0;

// ---------------------------------------------------------------------------
// Hook
// ---------------------------------------------------------------------------

/**
 * Keeps the audio session alive while dictation is in progress, and responds
 * to system lock-screen / notification-centre controls (play/pause / skip).
 *
 * Internally plays a silent 5-second looping WAV through `expo-audio`, which
 * prevents the OS from suspending the JS thread when the app enters the
 * background.  The same player is registered for lock-screen control via
 * `setActiveForLockScreen`.
 */
export function useBackgroundAudio(
  callbacksRef: React.MutableRefObject<RemoteCallbacks>,
) {
  const player = useAudioPlayer(require("../../assets/silent.wav"), {
    updateInterval: 300,
    keepAudioSessionActive: true,
  });

  // Internal state refs (avoid stale closures inside the listener)
  const isActiveRef = useRef(false);
  /** Count of our own play/pause/seek actions that we expect to see as
   *  status updates.  Each `setPlaying()` / `startSession()` call
   *  increments this; the listener decrements it until it reaches 0. */
  const pendingInternalRef = useRef(0);
  const prevPlayingRef = useRef(false);
  const prevTimeRef = useRef(0);
  const toggleTimerRef = useRef<ReturnType<typeof setTimeout> | null>(null);

  // ---- One-time player setup ----
  useEffect(() => {
    player.loop = true;
    // Very low volume so the system considers the session "active",
    // but still inaudible to the user.
    player.volume = 0.01;
  }, [player]);

  // ---- Playback-status listener ----
  useEffect(() => {
    const sub = player.addListener("playbackStatusUpdate", (status) => {
      if (!isActiveRef.current) return;

      // ----- 1. Consume status updates we caused ourselves -----
      if (pendingInternalRef.current > 0) {
        pendingInternalRef.current -= 1;
        prevPlayingRef.current = status.playing;
        prevTimeRef.current = status.currentTime;
        return;
      }

      // ----- 2. Play / Pause toggle (debounced) -----
      if (status.playing !== prevPlayingRef.current) {
        prevPlayingRef.current = status.playing;
        prevTimeRef.current = status.currentTime;

        if (toggleTimerRef.current) clearTimeout(toggleTimerRef.current);
        toggleTimerRef.current = setTimeout(() => {
          toggleTimerRef.current = null;
          // Double-check the player hasn't bounced back (loop transition)
          if (player.playing === status.playing) {
            callbacksRef.current.onTogglePlayPause();
          }
        }, TOGGLE_DEBOUNCE_MS);
        return;
      }

      // ----- 3. Skip forward / backward (seek detection) -----
      const timeDelta = status.currentTime - prevTimeRef.current;
      prevTimeRef.current = status.currentTime;

      const absDelta = Math.abs(timeDelta);
      // Filter out the natural loop wrap-around (-5 s or +5 s).
      if (
        absDelta > SEEK_MIN_JUMP_S &&
        absDelta < SEEK_MAX_JUMP_S
      ) {
        if (timeDelta > 0) {
          callbacksRef.current.onSkipToNext();
        } else {
          callbacksRef.current.onSkipToPrevious();
        }
      }
    });

    return () => {
      sub.remove();
      if (toggleTimerRef.current) clearTimeout(toggleTimerRef.current);
    };
  }, [player, callbacksRef]);

  // ---- Public API ----

  /** Activate lock screen + start the silent loop. */
  const startSession = useCallback(
    (isPlaying: boolean) => {
      isActiveRef.current = true;
      prevPlayingRef.current = isPlaying;

      player.setActiveForLockScreen(
        true,
        {
          title: "Alice 听写",
          artist: "单词听写中",
        },
        {
          showSeekForward: false,
          showSeekBackward: false,
        },
      );

      pendingInternalRef.current += 1;
      if (isPlaying) {
        player.play();
      } else {
        player.pause();
      }
    },
    [player],
  );

  /**
   * Sync the lock-screen play state after an in-app toggle (user pressed
   * the in-app pause / resume button, not the lock-screen one).
   */
  const setPlaying = useCallback(
    (playing: boolean) => {
      if (!isActiveRef.current) return;
      pendingInternalRef.current += 1;
      prevPlayingRef.current = playing;
      if (playing) {
        player.play();
      } else {
        player.pause();
      }
    },
    [player],
  );

  /** Update the metadata displayed on the lock screen. */
  const updateMetadata = useCallback(
    (title: string, artist?: string) => {
      if (!isActiveRef.current) return;
      player.updateLockScreenMetadata({
        title,
        artist: artist ?? "单词听写中",
      });
    },
    [player],
  );

  /** Deactivate lock screen and pause the silent loop. */
  const stopSession = useCallback(() => {
    isActiveRef.current = false;
    pendingInternalRef.current += 1;
    player.setActiveForLockScreen(false);
    player.pause();
  }, [player]);

  return { startSession, setPlaying, updateMetadata, stopSession };
}

import { useAudioPlayer } from "expo-audio";
import { useCallback, useEffect, useRef } from "react";

const SEEK_THRESHOLD_S = 0.2;

interface RemoteCallbacks {
  onTogglePlayPause: () => void;
  onSkipToNext: () => void;
  onSkipToPrevious: () => void;
}

export function useBackgroundAudio(
  callbacksRef: React.MutableRefObject<RemoteCallbacks>,
) {
  const player = useAudioPlayer(require("../../assets/silent.wav"), {
    updateInterval: 300,
    keepAudioSessionActive: true,
  });

  const isActiveRef = useRef(false);
  const internalActionRef = useRef(false);
  const prevPlayingRef = useRef(false);
  const prevTimeRef = useRef(0);

  useEffect(() => {
    player.loop = true;
    player.volume = 0;
    player.muted = true;
  }, [player]);

  useEffect(() => {
    const sub = player.addListener("playbackStatusUpdate", (status) => {
      if (!isActiveRef.current) return;

      if (internalActionRef.current) {
        internalActionRef.current = false;
        prevPlayingRef.current = status.playing;
        prevTimeRef.current = status.currentTime;
        return;
      }

      if (status.playing !== prevPlayingRef.current) {
        prevPlayingRef.current = status.playing;
        prevTimeRef.current = status.currentTime;
        callbacksRef.current.onTogglePlayPause();
        return;
      }

      const timeDelta = status.currentTime - prevTimeRef.current;
      prevTimeRef.current = status.currentTime;

      if (Math.abs(timeDelta) > SEEK_THRESHOLD_S) {
        if (timeDelta > 0) {
          callbacksRef.current.onSkipToNext();
        } else {
          callbacksRef.current.onSkipToPrevious();
        }
      }
    });

    return () => sub.remove();
  }, [player, callbacksRef]);

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
          showSeekForward: true,
          showSeekBackward: true,
        },
      );

      internalActionRef.current = true;
      if (isPlaying) {
        player.play();
      } else {
        player.pause();
      }
    },
    [player],
  );

  const setPlaying = useCallback(
    (playing: boolean) => {
      if (!isActiveRef.current) return;
      internalActionRef.current = true;
      prevPlayingRef.current = playing;
      if (playing) {
        player.play();
      } else {
        player.pause();
      }
    },
    [player],
  );

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

  const stopSession = useCallback(() => {
    isActiveRef.current = false;
    internalActionRef.current = true;
    player.setActiveForLockScreen(false);
    player.pause();
  }, [player]);

  return { startSession, setPlaying, updateMetadata, stopSession };
}

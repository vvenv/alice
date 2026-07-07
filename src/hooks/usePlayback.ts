import { useCallback, useEffect, useRef, useState } from "react";

import { speakWord, stopSpeech } from "../lib/tts";

type PlayState = "idle" | "playing" | "paused";

const TICK_INTERVAL_MS = 50;
const REPEAT_GAP_MS = 700;

function sleep(ms: number): Promise<void> {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

export function usePlayback({
  intervalSec,
  autoNext,
}: {
  intervalSec: number;
  autoNext: boolean;
}) {
  const [playState, setPlayState] = useState<PlayState>("idle");
  const [wordList, setWordList] = useState<string[]>([]);
  const [currentIndex, setCurrentIndex] = useState(0);
  const [remainingMs, setRemainingMs] = useState<number | null>(null);

  const timerRef = useRef<ReturnType<typeof setTimeout> | null>(null);
  const tickRef = useRef<ReturnType<typeof setInterval> | null>(null);
  const deadlineRef = useRef<number | null>(null);
  const playStateRef = useRef(playState);
  const currentIndexRef = useRef(currentIndex);
  const wordListRef = useRef(wordList);
  const playGenRef = useRef(0);

  currentIndexRef.current = currentIndex;
  wordListRef.current = wordList;

  const isActive = playState === "playing" || playState === "paused";

  const updatePlayState = useCallback((state: PlayState) => {
    playStateRef.current = state;
    setPlayState(state);
  }, []);

  const clearCountdown = useCallback(() => {
    if (tickRef.current) {
      clearInterval(tickRef.current);
      tickRef.current = null;
    }
    deadlineRef.current = null;
    setRemainingMs(null);
  }, []);

  const startCountdown = useCallback(
    (seconds: number) => {
      clearCountdown();
      const totalMs = seconds * 1000;
      const deadline = Date.now() + totalMs;
      deadlineRef.current = deadline;
      setRemainingMs(totalMs);

      tickRef.current = setInterval(() => {
        if (deadlineRef.current === null) return;
        const left = Math.max(0, deadlineRef.current - Date.now());
        setRemainingMs(left);
      }, TICK_INTERVAL_MS);
    },
    [clearCountdown],
  );

  const clearTimer = useCallback(() => {
    if (timerRef.current) {
      clearTimeout(timerRef.current);
      timerRef.current = null;
    }
    clearCountdown();
  }, [clearCountdown]);

  const finishDictation = useCallback(() => {
    clearTimer();
    stopSpeech();
    updatePlayState("idle");
  }, [clearTimer, updatePlayState]);

  const isPlayCurrent = useCallback((gen: number) => {
    return playStateRef.current === "playing" && playGenRef.current === gen;
  }, []);

  const playNextWord = useCallback(
    async (index: number, list: string[]) => {
      const gen = playGenRef.current;
      if (!isPlayCurrent(gen)) return;
      if (index >= list.length) {
        finishDictation();
        return;
      }

      clearCountdown();
      currentIndexRef.current = index;
      setCurrentIndex(index);
      const word = list[index]!;

      // Classroom style: each word read twice with a short gap.
      await speakWord(word);
      if (!isPlayCurrent(gen)) return;

      await sleep(REPEAT_GAP_MS);
      if (!isPlayCurrent(gen)) return;

      await speakWord(word);
      if (!isPlayCurrent(gen)) return;

      if (autoNext) {
        startCountdown(intervalSec);
        timerRef.current = setTimeout(() => {
          timerRef.current = null;
          clearCountdown();
          void playNextWord(index + 1, list);
        }, intervalSec * 1000);
      }
    },
    [
      autoNext,
      clearCountdown,
      finishDictation,
      intervalSec,
      isPlayCurrent,
      startCountdown,
    ],
  );

  const startDictation = useCallback(
    (words: string[]) => {
      playGenRef.current += 1;
      clearTimer();
      stopSpeech();
      setWordList(words);
      setCurrentIndex(0);
      updatePlayState("playing");
      void playNextWord(0, words);
    },
    [clearTimer, playNextWord, updatePlayState],
  );

  const resumeDictation = useCallback(() => {
    playGenRef.current += 1;
    updatePlayState("playing");
    const list = wordListRef.current;
    const index = currentIndexRef.current;
    if (index >= list.length) {
      finishDictation();
      return;
    }
    if (!timerRef.current) {
      void playNextWord(index, list);
    }
  }, [finishDictation, playNextWord, updatePlayState]);

  const pauseDictation = useCallback(() => {
    playGenRef.current += 1;
    updatePlayState("paused");
    clearTimer();
    stopSpeech();
  }, [clearTimer, updatePlayState]);

  const stopDictation = useCallback(() => {
    playGenRef.current += 1;
    clearTimer();
    stopSpeech();
    updatePlayState("idle");
  }, [clearTimer, updatePlayState]);

  const skipToNextWord = useCallback(() => {
    if (
      playStateRef.current !== "playing" &&
      playStateRef.current !== "paused"
    ) {
      return;
    }

    const list = wordListRef.current;
    const nextIndex = currentIndexRef.current + 1;

    playGenRef.current += 1;
    clearTimer();
    stopSpeech();

    currentIndexRef.current = nextIndex;
    if (playStateRef.current === "paused") {
      updatePlayState("playing");
    }
    void playNextWord(nextIndex, list);
  }, [clearTimer, playNextWord, updatePlayState]);

  useEffect(
    () => () => {
      clearTimer();
      stopSpeech();
    },
    [clearTimer],
  );

  return {
    playState,
    wordList,
    currentIndex,
    remainingMs,
    isActive,
    startDictation,
    pauseDictation,
    resumeDictation,
    stopDictation,
    skipToNextWord,
  };
}

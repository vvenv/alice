import { useCallback, useEffect, useRef, useState } from "react";

import {
  speakWord,
  stopSpeech,
} from "../lib/tts";

type PlayState = "idle" | "playing" | "paused";
type WordPhase = "speak1" | "gap" | "speak2" | "interval";

const REPEAT_GAP_MS = 700;

type Scheduler = {
  gen: number;
  index: number;
  phase: WordPhase;
  speaking: boolean;
};

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

  const playStateRef = useRef(playState);
  const currentIndexRef = useRef(currentIndex);
  const wordListRef = useRef(wordList);
  const playGenRef = useRef(0);
  const intervalSecRef = useRef(intervalSec);
  const autoNextRef = useRef(autoNext);
  const schedulerRef = useRef<Scheduler | null>(null);
  const cycleAbortRef = useRef<AbortController | null>(null);
  const countdownTimerRef = useRef<ReturnType<typeof setInterval> | null>(null);
  const deadlineRef = useRef<number | null>(null);

  intervalSecRef.current = intervalSec;
  autoNextRef.current = autoNext;
  currentIndexRef.current = currentIndex;
  wordListRef.current = wordList;

  const isActive = playState === "playing" || playState === "paused";

  const updatePlayState = useCallback((state: PlayState) => {
    playStateRef.current = state;
    setPlayState(state);
  }, []);

  const clearCountdown = useCallback(() => {
    if (countdownTimerRef.current) {
      clearInterval(countdownTimerRef.current);
      countdownTimerRef.current = null;
    }
    deadlineRef.current = null;
    setRemainingMs(null);
  }, []);

  const abortCycle = useCallback(() => {
    cycleAbortRef.current?.abort();
    cycleAbortRef.current = null;
  }, []);

  const isCancelled = useCallback((gen: number) => {
    return (
      playStateRef.current !== "playing" ||
      playGenRef.current !== gen ||
      !schedulerRef.current ||
      schedulerRef.current.gen !== gen
    );
  }, []);

  const finishDictation = useCallback(() => {
    abortCycle();
    schedulerRef.current = null;
    clearCountdown();
    stopSpeech();
    updatePlayState("idle");
  }, [abortCycle, clearCountdown, updatePlayState]);

  const waitMs = useCallback(
    (ms: number, signal: AbortSignal): Promise<boolean> => {
      if (ms <= 0) return Promise.resolve(true);
      const deadline = Date.now() + ms;
      deadlineRef.current = deadline;
      setRemainingMs(ms);

      return new Promise((resolve) => {
        if (signal.aborted) {
          resolve(false);
          return;
        }

        const finish = (ok: boolean) => {
          clearInterval(id);
          resolve(ok);
        };

        const id = setInterval(() => {
          if (signal.aborted) {
            finish(false);
            return;
          }
          const left = Math.max(0, deadline - Date.now());
          setRemainingMs(left);
          if (left === 0) {
            finish(true);
          }
        }, 50);

        const onAbort = () => {
          signal.removeEventListener("abort", onAbort);
          finish(false);
        };
        signal.addEventListener("abort", onAbort);
      });
    },
    [],
  );

  const runScheduler = useCallback(async () => {
    const s = schedulerRef.current;
    if (!s) return;
    if (playStateRef.current !== "playing") return;
    if (s.speaking) return;

    const list = wordListRef.current;
    if (s.index >= list.length) {
      finishDictation();
      return;
    }

    const gen = s.gen;
    const word = list[s.index]!;
    const signal = cycleAbortRef.current?.signal;
    if (!signal || signal.aborted) return;

    if (s.phase === "speak1" || s.phase === "speak2") {
      s.speaking = true;
      const phase = s.phase;
      currentIndexRef.current = s.index;
      setCurrentIndex(s.index);

      const ok = await speakWord(word);
      if (isCancelled(gen)) return;

      const cur = schedulerRef.current;
      if (!cur || cur.gen !== gen) return;
      cur.speaking = false;

      // If speaking failed, don't retry the same word forever — that turns a
      // single TTS failure into an infinite loop (and a frozen app). Skip the
      // repeat gap and let the scheduler advance to the next phase/word. The
      // `speak2` pass still acts as a natural second attempt for `speak1`.
      if (!ok && phase === "speak1") {
        cur.phase = "speak2";
        runScheduler();
        return;
      }

      if (phase === "speak1") {
        cur.phase = "gap";
        const gapOk = await waitMs(REPEAT_GAP_MS, signal);
        if (isCancelled(gen) || !gapOk) return;
        cur.phase = "speak2";
        runScheduler();
        return;
      }

      if (!autoNextRef.current) {
        schedulerRef.current = null;
        return;
      }

      cur.phase = "interval";
      const intervalMs = intervalSecRef.current * 1000;
      const intervalOk = await waitMs(intervalMs, signal);
      if (isCancelled(gen) || !intervalOk) return;

      clearCountdown();
      const nextIndex = cur.index + 1;
      if (nextIndex >= list.length) {
        finishDictation();
        return;
      }
      cur.index = nextIndex;
      cur.phase = "speak1";
      currentIndexRef.current = nextIndex;
      setCurrentIndex(nextIndex);
      runScheduler();
      return;
    }

    if (s.phase === "gap") {
      s.phase = "speak2";
      runScheduler();
      return;
    }

    if (s.phase === "interval") {
      const intervalMs = intervalSecRef.current * 1000;
      const intervalOk = await waitMs(intervalMs, signal);
      if (isCancelled(gen) || !intervalOk) return;

      clearCountdown();
      const nextIndex = s.index + 1;
      if (nextIndex >= list.length) {
        finishDictation();
        return;
      }
      s.index = nextIndex;
      s.phase = "speak1";
      currentIndexRef.current = nextIndex;
      setCurrentIndex(nextIndex);
      runScheduler();
    }
  }, [clearCountdown, finishDictation, isCancelled, waitMs]);

  const runSchedulerRef = useRef(runScheduler);
  runSchedulerRef.current = runScheduler;

  const startFrom = useCallback(
    (index: number, fromPhase: WordPhase) => {
      const list = wordListRef.current;
      if (index >= list.length) {
        finishDictation();
        return;
      }

      abortCycle();
      cycleAbortRef.current = new AbortController();

      schedulerRef.current = {
        gen: playGenRef.current,
        index,
        phase: fromPhase,
        speaking: false,
      };
      currentIndexRef.current = index;
      setCurrentIndex(index);
      void runSchedulerRef.current();
    },
    [abortCycle, finishDictation],
  );

  const startDictation = useCallback(
    (words: string[]) => {
      playGenRef.current += 1;
      abortCycle();
      schedulerRef.current = null;
      clearCountdown();
      stopSpeech();

      wordListRef.current = words;
      currentIndexRef.current = 0;
      setWordList(words);
      setCurrentIndex(0);

      if (words.length === 0) {
        updatePlayState("idle");
        return;
      }

      updatePlayState("playing");
      startFrom(0, "speak1");
    },
    [abortCycle, clearCountdown, startFrom, updatePlayState],
  );

  const resumeDictation = useCallback(() => {
    if (playStateRef.current === "playing") return;

    const index = currentIndexRef.current;
    const list = wordListRef.current;
    if (index >= list.length) {
      finishDictation();
      return;
    }

    playGenRef.current += 1;
    updatePlayState("playing");

    startFrom(index, "speak1"); }
  , [finishDictation, startFrom, updatePlayState]);

  const pauseDictation = useCallback(() => {
    playGenRef.current += 1;
    updatePlayState("paused");
    schedulerRef.current = null;
    abortCycle();
    clearCountdown();
    stopSpeech();
  }, [abortCycle, clearCountdown, updatePlayState]);

  const stopDictation = useCallback(() => {
    playGenRef.current += 1;
    schedulerRef.current = null;
    abortCycle();
    clearCountdown();
    stopSpeech();
    updatePlayState("idle");
  }, [abortCycle, clearCountdown, updatePlayState]);

  const skipToNextWord = useCallback(() => {
    if (
      playStateRef.current !== "playing" &&
      playStateRef.current !== "paused"
    ) {
      return;
    }

    const nextIndex = currentIndexRef.current + 1;
    playGenRef.current += 1;
    abortCycle();
    clearCountdown();
    stopSpeech();

    currentIndexRef.current = nextIndex;
    if (playStateRef.current === "paused") {
      updatePlayState("playing");
    }
    startFrom(nextIndex, "speak1");
  }, [abortCycle, clearCountdown, startFrom, updatePlayState]);

  const isDictationPlaying = useCallback(() => {
    return playStateRef.current === "playing";
  }, []);

  // ---- Interval slider live update ----
  useEffect(() => {
    if (playStateRef.current !== "playing") return;
    const s = schedulerRef.current;
    if (!s || s.phase !== "interval") return;
    // Restart countdown with new interval
    const newDeadline = Date.now() + intervalSec * 1000;
    deadlineRef.current = newDeadline;
    setRemainingMs(Math.max(0, newDeadline - Date.now()));
  }, [intervalSec]);

  useEffect(
    () => () => {
      abortCycle();
      schedulerRef.current = null;
      clearCountdown();
      stopSpeech();
    },
    [abortCycle, clearCountdown],
  );

  return {
    playState,
    wordList,
    currentIndex,
    remainingMs,
    isActive,
    isDictationPlaying,
    startDictation,
    pauseDictation,
    resumeDictation,
    stopDictation,
    skipToNextWord,
  };
}

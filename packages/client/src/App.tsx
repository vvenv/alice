import { useCallback, useEffect, useRef, useState } from "react";

import {
  loadWrongWords,
  ocrWordsFromImage,
  parseWords,
  saveWrongWords,
  speakWord,
  stopSpeech,
} from "./lib/dictation";

type PlayState = "idle" | "playing" | "paused";

const SAMPLE_WORDS = "apple banana cat dog elephant fish grape";

export default function App() {
  const [wordInput, setWordInput] = useState(
    "apple banana cat dog elephant\n",
  );
  const [intervalSec, setIntervalSec] = useState(3);
  const [autoNext, setAutoNext] = useState(true);
  const [showWord, setShowWord] = useState(false);
  const [playState, setPlayState] = useState<PlayState>("idle");
  const [wordList, setWordList] = useState<string[]>([]);
  const [currentIndex, setCurrentIndex] = useState(0);
  const [wrongWords, setWrongWords] = useState<string[]>(() => loadWrongWords());
  const [markedFlash, setMarkedFlash] = useState(false);
  const [ocrStatus, setOcrStatus] = useState("");
  const [ocrBusy, setOcrBusy] = useState(false);

  const timerRef = useRef<ReturnType<typeof setTimeout> | null>(null);
  const playStateRef = useRef(playState);
  const currentIndexRef = useRef(currentIndex);
  const wordListRef = useRef(wordList);
  const ocrInFlightRef = useRef(false);

  playStateRef.current = playState;
  currentIndexRef.current = currentIndex;
  wordListRef.current = wordList;

  const updatePlayState = useCallback((state: PlayState) => {
    playStateRef.current = state;
    setPlayState(state);
  }, []);

  const wordCount = parseWords(wordInput).length;
  const isActive = playState === "playing" || playState === "paused";
  const showInputSection = !isActive || showWord;
  const isFinished = wordList.length > 0 && currentIndex >= wordList.length;

  const clearTimer = useCallback(() => {
    if (timerRef.current) {
      clearTimeout(timerRef.current);
      timerRef.current = null;
    }
  }, []);

  const persistWrongWords = useCallback((words: string[]) => {
    setWrongWords(words);
    saveWrongWords(words);
  }, []);

  const finishDictation = useCallback(() => {
    clearTimer();
    stopSpeech();
    updatePlayState("idle");
  }, [clearTimer, updatePlayState]);

  const playNextWord = useCallback(
    async (index: number, list: string[]) => {
      if (playStateRef.current !== "playing") return;
      if (index >= list.length) {
        finishDictation();
        return;
      }

      setCurrentIndex(index);
      await speakWord(list[index]!);

      if (playStateRef.current !== "playing") return;
      if (autoNext) {
        timerRef.current = setTimeout(() => {
          timerRef.current = null;
          void playNextWord(index + 1, list);
        }, intervalSec * 1000);
      }
    },
    [autoNext, finishDictation, intervalSec],
  );

  const startDictation = useCallback(() => {
    const words = parseWords(wordInput);
    if (words.length === 0) {
      alert("请先输入单词列表");
      return;
    }

    clearTimer();
    stopSpeech();
    setWordList(words);
    setCurrentIndex(0);
    updatePlayState("playing");
    void playNextWord(0, words);
  }, [clearTimer, playNextWord, updatePlayState, wordInput]);

  const resumeDictation = useCallback(() => {
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
    updatePlayState("paused");
    clearTimer();
    stopSpeech();
  }, [clearTimer, updatePlayState]);

  const stopDictation = useCallback(() => {
    clearTimer();
    stopSpeech();
    updatePlayState("idle");
  }, [clearTimer, updatePlayState]);

  const handlePlayToggle = useCallback(() => {
    if (playState === "idle") {
      startDictation();
      return;
    }
    if (playState === "playing") {
      pauseDictation();
      return;
    }
    resumeDictation();
  }, [pauseDictation, playState, resumeDictation, startDictation]);

  const markWrong = useCallback(() => {
    if (!isActive || currentIndex >= wordList.length) return;
    const word = wordList[currentIndex]!;
    if (!wrongWords.includes(word)) {
      persistWrongWords([...wrongWords, word]);
    }
    setMarkedFlash(true);
    window.setTimeout(() => setMarkedFlash(false), 250);
  }, [currentIndex, isActive, persistWrongWords, wordList, wrongWords]);

  const exportWrong = useCallback(async () => {
    if (wrongWords.length === 0) {
      alert("错词本为空");
      return;
    }
    const text = wrongWords.join("\n");
    try {
      await navigator.clipboard.writeText(text);
      alert("已复制错词");
    } catch {
      alert(`错词:\n${text}`);
    }
  }, [wrongWords]);

  const clearWrong = useCallback(() => {
    if (wrongWords.length === 0) return;
    if (confirm("清空所有错词？")) {
      persistWrongWords([]);
    }
  }, [persistWrongWords, wrongWords]);

  const handlePhotoOcr = useCallback(
    async (file: File) => {
      if (ocrInFlightRef.current) return;
      ocrInFlightRef.current = true;
      setOcrBusy(true);
      try {
        const { words, rawText } = await ocrWordsFromImage(file, setOcrStatus);
        if (words.length === 0) {
          const hint = rawText ? `：${rawText.slice(0, 40)}` : "";
          setOcrStatus(`未识别到英文单词${hint}`);
          return;
        }
        const merged = [...parseWords(wordInput), ...words];
        setWordInput(merged.join("\n"));
        setOcrStatus(`已识别 ${words.length} 个单词`);
      } catch (error) {
        setOcrStatus(
          error instanceof Error ? error.message : "识别失败",
        );
      } finally {
        ocrInFlightRef.current = false;
        setOcrBusy(false);
      }
    },
    [wordInput],
  );

  const handleFileInputSelect = useCallback(
    (event: React.ChangeEvent<HTMLInputElement>) => {
      const input = event.target;
      const file = input.files?.[0];
      if (!file) return;
      setOcrStatus("已选图，准备识别…");
      void handlePhotoOcr(file).finally(() => {
        input.value = "";
      });
    },
    [handlePhotoOcr],
  );

  useEffect(() => {
    const onKeyDown = (event: KeyboardEvent) => {
      const target = event.target as HTMLElement;
      if (target.tagName === "INPUT" || target.tagName === "TEXTAREA") {
        return;
      }
      if (event.key === " " || event.code === "Space") {
        event.preventDefault();
        handlePlayToggle();
      }
      if (event.key === "m" || event.key === "M") {
        if (isActive) markWrong();
      }
      if (event.key === "Escape" && isActive) {
        stopDictation();
      }
    };
    document.addEventListener("keydown", onKeyDown);
    return () => document.removeEventListener("keydown", onKeyDown);
  }, [handlePlayToggle, isActive, markWrong, stopDictation]);

  useEffect(() => () => {
    clearTimer();
    stopSpeech();
  }, [clearTimer]);

  const displayWord = (() => {
    if (isFinished && playState === "idle") {
      return <span className="placeholder">🎉 完成</span>;
    }
    if (!isActive && wordList.length === 0) {
      return <span className="placeholder">准备</span>;
    }
    if (currentIndex >= wordList.length) {
      return <span className="placeholder">完成</span>;
    }
    return showWord ? wordList[currentIndex] : "???";
  })();

  return (
    <div className="app">
      {showInputSection ? (
        <div className="input-section">
          <textarea
            value={wordInput}
            onChange={(event) => setWordInput(event.target.value)}
            placeholder={"每行一个，或用逗号/空格分隔\n例：apple banana cat"}
            disabled={isActive}
          />
          <div className="input-meta">
            <span className="count">{wordCount} 个</span>
            <div className="group">
              <button
                type="button"
                className="btn btn-sm btn-outline"
                disabled={isActive}
                onClick={() => setWordInput(SAMPLE_WORDS)}
              >
                示例
              </button>
              <button
                type="button"
                className="btn btn-sm btn-outline"
                disabled={isActive}
                onClick={() => setWordInput("")}
              >
                清空
              </button>
            </div>
          </div>
        </div>
      ) : null}

      {!isActive ? (
        <div className="import-row">
          <label
            className={`btn btn-sm btn-outline file-label${ocrBusy ? " is-disabled" : ""}`}
          >
            <input
              type="file"
              accept="image/*"
              capture="environment"
              className="file-input-overlay"
              disabled={ocrBusy}
              onChange={handleFileInputSelect}
            />
            拍照识别
          </label>
          <label
            className={`btn btn-sm btn-outline file-label${ocrBusy ? " is-disabled" : ""}`}
          >
            <input
              type="file"
              accept="image/*"
              className="file-input-overlay"
              disabled={ocrBusy}
              onChange={handleFileInputSelect}
            />
            相册
          </label>
        </div>
      ) : null}

      {ocrStatus ? <div className="ocr-status">{ocrStatus}</div> : null}

      <div className="control-section">
        <div className="control-row">
          <span className="label">间隔</span>
          <div className="slider-wrap">
            <input
              type="range"
              min={1}
              max={10}
              step={0.5}
              value={intervalSec}
              disabled={isActive}
              onChange={(event) => setIntervalSec(Number(event.target.value))}
            />
            <span className="slider-value">{intervalSec}s</span>
          </div>
          <label className="inline-toggle">
            <input
              type="checkbox"
              checked={autoNext}
              disabled={isActive}
              onChange={(event) => setAutoNext(event.target.checked)}
            />
            自动
          </label>
        </div>

        <div className="main-bar">
          <button
            type="button"
            className={`btn btn-play ${playState === "playing" ? "playing" : ""}`}
            onClick={handlePlayToggle}
          >
            {playState === "idle" && "▶ 开始"}
            {playState === "playing" && "⏸ 暂停"}
            {playState === "paused" && "▶ 继续"}
          </button>
          <button
            type="button"
            className="btn btn-outline"
            disabled={!isActive}
            onClick={stopDictation}
          >
            ⏹ 结束
          </button>
        </div>
      </div>

      <div className="status-area">
        <div className="word-wrap">
          <span className={`word-display ${markedFlash ? "marked" : ""}`}>
            {displayWord}
          </span>
          <label className="show-toggle">
            <input
              type="checkbox"
              checked={showWord}
              onChange={(event) => setShowWord(event.target.checked)}
            />
            显示
          </label>
        </div>
        <div className="status-meta">
          <span className="progress-text">
            {wordList.length > 0
              ? `${Math.min(currentIndex, wordList.length)} / ${wordList.length}`
              : "0 / 0"}
          </span>
          <button
            type="button"
            className="mark-wrong-btn"
            disabled={!isActive || currentIndex >= wordList.length}
            onClick={markWrong}
          >
            ✕ 标记错词
          </button>
        </div>
      </div>

      <div className="wrong-section">
        <div className="wrong-header">
          <span>错词本</span>
          <div className="actions">
            <button
              type="button"
              className="btn btn-sm btn-outline"
              onClick={() => void exportWrong()}
            >
              导出
            </button>
            <button
              type="button"
              className="btn btn-sm btn-outline"
              onClick={clearWrong}
            >
              清空
            </button>
          </div>
        </div>
        {wrongWords.length === 0 ? (
          <div className="empty-hint">尚无错词</div>
        ) : (
          <div className="wrong-list">
            {wrongWords.map((word) => (
              <span key={word} className="wrong-tag">
                {word}
              </span>
            ))}
          </div>
        )}
      </div>

      <div className="footer">
        <kbd>空格</kbd> 播放/暂停 · <kbd>M</kbd> 标记错词 · <kbd>Esc</kbd> 结束
      </div>
    </div>
  );
}

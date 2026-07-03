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
type OcrMode = "append" | "replace";

const SAMPLE_WORDS = "apple banana cat dog elephant fish grape";

export default function App() {
  const [wordInput, setWordInput] = useState("apple banana cat dog elephant\n");
  const [intervalSec, setIntervalSec] = useState(3);
  const [autoNext, setAutoNext] = useState(true);
  const [showWord, setShowWord] = useState(false);
  const [playState, setPlayState] = useState<PlayState>("idle");
  const [wordList, setWordList] = useState<string[]>([]);
  const [currentIndex, setCurrentIndex] = useState(0);
  const [wrongWords, setWrongWords] = useState<string[]>(() =>
    loadWrongWords(),
  );
  const [markedFlash, setMarkedFlash] = useState(false);
  const [ocrStatus, setOcrStatus] = useState("");
  const [ocrBusy, setOcrBusy] = useState(false);
  const [ocrMode, setOcrMode] = useState<OcrMode>("replace");
  const [toast, setToast] = useState("");

  const timerRef = useRef<ReturnType<typeof setTimeout> | null>(null);
  const playStateRef = useRef(playState);
  const currentIndexRef = useRef(currentIndex);
  const wordListRef = useRef(wordList);
  const ocrInFlightRef = useRef(false);
  const toastTimerRef = useRef<ReturnType<typeof setTimeout> | null>(null);

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

  const showToast = useCallback((message: string) => {
    setToast(message);
    if (toastTimerRef.current) clearTimeout(toastTimerRef.current);
    toastTimerRef.current = setTimeout(() => setToast(""), 2200);
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
      showToast("请先输入单词列表");
      return;
    }

    clearTimer();
    stopSpeech();
    setWordList(words);
    setCurrentIndex(0);
    updatePlayState("playing");
    void playNextWord(0, words);
  }, [clearTimer, playNextWord, showToast, updatePlayState, wordInput]);

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
      showToast("错词本为空");
      return;
    }
    const text = wrongWords.join("\n");
    try {
      await navigator.clipboard.writeText(text);
      showToast(`已复制 ${wrongWords.length} 个错词`);
    } catch {
      showToast("复制失败，请手动选择");
    }
  }, [showToast, wrongWords]);

  const clearWrong = useCallback(() => {
    if (wrongWords.length === 0) return;
    if (confirm("清空所有错词？")) {
      persistWrongWords([]);
      showToast("已清空错词本");
    }
  }, [persistWrongWords, showToast, wrongWords]);

  const removeWrongWord = useCallback(
    (word: string) => {
      persistWrongWords(wrongWords.filter((item) => item !== word));
    },
    [persistWrongWords, wrongWords],
  );

  const handlePhotoOcr = useCallback(
    async (file: File, mode: OcrMode) => {
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
        const nextWords =
          mode === "replace" ? words : [...parseWords(wordInput), ...words];
        setWordInput(nextWords.join("\n"));
        const action = mode === "replace" ? "已替换为" : "已追加";
        setOcrStatus(`${action} ${words.length} 个单词`);
      } catch (error) {
        setOcrStatus(error instanceof Error ? error.message : "识别失败");
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
      void handlePhotoOcr(file, ocrMode).finally(() => {
        input.value = "";
      });
    },
    [handlePhotoOcr, ocrMode],
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

  useEffect(
    () => () => {
      clearTimer();
      stopSpeech();
      if (toastTimerRef.current) clearTimeout(toastTimerRef.current);
    },
    [clearTimer],
  );

  const isHidden = isActive && !showWord && currentIndex < wordList.length;
  const displayWord = (() => {
    if (isFinished && playState === "idle") {
      return <span className="text-indigo-600">🎉 全部完成</span>;
    }
    if (!isActive && wordList.length === 0) {
      return <span className="text-[#c7c7cf] font-normal">准备就绪</span>;
    }
    if (currentIndex >= wordList.length) {
      return <span className="text-[#c7c7cf] font-normal">完成</span>;
    }
    if (isHidden) {
      return <span className="tracking-[0.35em] text-[#c7c7cf]">• • •</span>;
    }
    return wordList[currentIndex];
  })();

  const markEnabled = isActive && currentIndex < wordList.length;
  const total = wordList.length;
  const progressPct =
    total > 0 ? (Math.min(currentIndex, total) / total) * 100 : 0;
  const positionText =
    total > 0
      ? `${Math.min(currentIndex + (isActive ? 1 : 0), total)} / ${total}`
      : "0 / 0";
  const sliderPct = ((intervalSec - 1) / (10 - 1)) * 100;

  const rootCls = [
    "w-full mx-auto bg-white px-[14px] pt-[14px] border border-[#ececf0]",
    "shadow-[0_8px_40px_-12px_rgba(0,0,0,0.12)]",
    isActive
      ? "pb-[max(16px,env(safe-area-inset-bottom))]"
      : "pb-[max(20px,env(safe-area-inset-bottom))]",
  ].join(" ");

  const fileLabelBase =
    "relative inline-flex items-center justify-center overflow-hidden cursor-pointer transition-all active:scale-[0.98]";
  const cameraCls = `${fileLabelBase} w-full gap-[10px] min-h-[54px] px-5 py-[14px] text-[17px] font-semibold text-white rounded-[16px] bg-gradient-to-br from-indigo-500 to-indigo-600 shadow-[0_6px_18px_-6px_rgba(79,70,229,0.6)] hover:from-indigo-500 hover:to-indigo-700${
    ocrBusy ? " opacity-50 pointer-events-none" : ""
  }`;
  const albumCls = `${fileLabelBase} shrink-0 min-h-[54px] px-[18px] text-sm font-medium text-[#4a4a52] border border-[#e5e5ea] rounded-[16px] bg-white hover:bg-[#f7f7f9]${
    ocrBusy ? " opacity-50 pointer-events-none" : ""
  }`;
  const fileInputCls =
    "absolute inset-0 w-full h-full m-0 p-0 opacity-0 cursor-pointer text-base";

  const ocrModeBtn = (active: boolean) =>
    `flex-1 rounded-[9px] text-[13px] font-medium cursor-pointer transition-all disabled:opacity-40 disabled:pointer-events-none ${
      active
        ? "bg-white text-[#1a1a1a] shadow-[0_1px_4px_rgba(0,0,0,0.1)]"
        : "text-[#8a8a92] hover:text-[#55555c]"
    }`;

  const smBtn =
    "px-3 py-[4px] text-xs font-medium text-[#55555c] border border-[#e5e5ea] rounded-full cursor-pointer transition-colors hover:bg-[#f5f5f7] active:bg-[#ececf0] disabled:opacity-40 disabled:pointer-events-none";

  const lgBase =
    "inline-flex items-center justify-center gap-1.5 px-5 font-semibold rounded-[15px] cursor-pointer transition-all active:scale-[0.98]";
  const lgActiveSize =
    "min-h-[56px] text-[18px] min-[520px]:min-h-[52px] min-[520px]:text-[17px]";
  const lgIdleSize = "min-h-[52px] text-[17px]";
  const barBtnSize = isActive ? lgActiveSize : lgIdleSize;

  const playCls = `flex-1 ${lgBase} ${barBtnSize} ${
    playState === "playing"
      ? "bg-white text-[#1a1a1a] border border-[#e5e5ea] hover:bg-[#f7f7f9]"
      : "text-white bg-gradient-to-br from-indigo-500 to-indigo-600 shadow-[0_6px_18px_-6px_rgba(79,70,229,0.6)] hover:from-indigo-500 hover:to-indigo-700"
  }`;
  const stopCls = `flex-1 ${lgBase} ${barBtnSize} border border-[#e5e5ea] text-[#55555c] bg-white hover:bg-[#f7f7f9] disabled:opacity-40 disabled:pointer-events-none`;
  const markCls = `w-full ${lgBase} ${
    markEnabled ? lgActiveSize : lgIdleSize
  } bg-rose-50 text-rose-600 hover:bg-rose-100 disabled:opacity-30 disabled:pointer-events-none`;

  const playbackCls = isActive
    ? "sticky bottom-[max(8px,env(safe-area-inset-bottom))] z-10 bg-white/90 backdrop-blur rounded-[20px] p-3 mx-[-4px] mb-[14px] border border-[#ececf0] shadow-[0_-6px_28px_-8px_rgba(0,0,0,0.12)] min-[520px]:static min-[520px]:shadow-none min-[520px]:border-none min-[520px]:bg-transparent min-[520px]:p-0 min-[520px]:mx-0 min-[520px]:mb-[14px]"
    : "mb-4";

  return (
    <div className={rootCls}>
      {wrongWords.length > 0 ? (
        <header className="flex items-center justify-between mb-4">
          <span className="text-xs font-medium text-rose-600 bg-rose-50 px-2.5 py-1 rounded-full">
            错词 {wrongWords.length}
          </span>
        </header>
      ) : null}

      {!isActive ? (
        <div className="mb-4 space-y-2.5">
          <div className="flex gap-2.5">
            <label className={cameraCls}>
              <input
                type="file"
                accept="image/*"
                capture="environment"
                className={fileInputCls}
                disabled={ocrBusy}
                onChange={handleFileInputSelect}
              />
              <span className="text-[20px] leading-none" aria-hidden>
                📷
              </span>
              {ocrBusy ? "识别中…" : "拍照识别"}
            </label>
            <label className={albumCls}>
              <input
                type="file"
                accept="image/*"
                className={fileInputCls}
                disabled={ocrBusy}
                onChange={handleFileInputSelect}
              />
              相册
            </label>
          </div>
          <div className="flex items-center gap-2.5">
            <span className="text-xs text-[#9a9aa2] shrink-0">识别后</span>
            <div
              className="flex flex-1 bg-[#f2f2f5] rounded-[11px] p-[3px] gap-[2px]"
              role="group"
              aria-label="识别后处理方式"
            >
              <button
                type="button"
                className={ocrModeBtn(ocrMode === "append")}
                disabled={ocrBusy}
                onClick={() => setOcrMode("append")}
              >
                追加
              </button>
              <button
                type="button"
                className={ocrModeBtn(ocrMode === "replace")}
                disabled={ocrBusy}
                onClick={() => setOcrMode("replace")}
              >
                替换
              </button>
            </div>
          </div>
          {ocrStatus ? (
            <div className="text-[13px] text-[#8a8a92] text-center bg-[#f7f7f9] rounded-[10px] py-2 px-3">
              {ocrStatus}
            </div>
          ) : null}
        </div>
      ) : null}

      {showInputSection ? (
        <div className="mb-[14px]">
          <textarea
            className="w-full h-[72px] border border-[#e8e8ec] rounded-[14px] px-[14px] py-3 text-base bg-[#fafafa] resize-y text-[#1a1a1a] leading-normal transition-all focus:outline-none focus:border-indigo-400 focus:ring-2 focus:ring-indigo-100 focus:bg-white"
            value={wordInput}
            onChange={(event) => setWordInput(event.target.value)}
            placeholder={"每行一个，或用逗号/空格分隔\n例：apple banana cat"}
            disabled={isActive}
          />
          <div className="flex justify-between items-center mt-[7px] text-xs text-[#aaa]">
            <span className="text-[#9a9aa2]">共 {wordCount} 个单词</span>
            <div className="flex gap-[6px]">
              <button
                type="button"
                className={smBtn}
                disabled={isActive}
                onClick={() => setWordInput(SAMPLE_WORDS)}
              >
                示例
              </button>
              <button
                type="button"
                className={smBtn}
                disabled={isActive}
                onClick={() => setWordInput("")}
              >
                清空
              </button>
            </div>
          </div>
        </div>
      ) : null}

      <div className="relative overflow-hidden bg-gradient-to-b from-[#fafafb] to-[#f4f4f7] rounded-[18px] mb-[14px] border border-[#eeeef2]">
        <div className="h-1 w-full bg-[#e8e8ee]">
          <div
            className="h-full bg-gradient-to-r from-indigo-500 to-indigo-600 rounded-r-full transition-[width] duration-300 ease-out"
            style={{ width: `${progressPct}%` }}
          />
        </div>
        <div className="px-4 pt-3 pb-4">
          <div className="flex items-center justify-between mb-2">
            <span className="text-xs text-[#9a9aa2] tabular-nums">
              {positionText}
            </span>
            <button
              type="button"
              onClick={() => setShowWord((v) => !v)}
              className={`flex items-center gap-1.5 text-[13px] font-medium select-none px-3 py-1.5 rounded-full border transition-colors ${
                showWord
                  ? "bg-indigo-50 text-indigo-600 border-indigo-600"
                  : "bg-white text-[#8a8a92] border-[#eaeaef]"
              }`}
            >
              {showWord ? "👁 显示中" : "🙈 已隐藏"}
            </button>
          </div>
          <div className="min-h-[76px] flex items-center justify-center text-center px-2">
            <span
              className={`text-[40px] font-semibold tracking-tight leading-tight break-words transition-all duration-200 ${
                markedFlash ? "text-rose-600 scale-105" : "text-[#111]"
              }`}
            >
              {displayWord}
            </span>
          </div>
        </div>
      </div>

      <div className={playbackCls}>
        {!isActive ? (
          <div className="flex flex-wrap items-center gap-y-[10px] gap-x-[14px] mb-3">
            <span className="text-[13px] text-[#9a9aa2] min-w-[30px]">
              间隔
            </span>
            <div className="flex-1 min-w-[100px] flex items-center gap-[10px]">
              <input
                type="range"
                className="flex-1 h-1.5 appearance-none rounded-full cursor-pointer"
                style={{
                  background: `linear-gradient(to right, #4f46e5 ${sliderPct}%, #e5e5ea ${sliderPct}%)`,
                }}
                min={1}
                max={10}
                step={0.5}
                value={intervalSec}
                onChange={(event) => setIntervalSec(Number(event.target.value))}
              />
              <span className="text-sm font-semibold text-indigo-600 min-w-[34px] text-center tabular-nums">
                {intervalSec}s
              </span>
            </div>
            <label className="flex items-center gap-[6px] text-sm text-[#8a8a92] cursor-pointer select-none min-h-[36px]">
              <input
                type="checkbox"
                className="accent-indigo-600 w-4 h-4"
                checked={autoNext}
                onChange={(event) => setAutoNext(event.target.checked)}
              />
              自动
            </label>
          </div>
        ) : null}

        <div className="flex gap-[10px] mb-[10px]">
          <button type="button" className={playCls} onClick={handlePlayToggle}>
            {playState === "idle" && "▶ 开始"}
            {playState === "playing" && "⏸ 暂停"}
            {playState === "paused" && "▶ 继续"}
          </button>
          <button
            type="button"
            className={stopCls}
            disabled={!isActive}
            onClick={stopDictation}
          >
            ⏹ 结束
          </button>
        </div>

        <button
          type="button"
          className={markCls}
          disabled={!isActive || currentIndex >= wordList.length}
          onClick={markWrong}
        >
          ✕ 标记错词
        </button>
      </div>

      <div className="border-t border-[#f0f0f3] pt-[14px]">
        <div className="flex justify-between items-center mb-[10px] text-sm text-[#8a8a92]">
          <span className="font-medium">错词本</span>
          <div className="flex gap-[6px]">
            <button
              type="button"
              className={smBtn}
              onClick={() => void exportWrong()}
            >
              导出
            </button>
            <button type="button" className={smBtn} onClick={clearWrong}>
              清空
            </button>
          </div>
        </div>
        {wrongWords.length === 0 ? (
          <div className="text-[13px] text-[#c2c2ca] py-2 text-center bg-[#fafafb] rounded-[12px]">
            尚无错词
          </div>
        ) : (
          <div className="flex flex-wrap gap-[6px]">
            {wrongWords.map((word) => (
              <button
                key={word}
                type="button"
                onClick={() => removeWrongWord(word)}
                title="点击移除"
                className="group inline-flex items-center gap-1.5 bg-[#f4f4f7] text-[#33333a] hover:bg-rose-50 hover:text-rose-600 pl-[14px] pr-[10px] py-[5px] rounded-full text-sm font-normal transition-colors cursor-pointer"
              >
                {word}
                <span className="text-[#c2c2ca] group-hover:text-rose-400 leading-none text-[15px]">
                  ×
                </span>
              </button>
            ))}
          </div>
        )}
      </div>

      <div className="hidden min-[520px]:block text-[11px] text-[#c2c2ca] text-center mt-4 pt-3 border-t border-[#f0f0f3]">
        <kbd className="bg-[#f4f4f7] px-[6px] rounded text-[10px] text-[#8a8a92]">
          空格
        </kbd>{" "}
        播放/暂停 ·{" "}
        <kbd className="bg-[#f4f4f7] px-[6px] rounded text-[10px] text-[#8a8a92]">
          M
        </kbd>{" "}
        标记错词 ·{" "}
        <kbd className="bg-[#f4f4f7] px-[6px] rounded text-[10px] text-[#8a8a92]">
          Esc
        </kbd>{" "}
        结束
      </div>

      {toast ? (
        <div className="fixed left-1/2 -translate-x-1/2 bottom-[max(24px,env(safe-area-inset-bottom))] z-50 animate-toast">
          <div className="bg-[#1a1a1a] text-white text-sm font-medium px-4 py-2.5 rounded-full shadow-[0_8px_24px_-6px_rgba(0,0,0,0.4)] whitespace-nowrap">
            {toast}
          </div>
        </div>
      ) : null}
    </div>
  );
}

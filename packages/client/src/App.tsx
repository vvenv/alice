import { useCallback, useEffect, useState } from "react";

import { OcrSection } from "./components/OcrSection";
import { PlaybackControls } from "./components/PlaybackControls";
import { ProgressCard } from "./components/ProgressCard";
import { Toast } from "./components/Toast";
import { WordInputSection } from "./components/WordInputSection";
import { WrongWordsPanel } from "./components/WrongWordsPanel";
import { useOcr } from "./hooks/useOcr";
import { usePlayback } from "./hooks/usePlayback";
import { useToast } from "./hooks/useToast";
import { useWrongWords } from "./hooks/useWrongWords";
import { loadTtsVoice, parseWords, saveTtsVoice } from "./lib/dictation";
import { ShortcutFooter } from "./components/ShortcutFooter";

const SAMPLE_WORDS = "apple banana cat dog elephant fish grape";

export default function App() {
  const [wordInput, setWordInput] = useState(
    "apple banana cat dog elephant\n",
  );
  const [intervalSec, setIntervalSec] = useState(8);
  const [autoNext, setAutoNext] = useState(true);
  const [voice, setVoice] = useState(() => loadTtsVoice());
  const [showWord, setShowWord] = useState(false);

  const { toast, showToast } = useToast();

  const playback = usePlayback({ intervalSec, autoNext, voice });

  const handleVoiceChange = useCallback((next: string) => {
    setVoice(next);
    saveTtsVoice(next);
  }, []);

  const {
    wrongWords,
    markedFlash,
    markWrong,
    exportWrong,
    clearWrong,
    removeWrongWord,
  } = useWrongWords();

  const handleOcrResult = useCallback(
    (words: string[], mode: "append" | "replace") => {
      const nextWords =
        mode === "replace"
          ? words
          : [...parseWords(wordInput), ...words];
      setWordInput(nextWords.join("\n"));
    },
    [wordInput],
  );

  const ocr = useOcr(handleOcrResult);

  const isActive = playback.isActive;
  const showInputSection = !isActive || showWord;

  // mark the current word as wrong
  const handleMarkWrong = useCallback(() => {
    if (!isActive || playback.currentIndex >= playback.wordList.length) return;
    markWrong(playback.wordList[playback.currentIndex]!);
  }, [isActive, markWrong, playback.currentIndex, playback.wordList]);

  // handle play/pause toggle (idle → parse & start, playing → pause, paused → resume)
  const handlePlayToggle = useCallback(() => {
    if (playback.playState === "idle") {
      const words = parseWords(wordInput);
      if (words.length === 0) {
        showToast("请先输入单词列表");
        return;
      }
      playback.startDictation(words);
      return;
    }
    if (playback.playState === "playing") {
      playback.pauseDictation();
      return;
    }
    playback.resumeDictation();
  }, [playback, showToast, wordInput]);

  // export wrong words
  const handleExportWrong = useCallback(async () => {
    const msg = await exportWrong();
    if (msg) showToast(msg);
  }, [exportWrong, showToast]);

  // clear wrong words
  const handleClearWrong = useCallback(() => {
    if (wrongWords.length === 0) return;
    if (confirm("清空所有错词？")) {
      const msg = clearWrong();
      showToast(msg);
    }
  }, [clearWrong, wrongWords, showToast]);

  // keyboard shortcuts
  useEffect(() => {
    const onKeyDown = (event: KeyboardEvent) => {
      const target = event.target as HTMLElement;
      if (
        target.tagName === "INPUT" ||
        target.tagName === "TEXTAREA" ||
        target.tagName === "SELECT"
      ) {
        return;
      }
      if (event.key === " " || event.code === "Space") {
        event.preventDefault();
        handlePlayToggle();
      }
      if (event.key === "m" || event.key === "M") {
        if (isActive) handleMarkWrong();
      }
      if (event.key === "Escape" && isActive) {
        playback.stopDictation();
      }
    };
    document.addEventListener("keydown", onKeyDown);
    return () => document.removeEventListener("keydown", onKeyDown);
  }, [handleMarkWrong, handlePlayToggle, isActive, playback.stopDictation]);

  return (
    <div
      className="flex-1 w-full max-w-md mx-auto bg-background px-4 pt-4 pb-[env(safe-area-inset-bottom)] flex flex-col gap-4"
    >
      {!isActive ? (
        <OcrSection
          ocrBusy={ocr.ocrBusy}
          ocrMode={ocr.ocrMode}
          ocrStatus={ocr.ocrStatus}
          onOcrModeChange={ocr.setOcrMode}
          onFileSelect={ocr.handleFileInputSelect}
        />
      ) : null}

      {showInputSection ? (
        <WordInputSection
          value={wordInput}
          disabled={isActive}
          onChange={setWordInput}
          onSetSample={() => setWordInput(SAMPLE_WORDS)}
          onClear={() => setWordInput("")}
        />
      ) : null}

      <ProgressCard
        wordList={playback.wordList}
        currentIndex={playback.currentIndex}
        playState={playback.playState}
        showWord={showWord}
        onToggleShowWord={() => setShowWord((v) => !v)}
        markedFlash={markedFlash}
        wrongWords={wrongWords}
      />

      <PlaybackControls
        playState={playback.playState}
        intervalSec={intervalSec}
        autoNext={autoNext}
        voice={voice}
        remainingMs={playback.remainingMs}
        currentIndex={playback.currentIndex}
        wordList={playback.wordList}
        onIntervalChange={setIntervalSec}
        onAutoNextChange={setAutoNext}
        onVoiceChange={handleVoiceChange}
        onPlayToggle={handlePlayToggle}
        onStop={playback.stopDictation}
        onMarkWrong={handleMarkWrong}
      />

      <WrongWordsPanel
        wrongWords={wrongWords}
        onExport={handleExportWrong}
        onClear={handleClearWrong}
        onRemove={removeWrongWord}
      />

      <ShortcutFooter />

      <Toast message={toast} />
    </div>
  );
}

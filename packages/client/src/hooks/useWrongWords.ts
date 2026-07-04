import { useCallback, useState } from "react";

import { loadWrongWords, saveWrongWords } from "../lib/dictation";

export function useWrongWords() {
  const [wrongWords, setWrongWords] = useState<string[]>(() =>
    loadWrongWords(),
  );
  const [markedFlash, setMarkedFlash] = useState(false);

  const persistWrongWords = useCallback((words: string[]) => {
    setWrongWords(words);
    saveWrongWords(words);
  }, []);

  const markWrong = useCallback(
    (word: string) => {
      setWrongWords((prev) => {
        if (prev.includes(word)) return prev;
        const next = [...prev, word];
        saveWrongWords(next);
        return next;
      });
      setMarkedFlash(true);
      window.setTimeout(() => setMarkedFlash(false), 250);
    },
    [],
  );

  const exportWrong = useCallback(async () => {
    if (wrongWords.length === 0) return "";
    try {
      await navigator.clipboard.writeText(wrongWords.join("\n"));
      return `已复制 ${wrongWords.length} 个错词`;
    } catch {
      return "复制失败，请手动选择";
    }
  }, [wrongWords]);

  const clearWrong = useCallback(() => {
    persistWrongWords([]);
    return "已清空错词本";
  }, [persistWrongWords]);

  const removeWrongWord = useCallback(
    (word: string) => {
      persistWrongWords(wrongWords.filter((item) => item !== word));
    },
    [persistWrongWords, wrongWords],
  );

  return {
    wrongWords,
    markedFlash,
    markWrong,
    exportWrong,
    clearWrong,
    removeWrongWord,
    hasWrongWords: wrongWords.length > 0,
  };
}

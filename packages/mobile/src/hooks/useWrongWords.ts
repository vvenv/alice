import { useCallback, useState } from "react";

import { loadWrongWords, saveWrongWords } from "../lib/storage";

export function useWrongWords(initialWords?: string[]) {
  const [wrongWords, setWrongWords] = useState<string[]>(
    () => initialWords ?? loadWrongWords(),
  );
  const [markedFlash, setMarkedFlash] = useState(false);

  const markWrong = useCallback((word: string) => {
    setWrongWords((prev) => {
      if (prev.includes(word)) return prev;
      const next = [...prev, word];
      saveWrongWords(next);
      return next;
    });
    setMarkedFlash(true);
    setTimeout(() => setMarkedFlash(false), 250);
  }, []);

  const exportWrong = useCallback(async () => {
    if (wrongWords.length === 0) return "";
    const Clipboard = await import("expo-clipboard");
    await Clipboard.setStringAsync(wrongWords.join("\n"));
    return `已复制 ${wrongWords.length} 个错词`;
  }, [wrongWords]);

  const clearWrong = useCallback(() => {
    saveWrongWords([]);
    setWrongWords([]);
    return "已清空错词本";
  }, []);

  const removeWrongWord = useCallback(
    (word: string) => {
      const next = wrongWords.filter((item) => item !== word);
      setWrongWords(next);
      saveWrongWords(next);
    },
    [wrongWords],
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

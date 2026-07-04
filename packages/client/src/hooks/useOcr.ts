import { useCallback, useRef, useState } from "react";

import { ocrWordsFromImage } from "../lib/dictation";

export type OcrMode = "append" | "replace";

export function useOcr(
  onOcrResult: (words: string[], mode: OcrMode) => void,
) {
  const [ocrStatus, setOcrStatus] = useState("");
  const [ocrBusy, setOcrBusy] = useState(false);
  const [ocrMode, setOcrMode] = useState<OcrMode>("replace");
  const ocrInFlightRef = useRef(false);

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
        onOcrResult(words, mode);
        const action = mode === "replace" ? "已替换为" : "已追加";
        setOcrStatus(`${action} ${words.length} 个单词`);
      } catch (error) {
        setOcrStatus(error instanceof Error ? error.message : "识别失败");
      } finally {
        ocrInFlightRef.current = false;
        setOcrBusy(false);
      }
    },
    [onOcrResult],
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

  return {
    ocrStatus,
    ocrBusy,
    ocrMode,
    setOcrMode,
    handleFileInputSelect,
  };
}

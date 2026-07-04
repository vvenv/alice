import type { ReactNode } from "react";

interface ProgressCardProps {
  wordList: string[];
  currentIndex: number;
  playState: "idle" | "playing" | "paused";
  showWord: boolean;
  onToggleShowWord: () => void;
  markedFlash: boolean;
  wrongWords: string[];
}

export function ProgressCard({
  wordList,
  currentIndex,
  playState,
  showWord,
  onToggleShowWord,
  markedFlash,
  wrongWords,
}: ProgressCardProps) {
  const isActive = playState === "playing" || playState === "paused";
  const isFinished = wordList.length > 0 && currentIndex >= wordList.length;
  const total = wordList.length;

  const currentPosition =
    total > 0
      ? Math.min(currentIndex + (isActive ? 1 : 0), total)
      : 0;

  const progressPct =
    total > 0
      ? (Math.min(currentIndex, total) / total) * 100
      : 0;

  const positionText = total > 0 ? `${currentPosition} / ${total}` : "0 / 0";

  const hasWrongWords = wrongWords.length > 0;
  const wrongWordsCount = wrongWords.length;

  const isHidden = isActive && !showWord && currentIndex < wordList.length;

  const displayWord: ReactNode = (() => {
    if (isFinished && playState === "idle") {
      return <span className="text-primary">🎉 全部完成</span>;
    }
    if (!isActive && wordList.length === 0) {
      return <span className="text-subtle font-normal">准备就绪</span>;
    }
    if (currentIndex >= wordList.length) {
      return <span className="text-subtle font-normal">完成</span>;
    }
    if (isHidden) {
      return <span className="tracking-[0.35em] text-subtle">• • •</span>;
    }
    return wordList[currentIndex];
  })();

  return (
    <div className="card">
      <div className="h-1 w-full bg-track">
        <div
          className="h-full bg-linear-to-r from-primary-light to-primary rounded-r-full transition-[width] duration-300 ease-out"
          style={{ width: `${progressPct}%` }}
        />
      </div>
      <div className="px-4 pt-3 pb-4">
        <div className="flex items-center justify-between mb-2">
          <span className="text-xl text-muted tabular-nums">
            {hasWrongWords ? (
              <>
                {currentPosition}
                {" / "}
                <span className="text-danger font-semibold">
                  {wrongWordsCount}
                </span>
                {" / "}
                {total}
              </>
            ) : (
              positionText
            )}
          </span>
          <button
            type="button"
            onClick={onToggleShowWord}
            className={`flex items-center gap-2 text-sm font-medium select-none px-4 py-2 rounded-full border transition-colors ${
              showWord
                ? "bg-primary-soft text-primary border-primary"
                : "bg-background text-muted border-border-muted"
            }`}
          >
            {showWord ? "👁 显示中" : "🙈 已隐藏"}
          </button>
        </div>
        <div className="min-h-20 flex items-center justify-center text-center px-2">
          <span
            className={`text-4xl font-semibold tracking-tight leading-tight wrap-break-word transition-all duration-200 ${
              markedFlash ? "text-danger scale-105" : "text-foreground"
            }`}
          >
            {displayWord}
          </span>
        </div>
      </div>
    </div>
  );
}

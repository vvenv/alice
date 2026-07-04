interface WrongWordsPanelProps {
  wrongWords: string[];
  onExport: () => void;
  onClear: () => void;
  onRemove: (word: string) => void;
}

export function WrongWordsPanel({
  wrongWords,
  onExport,
  onClear,
  onRemove,
}: WrongWordsPanelProps) {
  const hasWrongWords = wrongWords.length > 0;
  return (
    <div className="border-t border-border-subtle pt-4">
      <div className="flex justify-between items-center mb-3 text-sm text-muted">
        <span className="font-medium">错词本</span>
        <div className="flex gap-2">
          <button type="button" className="btn-sm" onClick={onExport}>
            导出
          </button>
          <button type="button" className="btn-sm" onClick={onClear}>
            清空
          </button>
        </div>
      </div>
      {!hasWrongWords ? (
        <div className="text-sm text-subtle py-2 text-center bg-surface-sunken rounded-xl">
          尚无错词
        </div>
      ) : (
        <div className="flex flex-wrap gap-2">
          {wrongWords.map((word) => (
            <button
              key={word}
              type="button"
              onClick={() => onRemove(word)}
              title="点击移除"
              className="group inline-flex items-center gap-2 bg-surface-raised text-foreground/80 hover:bg-danger-soft hover:text-danger pl-4 pr-3 py-1 rounded-full text-sm font-normal transition-colors cursor-pointer"
            >
              {word}
              <span className="text-subtle group-hover:text-danger-muted leading-none text-base">
                ×
              </span>
            </button>
          ))}
        </div>
      )}
    </div>
  );
}

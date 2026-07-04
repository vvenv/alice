import { useMemo } from "react";
import { parseWords } from "../lib/dictation";

interface WordInputSectionProps {
  value: string;
  disabled: boolean;
  onChange: (value: string) => void;
  onSetSample: () => void;
  onClear: () => void;
}

export function WordInputSection({
  value,
  disabled,
  onChange,
  onSetSample,
  onClear,
}: WordInputSectionProps) {
  const wordCount = useMemo(() => parseWords(value).length, [value]);

  return (
    <div className="flex flex-col gap-2">
      <textarea
        rows={2}
        className="w-full border border-border rounded-card px-4 py-3 text-base bg-surface-sunken field-sizing-content resize-none text-foreground leading-normal transition-all focus:outline-none focus:border-primary-focus focus:ring-2 focus:ring-primary-ring focus:bg-background"
        value={value}
        onChange={(event) => onChange(event.target.value)}
        placeholder={"每行一个，或用逗号/空格分隔\n例：apple banana cat"}
        disabled={disabled}
      />
      <div className="flex justify-between items-center text-xs text-subtle">
        <span className="text-muted">共 {wordCount} 个单词</span>
        <div className="flex gap-2">
          <button
            type="button"
            className="btn-sm"
            disabled={disabled}
            onClick={onSetSample}
          >
            示例
          </button>
          <button
            type="button"
            className="btn-sm"
            disabled={disabled}
            onClick={onClear}
          >
            清空
          </button>
        </div>
      </div>
    </div>
  );
}

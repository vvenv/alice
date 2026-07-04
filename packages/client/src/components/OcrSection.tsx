import type { OcrMode } from "../hooks/useOcr";

interface OcrSectionProps {
  ocrBusy: boolean;
  ocrMode: OcrMode;
  ocrStatus: string;
  onOcrModeChange: (mode: OcrMode) => void;
  onFileSelect: (event: React.ChangeEvent<HTMLInputElement>) => void;
}

function ocrModeBtn(active: boolean) {
  return `flex-1 rounded-lg text-sm font-medium cursor-pointer transition-all disabled:opacity-40 disabled:pointer-events-none ${
    active
      ? "bg-background text-foreground shadow-raised"
      : "text-muted hover:text-secondary"
  }`;
}

export function OcrSection({
  ocrBusy,
  ocrMode,
  ocrStatus,
  onOcrModeChange,
  onFileSelect,
}: OcrSectionProps) {
  return (
    <div className="flex flex-col gap-3">
      <div className="flex items-center gap-3">
        <label
          className={`relative btn-primary btn-lg w-full flex items-center gap-3 p-4 text-xl ${
            ocrBusy ? "opacity-50 pointer-events-none" : ""
          }`}
        >
          <input
            type="file"
            accept="image/*"
            capture="environment"
            className="absolute inset-0 w-full h-full opacity-0 cursor-pointer"
            disabled={ocrBusy}
            onChange={onFileSelect}
          />
          <span className="text-3xl leading-none" aria-hidden>
            📷
          </span>
          {ocrBusy ? "识别中…" : "拍照识别"}
        </label>
        <label
          className={`relative w-full flex items-center justify-center gap-3 p-4 font-medium border border-border rounded-2xl bg-background hover:bg-surface ${
            ocrBusy ? "opacity-50 pointer-events-none" : ""
          }`}
        >
          <input
            type="file"
            accept="image/*"
            className="absolute inset-0 w-full h-full opacity-0 cursor-pointer"
            disabled={ocrBusy}
            onChange={onFileSelect}
          />
          <span className="text-lg leading-none" aria-hidden>
            🖼️
          </span>
          相册
        </label>
      </div>
      <div className="flex items-center gap-3">
        <span className="text-xs text-muted shrink-0">识别后</span>
        <div
          className="flex flex-1 gap-1.5 bg-surface-raised rounded-xl p-1.5"
          role="group"
          aria-label="识别后处理方式"
        >
          <button
            type="button"
            className={`flex-1 text-center rounded-lg px-2 py-1.5 text-sm font-medium cursor-pointer transition-all ${
              ocrMode === "append"
                ? "bg-background text-foreground shadow-raised"
                : "text-muted hover:text-secondary"
            }`}
            disabled={ocrBusy}
            onClick={() => onOcrModeChange("append")}
          >
            追加
          </button>
          <button
            type="button"
            className={`flex-1 text-center rounded-lg px-2 py-1.5 text-sm font-medium cursor-pointer transition-all ${
              ocrMode === "replace"
                ? "bg-background text-foreground shadow-raised"
                : "text-muted hover:text-secondary"
            }`}
            disabled={ocrBusy}
            onClick={() => onOcrModeChange("replace")}
          >
            替换
          </button>
        </div>
      </div>
      {ocrStatus ? (
        <div className="text-sm text-muted text-center bg-surface rounded-xl py-2 px-3">
          {ocrStatus}
        </div>
      ) : null}
    </div>
  );
}

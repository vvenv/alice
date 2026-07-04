import type { OcrMode } from "../hooks/useOcr";

interface OcrSectionProps {
  ocrBusy: boolean;
  ocrMode: OcrMode;
  ocrStatus: string;
  onOcrModeChange: (mode: OcrMode) => void;
  onFileSelect: (event: React.ChangeEvent<HTMLInputElement>) => void;
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
          className={`relative btn-lg btn-ghost w-full flex items-center justify-center gap-3 p-4 ${
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
        <div className="segment" role="group" aria-label="识别后处理方式">
          <button
            type="button"
            className={`segment__item ${
              ocrMode === "append" ? "segment__item--active" : ""
            }`}
            disabled={ocrBusy}
            onClick={() => onOcrModeChange("append")}
          >
            追加
          </button>
          <button
            type="button"
            className={`segment__item ${
              ocrMode === "replace" ? "segment__item--active" : ""
            }`}
            disabled={ocrBusy}
            onClick={() => onOcrModeChange("replace")}
          >
            替换
          </button>
        </div>
      </div>
      {ocrStatus ? (
        <div className="text-sm text-muted text-center bg-surface rounded-surface py-2 px-3">
          {ocrStatus}
        </div>
      ) : null}
    </div>
  );
}

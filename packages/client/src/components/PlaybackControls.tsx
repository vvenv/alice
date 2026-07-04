import { SYSTEM_TTS_VOICES } from "../lib/dictation";

type PlayState = "idle" | "playing" | "paused";

interface PlaybackControlsProps {
  playState: PlayState;
  intervalSec: number;
  autoNext: boolean;
  voice: string;
  remainingMs: number | null;
  currentIndex: number;
  wordList: string[];
  onIntervalChange: (sec: number) => void;
  onAutoNextChange: (auto: boolean) => void;
  onVoiceChange: (voice: string) => void;
  onPlayToggle: () => void;
  onStop: () => void;
  onSkipNext: () => void;
  onMarkWrong: () => void;
}

export function PlaybackControls({
  playState,
  intervalSec,
  autoNext,
  voice,
  remainingMs,
  currentIndex,
  wordList,
  onIntervalChange,
  onAutoNextChange,
  onVoiceChange,
  onPlayToggle,
  onStop,
  onSkipNext,
  onMarkWrong,
}: PlaybackControlsProps) {
  const isActive = playState === "playing" || playState === "paused";
  const markEnabled = isActive && currentIndex < wordList.length;
  const skipEnabled = isActive && currentIndex < wordList.length;
  const sliderPct = ((intervalSec - 1) / (10 - 1)) * 100;
  const intervalMs = intervalSec * 1000;
  const countdownScale =
    remainingMs !== null && intervalMs > 0 ? remainingMs / intervalMs : 0;
  const countdownLabel =
    remainingMs !== null ? `${Math.ceil(remainingMs / 1000)}s` : "—";

  return (
    <div
      className={`flex flex-col gap-2 ${
        isActive
          ? "sticky bottom-[max(8px,env(safe-area-inset-bottom))] z-10 bg-background/90 backdrop-blur rounded-card p-3 -mx-1 border border-border-muted shadow-sticky md:static md:shadow-none md:border-none md:bg-transparent md:p-0 md:mx-0 md:mb-4"
          : ""
      }`}
    >
      {!isActive ? (
        <div className="flex items-center gap-3">
          <span className="text-sm text-muted shrink-0">音色</span>
          <div className="segment" role="radiogroup" aria-label="音色">
            {SYSTEM_TTS_VOICES.map((item) => {
              const active = voice === item.id;
              return (
                <label
                  key={item.id}
                  className={`segment__item ${
                    active ? "segment__item--active" : ""
                  }`}
                >
                  <input
                    type="radio"
                    name="tts-voice"
                    className="sr-only"
                    value={item.id}
                    checked={active}
                    onChange={() => onVoiceChange(item.id)}
                  />
                  {item.label}
                </label>
              );
            })}
          </div>
        </div>
      ) : null}

      <div className="flex items-center gap-3">
        <span className="text-sm text-muted shrink-0">
          {isActive ? "下一词" : "间隔"}
        </span>
        <div className="flex-1 flex items-center gap-3">
          {isActive ? (
            <div className="flex-1 h-2 rounded-full bg-border overflow-hidden">
              <div
                className="h-full w-full bg-primary rounded-full origin-left will-change-transform"
                style={{ transform: `scaleX(${countdownScale})` }}
              />
            </div>
          ) : (
            <input
              type="range"
              className="flex-1 h-2 appearance-none rounded-full cursor-pointer"
              style={{
                background: `linear-gradient(to right, var(--color-primary) ${sliderPct}%, var(--color-border) ${sliderPct}%)`,
              }}
              min={1}
              max={10}
              step={0.5}
              value={intervalSec}
              onChange={(event) => onIntervalChange(Number(event.target.value))}
            />
          )}
          <span className="text-sm font-semibold text-primary min-w-9 text-center tabular-nums">
            {isActive ? countdownLabel : `${intervalSec.toFixed(1)}s`}
          </span>
        </div>
        {!isActive ? (
          <label className="flex items-center gap-2 text-sm text-muted cursor-pointer select-none min-h-9">
            <input
              type="checkbox"
              className="accent-primary w-4 h-4"
              checked={autoNext}
              onChange={(event) => onAutoNextChange(event.target.checked)}
            />
            自动
          </label>
        ) : null}
      </div>

      <div className="flex items-center gap-3">
        <button
          type="button"
          className={`flex-1 btn-lg ${isActive ? "btn-lg--active" : "btn-lg--idle"} ${
            playState === "playing"
              ? "bg-background text-foreground border border-border hover:bg-surface"
              : "btn-primary"
          }`}
          onClick={onPlayToggle}
        >
          {playState === "idle" && "▶ 开始"}
          {playState === "playing" && "⏸ 暂停"}
          {playState === "paused" && "▶ 继续"}
        </button>
        {isActive ? (
          <button
            type="button"
            className={`flex-1 btn-lg btn-lg--active btn-ghost`}
            disabled={!skipEnabled}
            onClick={onSkipNext}
          >
            ⏭ 跳过
          </button>
        ) : null}
        <button
          type="button"
          className={`flex-1 btn-lg ${isActive ? "btn-lg--active" : "btn-lg--idle"} btn-ghost`}
          disabled={!isActive}
          onClick={onStop}
        >
          ⏹ 结束
        </button>
      </div>

      <button
        type="button"
        className={`w-full btn-lg ${
          markEnabled ? "btn-lg--active" : "btn-lg--idle"
        } btn-marker`}
        disabled={!markEnabled}
        onClick={onMarkWrong}
      >
        ✕ 标记错词
      </button>
    </div>
  );
}

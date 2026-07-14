import type { ReactNode } from "react";

/**
 * 手机外框模拟器，用于在官网中展示应用界面。
 */
export function PhoneFrame({
  children,
  className = "",
}: {
  children: ReactNode;
  className?: string;
}) {
  return (
    <div className={`relative ${className}`}>
      {/* 手机外框 */}
      <div className="relative w-[280px] rounded-[2.8rem] border-[3px] border-ink/80 bg-ink p-2 shadow-[0_30px_60px_-20px_rgba(26,43,74,0.4),0_0_0_1px_rgba(26,43,74,0.1)]">
        {/* 屏幕 */}
        <div className="relative overflow-hidden rounded-[2.2rem] bg-paper">
          {/* 刘海 */}
          <div className="absolute left-1/2 top-0 z-10 h-6 w-28 -translate-x-1/2 rounded-b-2xl bg-ink" />
          {/* 状态栏 */}
          <div className="flex items-center justify-between px-6 pt-2 pb-1 text-[10px] font-medium text-ink/70">
            <span>9:41</span>
            <span className="flex items-center gap-1">
              <span className="inline-block h-2 w-3 rounded-sm border border-ink/40" />
              <span className="inline-block h-2 w-2 rounded-full border border-ink/40" />
            </span>
          </div>
          {/* 内容区 */}
          <div className="px-4 pb-6 pt-2">{children}</div>
        </div>
      </div>
    </div>
  );
}

/** 听写界面模拟 */
export function DictationScreenMock() {
  return (
    <div className="space-y-3">
      {/* 顶部标题 */}
      <div className="flex items-center justify-between pt-2">
        <span className="text-xs text-ink/50">‹ 返回</span>
        <span className="font-display text-sm font-semibold text-ink">
          听写中
        </span>
        <span className="text-xs text-gold">3 / 12</span>
      </div>
      {/* 进度条 */}
      <div className="h-1 w-full overflow-hidden rounded-full bg-ink/10">
        <div className="h-full w-1/4 rounded-full bg-rose" />
      </div>
      {/* 当前单词卡 */}
      <div className="mt-4 rounded-2xl border border-gold/20 bg-parchment/60 p-5 text-center">
        <div className="mb-1 text-[10px] uppercase tracking-widest text-gold/70">
          Now Playing
        </div>
        <div className="font-display text-3xl font-bold text-ink tracking-tight">
          curiosity
        </div>
        <div className="mt-1 text-[11px] text-ink/50">n. 好奇心</div>
        <div className="mt-3 flex items-center justify-center gap-3 text-ink/40">
          <span className="text-lg">⏮</span>
          <span className="flex h-9 w-9 items-center justify-center rounded-full bg-rose text-paper">
            ▶
          </span>
          <span className="text-lg">⏭</span>
        </div>
      </div>
      {/* 控制 */}
      <div className="flex items-center justify-between rounded-xl bg-ink/5 px-3 py-2.5 text-[11px] text-ink/60">
        <span>间隔 4s</span>
        <span className="font-medium text-ink/80">自动连播</span>
        <span className="text-rose">标记错词</span>
      </div>
      {/* 单词列表 */}
      <div className="space-y-1.5">
        {[
          { w: "adventure", s: true },
          { w: "wonderland", s: true },
          { w: "curiosity", s: false, cur: true },
          { w: "rabbit-hole", s: false },
        ].map((item) => (
          <div
            key={item.w}
            className={`flex items-center justify-between rounded-lg px-3 py-1.5 text-xs ${
              item.cur ? "bg-rose/10 text-rose" : "text-ink/60"
            }`}
          >
            <span className="font-medium">{item.w}</span>
            {item.s ? (
              <span className="text-gold/50">✓</span>
            ) : item.cur ? (
              <span className="text-rose">●</span>
            ) : (
              <span className="text-ink/20">—</span>
            )}
          </div>
        ))}
      </div>
    </div>
  );
}

/** 拍照识别界面模拟 */
export function OcrScreenMock() {
  return (
    <div className="space-y-3">
      <div className="flex items-center justify-between pt-2">
        <span className="text-xs text-ink/50">‹ 返回</span>
        <span className="font-display text-sm font-semibold text-ink">
          拍照识别
        </span>
        <span className="text-xs text-ink/30">⚡</span>
      </div>
      {/* 取景框 */}
      <div className="relative mt-2 h-40 overflow-hidden rounded-2xl bg-ink/90">
        {/* 模拟书本内容 */}
        <div className="absolute inset-4 space-y-1.5">
          {[
            "adventure  n. 冒险",
            "curiosity  n. 好奇心",
            "rabbit-hole  n. 兔洞",
            "wonderland  n. 仙境",
          ].map((line, i) => (
            <div
              key={line}
              className={`rounded px-2 py-0.5 text-[10px] ${
                i < 2 ? "bg-gold/20 text-paper" : "text-paper/40"
              }`}
            >
              {line}
            </div>
          ))}
        </div>
        {/* 取景角标 */}
        <div className="absolute left-3 top-3 h-4 w-4 border-l-2 border-t-2 border-rose" />
        <div className="absolute right-3 top-3 h-4 w-4 border-r-2 border-t-2 border-rose" />
        <div className="absolute bottom-3 left-3 h-4 w-4 border-b-2 border-l-2 border-rose" />
        <div className="absolute bottom-3 right-3 h-4 w-4 border-b-2 border-r-2 border-rose" />
      </div>
      <div className="rounded-xl bg-rose/10 px-3 py-2 text-center text-[11px] text-rose">
        ✓ 已识别 4 个单词
      </div>
      <div className="flex justify-center">
        <div className="flex h-12 w-12 items-center justify-center rounded-full border-2 border-ink bg-rose">
          <div className="h-8 w-8 rounded-full border-2 border-paper" />
        </div>
      </div>
    </div>
  );
}

/** 错词本界面模拟 */
export function WrongWordsMock() {
  const words = [
    { w: "miscellaneous", m: "adj. 混杂的", count: 3 },
    { w: "conscientious", m: "adj. 认真的", count: 2 },
    { w: "rendezvous", m: "n. 约会", count: 4 },
    { w: "bureaucracy", m: "n. 官僚主义", count: 2 },
    { w: "silhouette", m: "n. 剪影", count: 1 },
  ];
  return (
    <div className="space-y-3">
      <div className="flex items-center justify-between pt-2">
        <span className="font-display text-sm font-semibold text-ink">
          错词本
        </span>
        <span className="rounded-full bg-rose/15 px-2 py-0.5 text-[10px] text-rose">
          12 词
        </span>
      </div>
      <div className="rounded-xl bg-ink/5 px-3 py-2 text-[11px] text-ink/60">
        共 12 个错词 · 已练习 3 次
      </div>
      <div className="space-y-1.5">
        {words.map((item) => (
          <div
            key={item.w}
            className="flex items-center justify-between rounded-lg border border-ink/8 bg-paper px-3 py-2"
          >
            <div>
              <div className="text-xs font-semibold text-ink">{item.w}</div>
              <div className="text-[10px] text-ink/40">{item.m}</div>
            </div>
            <div className="flex items-center gap-2">
              <span className="text-[10px] text-rose">×{item.count}</span>
              <span className="h-4 w-4 rounded-full border border-ink/20 text-[8px] leading-4 text-ink/40 text-center">
                ↻
              </span>
            </div>
          </div>
        ))}
      </div>
      <div className="rounded-lg bg-ink px-3 py-2 text-center text-[11px] font-medium text-paper">
        导出错词到剪贴板
      </div>
    </div>
  );
}

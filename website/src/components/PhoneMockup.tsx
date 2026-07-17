import type { ReactNode } from "react";

/**
 * 手机外框模拟器，用于在官网中展示应用界面。
 * 各屏内容均按 App 真实浅色 UI 还原。
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

/** 怀表倒计时圆环（听写屏核心元素） */
function CountdownRingMock() {
  // r=88, 周长 ≈ 553；金色弧约占 1/5
  return (
    <div className="relative mx-auto h-[196px] w-[196px]">
      <svg viewBox="0 0 196 196" className="h-full w-full -rotate-90">
        <circle
          cx="98"
          cy="98"
          r="90"
          fill="none"
          strokeWidth="6"
          className="stroke-ink/8"
        />
        <circle
          cx="98"
          cy="98"
          r="90"
          fill="none"
          strokeWidth="6"
          strokeLinecap="round"
          strokeDasharray="110 456"
          className="stroke-gold"
        />
      </svg>
      {/* 表盘 */}
      <div className="absolute inset-[14px] flex flex-col items-center justify-center rounded-full border border-ink/8 bg-white shadow-[0_8px_24px_-12px_rgba(26,43,74,0.25)]">
        <span className="text-2xl font-bold tracking-[0.2em] text-ink">
          •••••
        </span>
        <span className="mt-1 font-display text-sm font-semibold text-gold">
          2.4s
        </span>
      </div>
      {/* 显示/隐藏切换 */}
      <div className="absolute -right-1 top-1 flex h-8 w-8 items-center justify-center rounded-full border border-ink/10 bg-paper text-[13px] text-ink/50 shadow-sm">
        👁
      </div>
    </div>
  );
}

/** 听写界面模拟（怀表倒计时 + 控制台） */
export function DictationScreenMock() {
  return (
    <div className="space-y-3">
      {/* 顶部进度条 */}
      <div className="h-1 w-full overflow-hidden rounded-full bg-ink/10">
        <div className="h-full w-[14%] rounded-full bg-gold" />
      </div>
      {/* 头部：退出 / 进度 / 状态 */}
      <div className="flex items-center justify-between">
        <span className="flex h-7 w-7 items-center justify-center rounded-full border border-ink/10 bg-paper text-xs text-ink/60">
          ✕
        </span>
        <span className="text-sm text-ink/60">
          <span className="font-bold text-ink">6</span> / 44
        </span>
        <span className="flex items-center gap-1.5 rounded-full border border-ink/10 bg-paper px-2.5 py-1 text-[10px] text-ink/60">
          <span className="h-1.5 w-1.5 rounded-full bg-emerald-500" />
          听写中
        </span>
      </div>
      {/* 怀表倒计时 */}
      <div className="py-1">
        <CountdownRingMock />
      </div>
      {/* 标记错词 */}
      <div className="rounded-xl border border-rose/50 px-3 py-2 text-center text-xs font-semibold text-rose">
        ⊗ 标记错词
      </div>
      {/* 底部控制台 */}
      <div className="space-y-2.5 rounded-2xl bg-parchment/70 p-3">
        <div className="flex items-center gap-2 text-[10px] text-ink/60">
          <span>间隔</span>
          <span className="relative h-1 flex-1 rounded-full bg-ink/15">
            <span className="absolute left-0 top-0 h-full w-[45%] rounded-full bg-ink" />
            <span className="absolute left-[45%] top-1/2 h-3.5 w-3.5 -translate-x-1/2 -translate-y-1/2 rounded-full bg-ink" />
          </span>
          <span className="font-semibold text-ink">4.5s</span>
        </div>
        <div className="flex items-end justify-center gap-6">
          {[
            { icon: "■", label: "结束", cls: "h-9 w-9 border border-rose/40 text-rose text-[10px]" },
            { icon: "❚❚", label: "暂停", cls: "h-12 w-12 bg-ink text-paper text-xs" },
            { icon: "⏭", label: "跳过", cls: "h-9 w-9 border border-ink/15 text-ink/60 text-[10px]" },
          ].map((b) => (
            <div key={b.label} className="flex flex-col items-center gap-1">
              <span
                className={`flex items-center justify-center rounded-full ${b.cls}`}
              >
                {b.icon}
              </span>
              <span className="text-[9px] text-ink/50">{b.label}</span>
            </div>
          ))}
        </div>
      </div>
    </div>
  );
}

/** 首页界面模拟（单词列表 + 拍照识词） */
export function HomeScreenMock() {
  const words = [
    { n: "01", w: "rule", m: "n. 规则" },
    { n: "02", w: "arrive", m: "vi. 到达" },
    { n: "03", w: "hallway", m: "n. 门厅" },
    { n: "04", w: "dining hall", m: "n. 餐厅" },
    { n: "05", w: "listen", m: "vi. 听" },
  ];
  return (
    <div className="relative space-y-2.5">
      {/* 品牌头部 */}
      <div className="flex items-center justify-between pt-1">
        <span className="font-display text-base font-bold text-ink">
          <span className="italic">Alice</span>
          <span className="text-rose"> 听写</span>
        </span>
        <span className="flex h-7 w-7 items-center justify-center rounded-full bg-ink/5 text-xs text-ink/60">
          ☰
        </span>
      </div>
      {/* 识别进度 */}
      <div className="mx-auto flex w-fit items-center gap-2 rounded-full border border-gold/40 bg-gold/10 px-3 py-1 text-[10px] font-medium text-gold">
        <span className="inline-block h-2.5 w-2.5 animate-spin rounded-full border border-gold border-t-transparent" />
        已识别 44 个单词
      </div>
      {/* 列表头 */}
      <div className="flex items-center justify-between">
        <span className="flex items-center gap-1.5">
          <span className="font-display text-xs font-bold text-ink">
            单词列表
          </span>
          <span className="rounded-full border border-ink/10 px-1.5 py-px text-[9px] text-ink/50">
            44 词
          </span>
        </span>
        <span className="rounded-lg border border-ink/15 px-2 py-0.5 text-[10px] text-ink/60">
          ✎ 编辑
        </span>
      </div>
      {/* 单词列表 */}
      <div className="overflow-hidden rounded-2xl border border-ink/8 bg-white shadow-sm">
        {words.map((item, i) => (
          <div
            key={item.n}
            className={`flex items-center gap-3 px-3 py-1.5 ${
              i > 0 ? "border-t border-ink/5" : ""
            } ${i === 0 ? "bg-parchment/70" : ""}`}
          >
            <span className="w-5 font-display text-[10px] text-ink/35">
              {item.n}
            </span>
            <span>
              <span className="block text-xs font-semibold text-ink">
                {item.w}
              </span>
              <span className="block text-[9px] text-ink/40">{item.m}</span>
            </span>
          </div>
        ))}
      </div>
      {/* 拍照 FAB */}
      <div className="absolute -bottom-1 right-0 flex h-11 w-11 items-center justify-center rounded-full bg-gold text-lg shadow-lg">
        📷
      </div>
      {/* 开始听写 */}
      <div className="mr-14 flex items-center justify-center gap-2 rounded-2xl bg-ink px-3 py-2.5 text-xs font-semibold text-paper">
        ▶ 开始听写
        <span className="rounded-full bg-paper/20 px-1.5 text-[9px]">44 词</span>
      </div>
    </div>
  );
}

/** 词库界面模拟（底部抽屉） */
export function LibraryScreenMock() {
  const groups = [
    {
      cat: "人教版初中",
      items: [
        { l: "七上 Unit 1", n: 38 },
        { l: "七上 Unit 2", n: 42 },
      ],
    },
    {
      cat: "中考1600",
      items: [{ l: "A", n: 96 }],
    },
    {
      cat: "高考3500",
      items: [
        { l: "A", n: 323 },
        { l: "B", n: 252 },
      ],
    },
  ];
  return (
    <div className="flex h-[380px] flex-col justify-end">
      {/* 首页背景（虚化） */}
      <div className="pointer-events-none absolute inset-x-4 top-10 space-y-2 opacity-30 blur-[1px]">
        <div className="h-5 w-24 rounded bg-ink/20" />
        <div className="h-20 rounded-2xl bg-ink/10" />
        <div className="h-3 w-32 rounded bg-ink/15" />
      </div>
      {/* 底部抽屉 */}
      <div className="relative rounded-t-3xl border border-b-0 border-ink/10 bg-paper pb-3 shadow-[0_-12px_32px_-12px_rgba(26,43,74,0.25)]">
        {/* 抽屉把手 */}
        <div className="mx-auto mt-2 h-1 w-10 rounded-full bg-ink/15" />
        <div className="px-3 pt-2">
          <div className="mb-2 font-display text-sm font-semibold text-ink">
            词库 (278)
          </div>
          {/* 搜索框 */}
          <div className="mb-2.5 flex items-center gap-2 rounded-xl border border-ink/10 bg-parchment/70 px-3 py-1.5">
            <span className="text-xs text-ink/40">⌕</span>
            <span className="text-[11px] text-ink/35">搜索标题或分类</span>
          </div>
          {/* 分组列表 */}
          <div className="space-y-2">
            {groups.map((g) => (
              <div key={g.cat}>
                <div className="mb-1 px-1 font-display text-[10px] font-semibold text-ink/45">
                  {g.cat}
                </div>
                <div className="space-y-1">
                  {g.items.map((item) => (
                    <div
                      key={`${g.cat}-${item.l}`}
                      className="flex items-center justify-between rounded-lg border border-ink/8 bg-parchment/60 px-3 py-1.5 text-xs text-ink/80"
                    >
                      <span className="font-medium">{item.l}</span>
                      <span className="text-[10px] text-ink/35">{item.n}</span>
                    </div>
                  ))}
                </div>
              </div>
            ))}
          </div>
        </div>
      </div>
    </div>
  );
}

/** 听写完成界面模拟（成绩单 + 错词本） */
export function FinishScreenMock() {
  const wrong = ["hallway", "dining hall", "rule"];
  return (
    <div className="space-y-3">
      {/* 头部 */}
      <div className="flex items-center justify-between pt-1">
        <span className="flex h-7 w-7 items-center justify-center rounded-full border border-ink/10 bg-paper text-xs text-ink/60">
          ✕
        </span>
        <span className="text-sm text-ink/60">
          <span className="font-bold text-ink">44</span> / 44
        </span>
        <span className="flex items-center gap-1.5 rounded-full border border-ink/10 bg-paper px-2.5 py-1 text-[10px] text-ink/60">
          <span className="h-1.5 w-1.5 rounded-full bg-emerald-500" />
          已完成
        </span>
      </div>
      {/* 成绩单 */}
      <div className="rounded-2xl border border-ink/8 bg-white p-4 text-center shadow-sm">
        <div className="mx-auto flex h-10 w-10 items-center justify-center rounded-full bg-emerald-500 text-lg text-white">
          ✓
        </div>
        <div className="mt-2 font-display text-lg font-bold text-ink">
          听写完成
        </div>
        <div className="mt-3 flex justify-around border-t border-ink/8 pt-3">
          {[
            { v: "44", l: "单词", cls: "text-ink" },
            { v: "3", l: "错词", cls: "text-rose" },
            { v: "5:32", l: "用时", cls: "text-ink" },
          ].map((s) => (
            <div key={s.l}>
              <div className={`font-display text-base font-bold ${s.cls}`}>
                {s.v}
              </div>
              <div className="text-[9px] text-ink/45">{s.l}</div>
            </div>
          ))}
        </div>
      </div>
      {/* 操作 */}
      <div className="flex items-center justify-center gap-2 rounded-xl bg-ink px-3 py-2 text-[11px] font-semibold text-paper">
        ↻ 错词再听一遍 (3)
      </div>
      {/* 错词本 */}
      <div className="rounded-2xl bg-parchment/70 p-3">
        <div className="mb-2 flex items-center justify-between text-[10px] text-ink/60">
          <span className="font-semibold">错词本 (3)</span>
          <span className="flex gap-2">
            <span>导出</span>
            <span>清空</span>
          </span>
        </div>
        <div className="flex flex-wrap gap-1.5">
          {wrong.map((w) => (
            <span
              key={w}
              className="rounded-full border border-ink/12 bg-paper px-2.5 py-1 text-[10px] font-medium text-ink"
            >
              {w} <span className="text-ink/35">×</span>
            </span>
          ))}
        </div>
      </div>
    </div>
  );
}

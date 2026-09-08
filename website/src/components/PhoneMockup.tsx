import type { ReactNode } from "react";

export type AppShot = "home" | "library" | "dictation" | "finish";

const SHOTS: Record<AppShot, { src: string; alt: string }> = {
  home: {
    src: "/screenshots/home.png",
    alt: "首页：单词列表、拍照识词与开始听写",
  },
  library: {
    src: "/screenshots/library.png",
    alt: "词库：290 套教材词表，支持搜索与收藏",
  },
  dictation: {
    src: "/screenshots/dictation.png",
    alt: "听写：怀表倒计时，可重听、调语速、标记错词",
  },
  finish: {
    src: "/screenshots/finish.png",
    alt: "完成：成绩单、本轮错词与再听一遍",
  },
};

/**
 * 手机外框。一圈等宽 border，四边同一粗细。
 * 截图自带状态栏与手势条，不再另叠刘海。
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
      <div className="w-70 overflow-hidden rounded-[1.75rem] border-[10px] border-ink bg-paper shadow-[0_30px_60px_-20px_rgba(26,43,74,0.4)]">
        {children}
      </div>
    </div>
  );
}

export function PhoneScreenshot({
  shot,
  className = "",
  priority = false,
}: {
  shot: AppShot;
  className?: string;
  priority?: boolean;
}) {
  const { src, alt } = SHOTS[shot];
  return (
    <PhoneFrame className={className}>
      <img
        src={src}
        alt={alt}
        width={1080}
        height={2424}
        className="block h-auto w-full"
        decoding="async"
        loading={priority ? "eager" : "lazy"}
        fetchPriority={priority ? "high" : "auto"}
      />
    </PhoneFrame>
  );
}

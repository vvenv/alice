import {
  Camera,
  Volume2,
  RefreshCw,
  Library,
  Share2,
  MonitorSmartphone,
  type LucideIcon,
} from "lucide-react";
import { useStaggeredReveal } from "../hooks/useReveal";
import { SuitHeart } from "./Decorations";

interface Feature {
  icon: LucideIcon;
  title: string;
  desc: string;
  tag: string;
}

const FEATURES: Feature[] = [
  {
    icon: Camera,
    title: "拍照即听写",
    desc: "拍一张或从相册选图，可先裁切、旋转再识别。AI 补全词性与释义。免费档无限次，高级档更准。",
    tag: "拍照识别",
  },
  {
    icon: Share2,
    title: "分享、粘贴即成表",
    desc: "从微信、备忘录把文字分享过来，或直接粘贴。单行带逗号、顿号会自动拆开。",
    tag: "Android 分享",
  },
  {
    icon: Volume2,
    title: "听写中就能调",
    desc: "默认 Edge 朗读，失败回落有道或系统语音。重听、语速、朗读中文释义都不必退出。",
    tag: "语音朗读",
  },
  {
    icon: MonitorSmartphone,
    title: "放桌上也能写完",
    desc: "听写时屏幕常亮。切后台、来电、拔耳机都会自动暂停，回来接着听，不会白读。",
    tag: "听写体验",
  },
  {
    icon: RefreshCw,
    title: "错词追踪闭环",
    desc: "一键标记错词，完成页立刻列出。错词本可查看、划词、导出，再听一遍直到攻克。",
    tag: "本地保存",
  },
  {
    icon: Library,
    title: "290 套教材词库",
    desc: "中考 1600、高考 3500，人教、外研、闽教、仁爱版单元词表开箱即用，支持搜索与收藏。",
    tag: "教材同步",
  },
];

export function Features() {
  const ref = useStaggeredReveal(120);

  return (
    <section id="features" className="relative py-24 lg:py-32">
      <div className="container">
        {/* 标题 */}
        <div className="mx-auto mb-16 max-w-2xl text-center">
          <div className="eyebrow mb-4">
            <span>Core Features</span>
          </div>
          <h2 className="heading-serif text-4xl sm:text-5xl">
            为听写而生的
            <span className="italic text-rose"> 每一处细节</span>
          </h2>
          <p className="mt-5 text-base leading-relaxed text-ink/60">
            从识别到发音，从练习到回顾，每个环节都打磨到顺手。
          </p>
        </div>

        {/* 卡片网格 */}
        <div ref={ref} className="grid gap-6 sm:grid-cols-2 lg:grid-cols-3">
          {FEATURES.map((f) => (
            <div
              key={f.title}
              className="card-paper reveal group relative overflow-hidden"
            >
              {/* 角标 */}
              <SuitHeart className="absolute right-6 top-6 h-4 w-4 text-rose/15 transition-all duration-500 group-hover:rotate-12 group-hover:text-rose/30" />

              <div className="mb-5 inline-flex h-12 w-12 items-center justify-center rounded-xl bg-ink text-paper transition-all duration-500 group-hover:bg-rose">
                <f.icon className="h-6 w-6" />
              </div>

              <div className="mb-1 text-xs font-medium uppercase tracking-widest text-gold/70">
                {f.tag}
              </div>
              <h3 className="font-display text-2xl font-bold text-ink">
                {f.title}
              </h3>
              <p className="mt-3 text-sm leading-relaxed text-ink/60">
                {f.desc}
              </p>
            </div>
          ))}
        </div>
      </div>
    </section>
  );
}

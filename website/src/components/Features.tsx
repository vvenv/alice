import {
  Camera,
  Volume2,
  RefreshCw,
  Library,
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
    desc: "拍一张课本照片，AI 自动识别全部单词，瞬间生成听写列表。",
    tag: "拍照识别",
  },
  {
    icon: Volume2,
    title: "纯正系统发音",
    desc: "纯正美音逐词朗读，间隔可调、自动连播，像一位老师在身边领读。",
    tag: "语音朗读",
  },
  {
    icon: RefreshCw,
    title: "错词追踪闭环",
    desc: "一键标记错词，自动收入错词本。支持导出，反复练习薄弱词汇。",
    tag: "本地保存",
  },
  {
    icon: Library,
    title: "内置教材词库",
    desc: "中考 1600、高考 3500，人教、外研、闽教版教材单元词表开箱即用，支持搜索。",
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
        <div ref={ref} className="grid gap-6 sm:grid-cols-2">
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

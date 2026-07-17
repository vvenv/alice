import {
  ArrowRight,
  Smartphone,
  Volume2,
  Camera,
  BookOpen,
  Library,
} from "lucide-react";
import { PhoneFrame, DictationScreenMock } from "./PhoneMockup";
import { PocketWatch, GearCluster, SuitHeart, SuitSpade } from "./Decorations";

export function Hero() {
  return (
    <section className="relative overflow-hidden pt-28 lg:pt-36">
      {/* 背景装饰 */}
      <GearCluster className="-left-20 top-32 hidden lg:block" />
      <GearCluster className="-right-24 top-96 hidden lg:block" />
      <div className="pointer-events-none absolute right-[8%] top-24 hidden lg:block">
        <PocketWatch className="h-20 w-20 animate-float text-gold/25" />
      </div>

      <div className="container relative z-10">
        <div className="grid items-center gap-12 lg:grid-cols-[1.1fr_0.9fr] lg:gap-8">
          {/* 左侧文字 */}
          <div className="max-w-xl">
            <div
              className="mb-6 inline-flex items-center gap-2 rounded-full border border-gold/30 bg-gold/5 px-4 py-1.5 text-xs font-medium text-gold opacity-0"
              style={{ animation: "fadeUp 0.8s 0.1s forwards" }}
            >
              <SuitHeart className="h-3 w-3" />
              拍照即听写 · 内置教材词库
            </div>

            <h1
              className="heading-serif text-5xl opacity-0 sm:text-6xl lg:text-7xl"
              style={{ animation: "fadeUp 0.9s 0.2s forwards" }}
            >
              Alice
              <span className="em-italic block text-rose">听写</span>
            </h1>

            <p
              className="mt-3 font-serif text-2xl italic text-gold opacity-0"
              style={{ animation: "fadeUp 0.9s 0.35s forwards" }}
            >
              Down the rabbit-hole of words.
            </p>

            <p
              className="mt-6 text-base leading-relaxed text-ink/70 opacity-0"
              style={{ animation: "fadeUp 0.9s 0.5s forwards" }}
            >
              拍照识别单词，内置教材词库，逐词朗读、错词留痕。 让听写回归语言本身。
            </p>

            <div
              className="mt-8 flex flex-wrap items-center gap-4 opacity-0"
              style={{ animation: "fadeUp 0.9s 0.65s forwards" }}
            >
              <a href="#download" className="btn-primary">
                <Smartphone className="h-4 w-4" />
                立即下载
                <ArrowRight className="h-4 w-4" />
              </a>
              <a href="#features" className="btn-secondary">
                了解功能
              </a>
            </div>

            {/* 数据指标 */}
            <div
              className="mt-10 flex flex-wrap items-center gap-x-8 gap-y-4 opacity-0"
              style={{ animation: "fadeUp 0.9s 0.8s forwards" }}
            >
              {[
                { icon: Camera, label: "拍照识别", value: "拍照即用" },
                { icon: Library, label: "内置词库", value: "教材同步" },
                { icon: Volume2, label: "语音朗读", value: "纯正美音" },
                { icon: BookOpen, label: "错词追踪", value: "本地保存" },
              ].map((item) => (
                <div key={item.label} className="flex items-center gap-2.5">
                  <item.icon className="h-5 w-5 text-gold" />
                  <div>
                    <div className="text-sm font-semibold text-ink">
                      {item.value}
                    </div>
                    <div className="text-xs text-ink/50">{item.label}</div>
                  </div>
                </div>
              ))}
            </div>
          </div>

          {/* 右侧手机模拟 */}
          <div
            className="relative flex justify-center opacity-0 lg:justify-end"
            style={{ animation: "fadeIn 1s 0.4s forwards" }}
          >
            {/* 装饰扑克花色 */}
            <SuitSpade className="absolute -left-4 top-12 h-8 w-8 rotate-12 text-ink/15" />
            <SuitHeart className="absolute -right-2 bottom-20 h-7 w-7 -rotate-12 text-rose/20" />

            {/* 浮动光晕 */}
            <div className="absolute inset-0 -z-10 bg-linear-to-tr from-rose/10 via-transparent to-gold/10 blur-3xl" />

            <div className="animate-float">
              <PhoneFrame>
                <DictationScreenMock />
              </PhoneFrame>
            </div>
          </div>
        </div>
      </div>

      <style>{`
        @keyframes fadeUp {
          from { opacity: 0; transform: translateY(24px); }
          to { opacity: 1; transform: translateY(0); }
        }
        @keyframes fadeIn {
          from { opacity: 0; transform: scale(0.96); }
          to { opacity: 1; transform: scale(1); }
        }
      `}</style>
    </section>
  );
}

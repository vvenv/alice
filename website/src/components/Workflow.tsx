import { useStaggeredReveal } from "../hooks/useReveal";
import { PocketWatch } from "./Decorations";

const STEPS = [
  {
    num: "I",
    title: "拍照或粘贴",
    desc: "拍下课本单词表，或直接粘贴单词文本。",
  },
  {
    num: "II",
    title: "自动识别",
    desc: "AI 提取照片中的全部单词，自动生成听写列表。",
  },
  {
    num: "III",
    title: "逐词听写",
    desc: "逐词朗读，你来书写。间隔可调，自动连播。",
  },
  {
    num: "IV",
    title: "错词回顾",
    desc: "错词自动入册，导出后反复练习，直到攻克。",
  },
];

export function Workflow() {
  const ref = useStaggeredReveal(150);

  return (
    <section
      id="workflow"
      className="relative overflow-hidden bg-parchment/40 py-24 lg:py-32"
    >
      <div className="container">
        <div className="mx-auto mb-16 max-w-2xl text-center">
          <div className="eyebrow mb-4">
            <span>How It Works</span>
          </div>
          <h2 className="heading-serif text-4xl sm:text-5xl">
            四步开启，
            <span className="italic text-rose"> 一场听写之旅</span>
          </h2>
          <p className="mt-5 text-base leading-relaxed text-ink/60">
            如同坠入兔洞般自然，每一步都顺理成章。
          </p>
        </div>

        <div ref={ref} className="relative">
          {/* 连接线 */}
          <div className="absolute left-0 right-0 top-[3.25rem] hidden border-t-2 border-dashed border-gold/25 lg:block" />

          <div className="grid gap-10 lg:grid-cols-4 lg:gap-6">
            {STEPS.map((step, i) => (
              <div
                key={step.num}
                className="reveal relative flex flex-col items-center text-center"
              >
                {/* 怀表序号 */}
                <div className="relative mb-6">
                  <div className="relative z-10 flex h-[6.5rem] w-[6.5rem] items-center justify-center rounded-full border-2 border-gold/40 bg-paper shadow-[0_8px_24px_-8px_rgba(184,134,11,0.3)]">
                    <PocketWatch className="absolute inset-0 h-full w-full p-2 text-gold/15" />
                    <span className="font-display text-3xl font-bold italic text-rose">
                      {step.num}
                    </span>
                  </div>
                  {/* 连接点 */}
                  {i < STEPS.length - 1 && (
                    <span className="absolute -right-3 top-1/2 hidden h-3 w-3 -translate-y-1/2 rounded-full bg-gold/40 lg:block" />
                  )}
                </div>

                <h3 className="font-display text-xl font-bold text-ink">
                  {step.title}
                </h3>
                <p className="mt-3 max-w-xs text-sm leading-relaxed text-ink/60">
                  {step.desc}
                </p>
              </div>
            ))}
          </div>
        </div>
      </div>
    </section>
  );
}

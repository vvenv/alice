import { ChevronDown } from "lucide-react";
import { FAQS } from "@/data/faq";
import { useReveal } from "../hooks/useReveal";

export function Faq() {
  const { ref, visible } = useReveal();

  return (
    <section id="faq" className="relative py-24 lg:py-32">
      <div className="container">
        <div className="grid gap-12 lg:grid-cols-[0.85fr_1.15fr] lg:gap-16">
          {/* 左侧标题 */}
          <div className="lg:sticky lg:top-28 lg:self-start">
            <div className="eyebrow eyebrow-left mb-4">
              <span>FAQ</span>
            </div>
            <h2 className="heading-serif text-4xl sm:text-5xl">
              常见
              <span className="italic text-rose"> 疑问</span>
            </h2>
            <p className="mt-5 text-base leading-relaxed text-ink/60">
              关于隐私与使用的解答。
            </p>
          </div>

          {/* 右侧问答列表 */}
          <div
            ref={ref}
            className={`reveal space-y-3 ${visible ? "is-visible" : ""}`}
          >
            {FAQS.map((item, i) => (
              <details
                key={i}
                open={i === 0}
                className="group overflow-hidden rounded-xl border border-ink/10 bg-paper/50 transition-all duration-300 open:shadow-[0_4px_20px_-8px_rgba(184,134,11,0.2)] hover:border-ink/15 open:hover:border-gold/30"
              >
                <summary className="flex cursor-pointer list-none items-center justify-between gap-4 px-6 py-5 text-left [&::-webkit-details-marker]:hidden">
                  <span className="font-display text-lg font-semibold text-ink transition-colors group-open:text-rose">
                    {item.q}
                  </span>
                  <ChevronDown className="h-5 w-5 shrink-0 text-gold transition-transform duration-300 group-open:rotate-180" />
                </summary>
                <p className="px-6 pb-5 text-sm leading-relaxed text-ink/65">
                  {item.a}
                </p>
              </details>
            ))}
          </div>
        </div>
      </div>
    </section>
  );
}

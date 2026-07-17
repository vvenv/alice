import { useState } from "react";
import { ChevronDown } from "lucide-react";
import { FAQS } from "@/data/faq";
import { useReveal } from "../hooks/useReveal";

export function Faq() {
  const [open, setOpen] = useState<number | null>(0);
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
            {FAQS.map((item, i) => {
              const isOpen = open === i;
              return (
                <div
                  key={i}
                  className={`overflow-hidden rounded-xl border transition-all duration-300 ${
                    isOpen
                      ? "border-gold/30 bg-paper shadow-[0_4px_20px_-8px_rgba(184,134,11,0.2)]"
                      : "border-ink/10 bg-paper/50 hover:border-ink/15"
                  }`}
                >
                  <button
                    onClick={() => setOpen(isOpen ? null : i)}
                    className="flex w-full items-center justify-between gap-4 px-6 py-5 text-left"
                  >
                    <span
                      className={`font-display text-lg font-semibold transition-colors ${isOpen ? "text-rose" : "text-ink"}`}
                    >
                      {item.q}
                    </span>
                    <ChevronDown
                      className={`h-5 w-5 shrink-0 text-gold transition-transform duration-300 ${
                        isOpen ? "rotate-180" : ""
                      }`}
                    />
                  </button>
                  <div
                    className={`grid transition-all duration-300 ${
                      isOpen
                        ? "grid-rows-[1fr] opacity-100"
                        : "grid-rows-[0fr] opacity-0"
                    }`}
                  >
                    <div className="overflow-hidden">
                      <p className="px-6 pb-5 text-sm leading-relaxed text-ink/65">
                        {item.a}
                      </p>
                    </div>
                  </div>
                </div>
              );
            })}
          </div>
        </div>
      </div>
    </section>
  );
}

import { useState } from "react";
import { ChevronDown } from "lucide-react";
import { useReveal } from "../hooks/useReveal";

interface QA {
  q: string;
  a: string;
}

const FAQS: QA[] = [
  {
    q: "应用是免费的吗？",
    a: "完全免费。听写、词库、错词本、拍照识别等全部功能均可直接使用，无内购、无广告。如需更换识别服务，也可以在设置中配置自己的 OCR 服务（自定义 API 地址与密钥）。",
  },
  {
    q: "内置词库有哪些内容？",
    a: "内置中考 1600、高考 3500，以及人教版小学 / 初中、外研版初中、闽教版小学教材的单元词表。支持按标题与分类搜索，点击即可载入听写。",
  },
  {
    q: "我的单词数据保存在哪里？会同步到云端吗？",
    a: "所有数据保存在你的设备本机，不上传云端，完全私密。",
  },
  {
    q: "发音使用的是什么语音？",
    a: "调用系统内置英文语音引擎朗读。建议在系统设置中选用高质量英文语音，效果更佳。",
  },
  {
    q: "支持哪些平台？需要联网吗？",
    a: "目前已上线 Android 版本，iOS 与 Web 版本敬请期待。听写、错词追踪无需联网；仅拍照识别需要联网。",
  },
  {
    q: "拍照识别能识别手写体吗？准确率如何？",
    a: "印刷体识别率极高，工整的手写体也能识别。拍摄时保持光线充足、文字清晰即可。",
  },
  {
    q: "如何联系开发者或反馈问题？",
    a: "添加页面底部的开发者微信沟通反馈，或在 GitHub 仓库提交 Issue。",
  },
];

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

import { Apple, Smartphone, Globe } from "lucide-react";
import { APP_VERSION, APK_URL, WEB_APP_URL } from "@/data/site";
import { useReveal } from "../hooks/useReveal";
import { PocketWatch, SuitHeart, SuitSpade } from "./Decorations";

export function Download() {
  const { ref, visible } = useReveal();

  return (
    <section
      id="download"
      className="relative overflow-hidden py-24 lg:py-32"
    >
      <div className="container">
        <div
          ref={ref}
          className={`reveal relative overflow-hidden rounded-3xl bg-ink px-8 py-16 text-center shadow-2xl lg:px-16 lg:py-20 ${
            visible ? "is-visible" : ""
          }`}
        >
          {/* 背景装饰 */}
          <PocketWatch className="pointer-events-none absolute -left-10 -top-10 h-44 w-44 animate-spin-slower text-gold/10" />
          <PocketWatch className="pointer-events-none absolute -bottom-12 -right-8 h-36 w-36 animate-spin-slow text-rose/10" />
          <SuitHeart className="pointer-events-none absolute right-[15%] top-8 h-6 w-6 rotate-12 text-rose/20" />
          <SuitSpade className="pointer-events-none absolute left-[12%] bottom-10 h-6 w-6 -rotate-12 text-gold/15" />

          <div className="relative z-10">
            <div className="eyebrow mb-4 !text-gold/80">
              <span>Get Alice</span>
            </div>
            <h2 className="font-display text-4xl font-bold leading-tight text-paper sm:text-5xl">
              开启你的
              <span className="italic text-rose"> 听写之旅</span>
            </h2>
            <p className="mx-auto mt-5 max-w-xl text-base leading-relaxed text-paper/60">
              听写、词库、错词本免费无广告。拍照识别提供免费档与演示积分高级档。
            </p>

            {/* 下载按钮 */}
            <div className="mt-10 flex flex-wrap items-center justify-center gap-4">
              {/* iOS — 尚未上架，不要伪装成可下载 */}
              <div
                aria-disabled="true"
                title="iOS 版本即将推出"
                className="inline-flex cursor-not-allowed items-center gap-3 rounded-xl border border-paper/15 bg-paper/5 px-6 py-4 opacity-55"
              >
                <Apple className="h-7 w-7 text-paper" />
                <div className="text-left">
                  <div className="text-[10px] uppercase tracking-widest text-paper/50">
                    即将推出
                  </div>
                  <div className="text-sm font-semibold text-paper">
                    App Store
                  </div>
                </div>
              </div>

              {/* Android — 真实下载 */}
              <a
                href={APK_URL}
                download
                className="group relative inline-flex items-center gap-3 rounded-xl border border-gold/40 bg-gold/15 px-6 py-4 backdrop-blur-sm transition-all duration-300 hover:border-gold/70 hover:bg-gold/25"
              >
                <span className="absolute -right-2 -top-2 rounded-full bg-rose px-2 py-0.5 text-[10px] font-bold text-paper">
                  APK
                </span>
                <Smartphone className="h-7 w-7 text-gold" />
                <div className="text-left">
                  <div className="text-[10px] uppercase tracking-widest text-gold/70">
                    Get it for
                  </div>
                  <div className="text-sm font-semibold text-paper">
                    Android 下载
                  </div>
                </div>
              </a>

              {/* Web — 浏览器版 */}
              <a
                href={WEB_APP_URL}
                target="_blank"
                rel="noopener noreferrer"
                className="group relative inline-flex items-center gap-3 rounded-xl border border-paper/20 bg-paper/5 px-6 py-4 backdrop-blur-sm transition-all duration-300 hover:border-gold/50 hover:bg-paper/10"
              >
                <span className="absolute -right-2 -top-2 rounded-full bg-paper/15 px-2 py-0.5 text-[10px] font-bold text-paper">
                  NEW
                </span>
                <Globe className="h-7 w-7 text-paper" />
                <div className="text-left">
                  <div className="text-[10px] uppercase tracking-widest text-paper/50">
                    Open in
                  </div>
                  <div className="text-sm font-semibold text-paper">
                    Web 浏览器
                  </div>
                </div>
              </a>
            </div>

            {/* 二维码区 */}
            <div className="mt-12 flex flex-col items-center justify-center gap-6 sm:flex-row sm:gap-10">
              <div className="flex flex-col items-center gap-3">
                <div className="flex h-32 w-32 items-center justify-center rounded-2xl border border-paper/15 bg-paper p-3">
                  <img
                    src="/qr-code.png"
                    alt="扫码下载 Alice 听写"
                    width={128}
                    height={128}
                    className="h-full w-full rounded-md"
                  />
                </div>
                <span className="text-xs text-paper/50">扫码下载</span>
              </div>

              <div className="hidden h-24 w-px bg-paper/15 sm:block" />

              <div className="text-left">
                <div className="font-display text-lg font-semibold text-paper">
                  版本 v{APP_VERSION}
                </div>
                <div className="mt-1 text-sm text-paper/50">
                  支持 Android 8+ · Web 浏览器
                </div>
                <div className="mt-1 text-xs text-paper/40">
                  Web 版拍照识别需自备 OCR API Key
                </div>
              </div>
            </div>
          </div>
        </div>
      </div>
    </section>
  );
}

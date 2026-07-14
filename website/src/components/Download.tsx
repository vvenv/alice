import { useState, useEffect, useCallback } from "react";
import { Apple, Smartphone, Globe } from "lucide-react";
import { useReveal } from "../hooks/useReveal";
import { PocketWatch, SuitHeart, SuitSpade } from "./Decorations";

const APK_URL =
  "https://alice.edao.plus/downloads/alice-0.1.0-20260714-1151.apk";

export function Download() {
  const { ref, visible } = useReveal();
  const [toast, setToast] = useState(false);
  const [hide, setHide] = useState(false);

  const showToast = useCallback(() => {
    setHide(false);
    setToast(true);
  }, []);

  useEffect(() => {
    if (!toast) return;
    const t1 = setTimeout(() => setHide(true), 2200);
    const t2 = setTimeout(() => setToast(false), 2700);
    return () => {
      clearTimeout(t1);
      clearTimeout(t2);
    };
  }, [toast]);

  return (
    <>
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
                扫码下载，核心听写功能免费，拍照识别可按需解锁。
              </p>

              {/* 下载按钮 */}
              <div className="mt-10 flex flex-wrap items-center justify-center gap-4">
                {/* iOS — 敬请期待 */}
                <button
                  onClick={showToast}
                  className="group inline-flex cursor-pointer items-center gap-3 rounded-xl border border-paper/20 bg-paper/5 px-6 py-4 backdrop-blur-sm transition-all duration-300 hover:border-gold/50 hover:bg-paper/10"
                >
                  <Apple className="h-7 w-7 text-paper" />
                  <div className="text-left">
                    <div className="text-[10px] uppercase tracking-widest text-paper/50">
                      Download on
                    </div>
                    <div className="text-sm font-semibold text-paper">
                      App Store
                    </div>
                  </div>
                </button>

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

                {/* Web — 敬请期待 */}
                <button
                  onClick={showToast}
                  className="group inline-flex cursor-pointer items-center gap-3 rounded-xl border border-paper/20 bg-paper/5 px-6 py-4 backdrop-blur-sm transition-all duration-300 hover:border-gold/50 hover:bg-paper/10"
                >
                  <Globe className="h-7 w-7 text-paper" />
                  <div className="text-left">
                    <div className="text-[10px] uppercase tracking-widest text-paper/50">
                      Open in
                    </div>
                    <div className="text-sm font-semibold text-paper">
                      Web 浏览器
                    </div>
                  </div>
                </button>
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
                  <span className="text-xs text-paper/50">
                    扫码下载
                  </span>
                </div>

                <div className="hidden h-24 w-px bg-paper/15 sm:block" />

                <div className="text-left">
                  <div className="font-display text-lg font-semibold text-paper">
                    版本 v0.1.0
                  </div>
                  <div className="mt-1 text-sm text-paper/50">
                    支持 Android 8+
                  </div>
                  <div className="mt-3 inline-flex items-center gap-2 rounded-full bg-gold/15 px-3 py-1 text-xs text-gold">
                    <span className="h-1.5 w-1.5 rounded-full bg-gold" />
                    核心功能永久免费
                  </div>
                </div>
              </div>
            </div>
          </div>
        </div>
      </section>

      {/* Toast 提示 */}
      {toast && (
        <div
          className={`fixed bottom-8 left-0 right-0 z-[100] flex justify-center transition-opacity duration-500 ${
            hide ? "opacity-0" : "opacity-100"
          }`}
        >
          <div className="flex items-center gap-3 rounded-2xl border border-gold/30 bg-ink px-6 py-4 shadow-2xl">
            <span className="text-lg">⏳</span>
            <span className="text-sm font-medium text-paper">iOS 与 Web 版本敬请期待</span>
          </div>
        </div>
      )}
    </>
  );
}

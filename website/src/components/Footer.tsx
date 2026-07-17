import { PocketWatch, SuitHeart, SuitSpade } from "./Decorations";

export function Footer() {
  return (
    <footer className="relative overflow-hidden border-t border-ink/10 bg-parchment/50">
      <div className="container py-16">
        <div className="grid gap-10 lg:grid-cols-[1.5fr_1fr_1fr]">
          {/* 品牌 */}
          <div className="max-w-sm">
            <div className="flex items-center gap-2.5">
              <PocketWatch className="h-8 w-8 text-gold" />
              <span className="font-display text-2xl font-bold tracking-tight text-ink">
                Alice<span className="text-rose"> 听写</span>
              </span>
            </div>
            <p className="mt-4 font-serif text-lg italic text-gold/80">
              "Down the rabbit-hole of words."
            </p>
            <p className="mt-3 text-sm leading-relaxed text-ink/55">
              为英语学习者打造的单词听写应用。拍照识别，纯正发音，错词追踪。
            </p>
            <div className="mt-5 flex items-center gap-3 text-gold/40">
              <SuitHeart className="h-4 w-4" />
              <SuitSpade className="h-4 w-4" />
            </div>
          </div>

          {/* 导航 */}
          <div>
            <h4 className="mb-4 text-xs font-semibold uppercase tracking-widest text-ink/40">
              导航
            </h4>
            <ul className="space-y-3 text-sm">
              {[
                { label: "功能特性", href: "#features" },
                { label: "使用流程", href: "#workflow" },
                { label: "下载应用", href: "#download" },
                { label: "常见问题", href: "#faq" },
              ].map((link) => (
                <li key={link.href}>
                  <a
                    href={link.href}
                    className="text-ink/60 transition-colors hover:text-rose"
                  >
                    {link.label}
                  </a>
                </li>
              ))}
            </ul>
          </div>

          {/* 联系 */}
          <div>
            <h4 className="mb-4 text-xs font-semibold uppercase tracking-widest text-ink/40">
              联系
            </h4>
            <ul className="space-y-3 text-sm">
              <li className="text-ink/60">
                <span className="block text-ink/40">邮箱</span>
                <span className="font-medium text-ink">vvenvw[at]gmail.com</span>
              </li>
              <li className="text-ink/60">
                <span className="block text-ink/40">开源代码</span>
                <a
                  href="https://github.com/vvenv/alice"
                  target="_blank"
                  rel="noopener noreferrer"
                  className="font-medium text-ink transition-colors hover:text-rose"
                >
                  github.com/vvenv/alice
                </a>
              </li>
            </ul>
          </div>
        </div>

        {/* 分隔线 */}
        <div className="ornament-divider my-10">
          <span className="text-lg">✦</span>
        </div>

        {/* 版权 */}
        <div className="flex flex-col items-center justify-between gap-4 text-xs text-ink/40 sm:flex-row">
          <p>
            © 2026 Alice 听写 ·{" "}
            <a
              href="https://github.com/vvenv/alice/blob/main/LICENSE"
              target="_blank"
              rel="noopener noreferrer"
              className="transition-colors hover:text-rose"
            >
              MIT License
            </a>
          </p>
          <p className="font-serif italic">
            Crafted with care, like a pocket watch.
          </p>
        </div>
      </div>
    </footer>
  );
}

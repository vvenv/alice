import { useEffect, useState } from "react";
import { Menu, X, Download } from "lucide-react";
import { PocketWatch } from "./Decorations";

const GITHUB_URL = "https://github.com/vvenv/alice";

/** GitHub mark (lucide-react no longer ships brand icons). */
function Github({ className }: { className?: string }) {
  return (
    <svg
      className={className}
      viewBox="0 0 24 24"
      fill="currentColor"
      aria-hidden="true"
    >
      <path d="M12 .5C5.65.5.5 5.65.5 12c0 5.08 3.29 9.39 7.86 10.91.58.11.79-.25.79-.55 0-.27-.01-1.17-.02-2.12-3.2.7-3.87-1.36-3.87-1.36-.52-1.33-1.28-1.68-1.28-1.68-1.04-.71.08-.7.08-.7 1.15.08 1.76 1.19 1.76 1.19 1.03 1.75 2.69 1.25 3.34.95.1-.74.4-1.25.72-1.53-2.55-.29-5.23-1.28-5.23-5.68 0-1.26.45-2.28 1.19-3.09-.12-.29-.51-1.46.11-3.05 0 0 .97-.31 3.17 1.18a11.04 11.04 0 0 1 5.78 0c2.2-1.49 3.17-1.18 3.17-1.18.62 1.59.23 2.76.11 3.05.74.81 1.18 1.83 1.18 3.09 0 4.41-2.69 5.38-5.25 5.66.41.35.77 1.05.77 2.12 0 1.53-.01 2.76-.01 3.14 0 .3.2.66.79.55A11.52 11.52 0 0 0 23.5 12C23.5 5.65 18.35.5 12 .5Z" />
    </svg>
  );
}

const NAV_LINKS = [
  { label: "功能特性", href: "#features" },
  { label: "使用流程", href: "#workflow" },
  { label: "下载", href: "#download" },
  { label: "常见问题", href: "#faq" },
];

export function Navbar() {
  const [scrolled, setScrolled] = useState(false);
  const [open, setOpen] = useState(false);

  useEffect(() => {
    const onScroll = () => setScrolled(window.scrollY > 24);
    onScroll();
    window.addEventListener("scroll", onScroll, { passive: true });
    return () => window.removeEventListener("scroll", onScroll);
  }, []);

  return (
    <header
      className={`fixed inset-x-0 top-0 z-50 transition-all duration-500 ${
        scrolled
          ? "border-b border-ink/8 bg-paper/85 backdrop-blur-md"
          : "border-b border-transparent bg-transparent"
      }`}
    >
      <nav className="container flex h-16 items-center justify-between lg:h-20">
        {/* Logo */}
        <a href="#" className="flex items-center gap-2.5">
          <PocketWatch className="h-7 w-7 text-gold" />
          <span className="font-display text-xl font-bold tracking-tight text-ink">
            Alice<span className="text-rose"> 听写</span>
          </span>
        </a>

        {/* Desktop nav */}
        <div className="hidden items-center gap-8 md:flex">
          {NAV_LINKS.map((link) => (
            <a
              key={link.href}
              href={link.href}
              className="text-sm text-ink/70 transition-colors hover:text-rose"
            >
              {link.label}
            </a>
          ))}
          <a
            href={GITHUB_URL}
            target="_blank"
            rel="noopener noreferrer"
            aria-label="GitHub 开源仓库"
            className="text-ink/70 transition-colors hover:text-rose"
          >
            <Github className="h-5 w-5" />
          </a>
          <a href="#download" className="btn-primary !px-5 !py-2.5">
            <Download className="h-4 w-4" />
            立即下载
          </a>
        </div>

        {/* Mobile toggle */}
        <button
          className="flex h-10 w-10 items-center justify-center rounded-lg text-ink md:hidden"
          onClick={() => setOpen((v) => !v)}
          aria-label="切换菜单"
        >
          {open ? <X className="h-5 w-5" /> : <Menu className="h-5 w-5" />}
        </button>
      </nav>

      {/* Mobile menu */}
      {open && (
        <div className="border-t border-ink/8 bg-paper/95 backdrop-blur-md md:hidden">
          <div className="container flex flex-col gap-1 py-4">
            {NAV_LINKS.map((link) => (
              <a
                key={link.href}
                href={link.href}
                onClick={() => setOpen(false)}
                className="rounded-lg px-3 py-3 text-sm text-ink/80 transition-colors hover:bg-parchment"
              >
                {link.label}
              </a>
            ))}
            <a
              href={GITHUB_URL}
              target="_blank"
              rel="noopener noreferrer"
              onClick={() => setOpen(false)}
              className="flex items-center gap-2 rounded-lg px-3 py-3 text-sm text-ink/80 transition-colors hover:bg-parchment"
            >
              <Github className="h-4 w-4" />
              GitHub 开源仓库
            </a>
            <a
              href="#download"
              onClick={() => setOpen(false)}
              className="btn-primary mt-2"
            >
              <Download className="h-4 w-4" />
              立即下载
            </a>
          </div>
        </div>
      )}
    </header>
  );
}

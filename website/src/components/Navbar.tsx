import { useEffect, useState } from "react";
import { Menu, X, Download } from "lucide-react";
import { PocketWatch } from "./Decorations";

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

/**
 * Wonderland 主题装饰元素：怀表、齿轮、扑克花色等。
 * 纯 SVG 装饰，用于烘托"爱丽丝梦游仙境"的文学氛围。
 */

export function PocketWatch({
  className = "",
  spin = false,
}: {
  className?: string;
  spin?: boolean;
}) {
  return (
    <svg
      viewBox="0 0 120 140"
      fill="none"
      className={`${className} ${spin ? "animate-spin-slower" : ""}`}
      aria-hidden="true"
    >
      {/* 表冠环 */}
      <line
        x1="60"
        y1="4"
        x2="60"
        y2="14"
        stroke="currentColor"
        strokeWidth="2"
      />
      <circle cx="60" cy="4" r="4" fill="currentColor" />
      {/* 表壳 */}
      <circle
        cx="60"
        cy="75"
        r="48"
        stroke="currentColor"
        strokeWidth="2.5"
        fill="none"
      />
      <circle
        cx="60"
        cy="75"
        r="42"
        stroke="currentColor"
        strokeWidth="1"
        fill="none"
        opacity="0.4"
      />
      {/* 刻度 */}
      {[0, 30, 60, 90, 120, 150, 180, 210, 240, 270, 300, 330].map((deg) => {
        const rad = (deg * Math.PI) / 180;
        const x1 = 60 + Math.sin(rad) * 40;
        const y1 = 75 - Math.cos(rad) * 40;
        const x2 = 60 + Math.sin(rad) * 45;
        const y2 = 75 - Math.cos(rad) * 45;
        return (
          <line
            key={deg}
            x1={x1}
            y1={y1}
            x2={x2}
            y2={y2}
            stroke="currentColor"
            strokeWidth={deg % 90 === 0 ? 2 : 1}
            opacity={deg % 90 === 0 ? 1 : 0.5}
          />
        );
      })}
      {/* 指针 */}
      <line
        x1="60"
        y1="75"
        x2="60"
        y2="48"
        stroke="currentColor"
        strokeWidth="2.5"
        strokeLinecap="round"
      />
      <line
        x1="60"
        y1="75"
        x2="82"
        y2="75"
        stroke="currentColor"
        strokeWidth="2"
        strokeLinecap="round"
      />
      <circle cx="60" cy="75" r="3" fill="currentColor" />
    </svg>
  );
}

export function Gear({
  className = "",
  teeth = 12,
}: {
  className?: string;
  teeth?: number;
}) {
  const path = Array.from({ length: teeth }, (_, i) => {
    const angle = (i / teeth) * Math.PI * 2;
    const inner = 28;
    const outer = 36;
    const cx = 50;
    const cy = 50;
    const a1 = angle;
    const a2 = angle + Math.PI / teeth;
    const x1 = cx + Math.cos(a1) * outer;
    const y1 = cy + Math.sin(a1) * outer;
    const x2 = cx + Math.cos(a2) * inner;
    const y2 = cy + Math.sin(a2) * inner;
    return `L${x1},${y1} L${x2},${y2}`;
  }).join(" ");

  return (
    <svg
      viewBox="0 0 100 100"
      fill="none"
      className={className}
      aria-hidden="true"
    >
      <path
        d={`M50,14 ${path} Z`}
        stroke="currentColor"
        strokeWidth="1.5"
        fill="none"
      />
      <circle
        cx="50"
        cy="50"
        r="20"
        stroke="currentColor"
        strokeWidth="1.5"
        fill="none"
      />
      <circle
        cx="50"
        cy="50"
        r="6"
        stroke="currentColor"
        strokeWidth="1.5"
        fill="none"
      />
    </svg>
  );
}

export function SuitSpade({ className = "" }: { className?: string }) {
  return (
    <svg
      viewBox="0 0 40 40"
      fill="currentColor"
      className={className}
      aria-hidden="true"
    >
      <path d="M20 6 C20 6 8 18 8 25 C8 30 12 33 16 33 C18 33 19 32 20 30 L18 34 L22 34 L20 30 C21 32 22 33 24 33 C28 33 32 30 32 25 C32 18 20 6 20 6 Z" />
    </svg>
  );
}

export function SuitHeart({ className = "" }: { className?: string }) {
  return (
    <svg
      viewBox="0 0 40 40"
      fill="currentColor"
      className={className}
      aria-hidden="true"
    >
      <path d="M20 33 C20 33 6 23 6 15 C6 10 10 7 14 7 C17 7 19 9 20 12 C21 9 23 7 26 7 C30 7 34 10 34 15 C34 23 20 33 20 33 Z" />
    </svg>
  );
}

/** 旋转的背景齿轮组 */
export function GearCluster({ className = "" }: { className?: string }) {
  return (
    <div
      className={`pointer-events-none absolute ${className}`}
      aria-hidden="true"
    >
      <Gear teeth={14} className="h-40 w-40 animate-spin-slow text-gold/15" />
      <Gear
        teeth={10}
        className="absolute -right-10 -bottom-10 h-24 w-24 animate-spin-slower text-rose/10"
      />
    </div>
  );
}

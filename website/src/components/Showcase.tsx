import { useReveal } from "../hooks/useReveal";
import { PhoneScreenshot, type AppShot } from "./PhoneMockup";
import { PocketWatch } from "./Decorations";

interface ShowCaseItem {
  eyebrow: string;
  title: string;
  desc: string;
  points: string[];
  shot: AppShot;
  reverse?: boolean;
}

const ITEMS: ShowCaseItem[] = [
  {
    eyebrow: "Step 01 · 入列",
    title: "拍照、粘贴或分享，单词入列",
    desc: "对准课本单词表拍照或从相册选取，选图后可裁切、旋转再交给 AI 识别，并补全词性与释义。也可以粘贴词表，或从别的应用直接分享过来。",
    points: [
      "拍照或相册选取，选后可裁切、旋转",
      "粘贴词表，或 Android 分享即成表",
      "识别与载入结果可随时编辑、撤销",
    ],
    shot: "home",
  },
  {
    eyebrow: "Step 02 · 词库",
    title: "不想拍照？290 套词表开箱即用",
    desc: "中考 1600、高考 3500，人教、外研、闽教、仁爱版单元词表逐课收录，搜索即达，点击即载入。",
    points: ["290 套词表 · 中考 1600 · 高考 3500", "教材单元词表逐课收录，可收藏", "标题、分类模糊搜索"],
    shot: "library",
    reverse: true,
  },
  {
    eyebrow: "Step 03 · 听写",
    title: "逐词朗读，重听与语速都在手边",
    desc: "怀表倒计时逐词朗读。听写中可重听、切词、调语速，也可打开中文释义。屏幕常亮，切后台会自动暂停。",
    points: [
      "点表盘或「重听」再听当前词",
      "间隔 1–10s · 语速可调 · 可选朗读释义",
      "显示/隐藏当前词 · 一键标记错词",
    ],
    shot: "dictation",
  },
  {
    eyebrow: "Step 04 · 回顾",
    title: "错词留在成绩单上，再听一遍",
    desc: "听写完成即出成绩：单词、错词、用时，错了哪几个直接列在卡片上。可再听错词，或导出反复练习。",
    points: ["单词 / 错词 / 用时，错词列在成绩单", "错词再听一遍", "错词本导出与清空"],
    shot: "finish",
    reverse: true,
  },
];

export function Showcase() {
  return (
    <section className="relative overflow-hidden py-24 lg:py-32">
      {/* 背景装饰 */}
      <div className="pointer-events-none absolute left-0 top-1/3 hidden text-gold/8 lg:block">
        <PocketWatch className="h-48 w-48 animate-spin-slower" />
      </div>

      <div className="container relative z-10">
        <div className="mx-auto mb-20 max-w-2xl text-center">
          <div className="eyebrow mb-4">
            <span>In Action</span>
          </div>
          <h2 className="heading-serif text-4xl sm:text-5xl">
            从拍照到回顾，
            <span className="italic text-rose"> 一气呵成</span>
          </h2>
        </div>

        <div className="space-y-24 lg:space-y-32">
          {ITEMS.map((item, i) => (
            <ShowcaseRow key={i} item={item} />
          ))}
        </div>
      </div>
    </section>
  );
}

function ShowcaseRow({ item }: { item: ShowCaseItem }) {
  const { ref, visible } = useReveal();

  return (
    <div
      ref={ref}
      className={`grid items-center gap-12 lg:grid-cols-2 lg:gap-16 ${
        item.reverse ? "lg:[&>*:first-child]:order-2" : ""
      }`}
    >
      {/* 文字 */}
      <div
        className={`reveal ${visible ? "is-visible" : ""}`}
        style={{ transitionDelay: "100ms" }}
      >
        <div className="eyebrow eyebrow-left mb-4">
          <span>{item.eyebrow}</span>
        </div>
        <h3 className="heading-serif text-3xl sm:text-4xl">{item.title}</h3>
        <p className="mt-5 text-base leading-relaxed text-ink/65">
          {item.desc}
        </p>
        <ul className="mt-6 space-y-3">
          {item.points.map((p) => (
            <li key={p} className="flex items-center gap-3 text-sm text-ink/75">
              <span className="flex h-5 w-5 items-center justify-center rounded-full bg-rose/15 text-[10px] text-rose">
                ✦
              </span>
              {p}
            </li>
          ))}
        </ul>
      </div>

      {/* 手机模拟 */}
      <div
        className={`reveal flex justify-center ${visible ? "is-visible" : ""}`}
        style={{ transitionDelay: "250ms" }}
      >
        <div className="relative">
          <div className="absolute inset-0 -z-10 scale-110 rounded-full bg-linear-to-tr from-gold/8 to-rose/8 blur-3xl" />
          <PhoneScreenshot shot={item.shot} />
        </div>
      </div>
    </div>
  );
}

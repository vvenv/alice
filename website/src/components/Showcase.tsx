import { useReveal } from "../hooks/useReveal";
import {
  PhoneFrame,
  DictationScreenMock,
  FinishScreenMock,
  HomeScreenMock,
  LibraryScreenMock,
} from "./PhoneMockup";
import { PocketWatch } from "./Decorations";

interface ShowCaseItem {
  eyebrow: string;
  title: string;
  desc: string;
  points: string[];
  mock: React.ReactNode;
  reverse?: boolean;
}

const ITEMS: ShowCaseItem[] = [
  {
    eyebrow: "Step 01 · 识别",
    title: "拍一张照片，单词自动入列",
    desc: "对准课本单词表，AI 数秒内完成识别，自动补全词性与释义，瞬间生成听写列表。",
    points: ["AI 智能识别，印刷体与手写均可", "自动补全词性与中文释义", "识别结果可随时编辑"],
    mock: <HomeScreenMock />,
  },
  {
    eyebrow: "Step 02 · 词库",
    title: "不想拍照？词库开箱即用",
    desc: "内置中考 1600、高考 3500 与人教、外研、闽教版教材单元词表，搜索即达，点击即载入。",
    points: ["中考 1600 · 高考 3500", "教材单元词表逐课收录", "标题、分类模糊搜索"],
    mock: <LibraryScreenMock />,
    reverse: true,
  },
  {
    eyebrow: "Step 03 · 听写",
    title: "逐词朗读，间隔随心",
    desc: "怀表式倒计时逐词朗读，间隔可调、自动连播。单词可显示或隐藏，写错随手标记。",
    points: ["怀表倒计时，节奏尽在掌握", "间隔 1–10s 可调 · 自动连播", "显示/隐藏切换 · 一键标记错词"],
    mock: <DictationScreenMock />,
  },
  {
    eyebrow: "Step 04 · 回顾",
    title: "错词留痕，有的放矢",
    desc: "听写完成即出成绩单，错词自动收入错词本。一键再听一遍，或导出反复练习。",
    points: ["单词 / 错词 / 用时统计", "错词再听一遍", "一键导出错词本"],
    mock: <FinishScreenMock />,
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
          <div className="absolute inset-0 -z-10 scale-110 rounded-full bg-gradient-to-tr from-gold/8 to-rose/8 blur-3xl" />
          <PhoneFrame>{item.mock}</PhoneFrame>
        </div>
      </div>
    </div>
  );
}

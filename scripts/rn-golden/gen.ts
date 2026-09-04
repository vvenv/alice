import * as fs from "node:fs";
import { parseWords, parseWordLine, parseWordEntries, entryToLine, speakTextFromEntry } from "./dictation";
import { splitSenses, sensesClamped, lookupWordMeta, enrichWordListText } from "./dictionary";
import { extractWordsFromOcrText } from "./ocrwords";

const WORD_LINES = [
  "apple", "  banana  ", "apple | n. | 苹果", "cat|n.|猫",
  "actor / actress", "you're = you are", "you're＝you are",
  "look forward to | | 期待", "ice cream | n.", "全角｜pos｜释义",
  "", "   ", "a/an", "X-ray", "well-known | adj. | 著名的",
  "run | v. | 跑；经营；运转", "set = set up", "abc | n. | ",
];

const MULTILINE = [
  "apple\nbanana\ncat",
  "apple | n. | 苹果\n\nbanana | n. | 香蕉\r\ncat",
  "  \n \n",
  "you're = you are\nactor / actress\nice cream",
  "hello\nworld\nhello",
];

const MEANINGS: [string, string | undefined][] = [
  ["苹果", "n."],
  ["n. 苹果；v. 摘苹果", "n."],
  ["跑；经营；运转", "v."],
  ["adj. 著名的；adv. 很好地", "adj."],
  ["著名的", undefined],
  ["a. 好的；n. 好处", "adj."],
  ["vt. 打开；vi. 开始；n. 空地", "n."],
  ["", "n."],
  ["；；", "v."],
  ["【计】计算机术语", "n."],
];

const CLAMP_CASES: [string[], number, number][] = [
  [["n. 苹果"], 2, 14],
  [["n. 苹果；香蕉；橘子；葡萄；西瓜；草莓"], 2, 14],
  [["n. 苹果", "v. 摘苹果", "adj. 苹果的"], 2, 20],
  [[], 2, 14],
  [["a very long english meaning that goes on and on and on"], 2, 14],
];

const OCR_TEXTS = [
  "apple\nbanana\ncat",
  "1. apple\n2. banana\n3. cat",
  "apple, banana, cat, dog",
  "apple | n. | 苹果\nbanana | n. | 香蕉",
  "```\napple\nbanana\n```",
  "apple banana cat dog elephant fish grape",
  "actor / actress\nice cream\nlook forward to",
  "“apple”\n‘banana’\ncat.",
  "APPLE\napple\nApple",
  "苹果\nbanana\n123\napple2",
  "- apple\n• banana\n* cat",
  "apple，banana；cat、dog",
  "",
  "the quick brown fox jumps over the lazy dog and keeps running forever",
  "apple |  | \nbanana | n. |  | extra",
];

const LOOKUP_WORDS = [
  "apple", "Apple", "APPLE", "banana", "run", "well-known",
  "a/an", "ice cream", "actor / actress", "apple.", "zzzznotaword",
  "", "  cat  ", "X-ray", "you're",
];

const ENRICH_TEXTS = [
  "apple\nbanana\ncat",
  "apple | n. | 已有释义\nbanana",
  "you're = you are\nactor / actress",
  "zzzznotaword\napple",
  "",
];

const golden = {
  parseWords: MULTILINE.map((input) => ({ input, output: parseWords(input) })),
  parseWordLine: WORD_LINES.map((input) => {
    const e = parseWordLine(input);
    return { input, word: e.word, pos: e.pos ?? null, meaning: e.meaning ?? null };
  }),
  entryToLine: WORD_LINES.map((input) => ({
    input,
    output: entryToLine(parseWordLine(input)),
  })),
  speakTextFromEntry: WORD_LINES.map((input) => ({
    input,
    output: speakTextFromEntry(input),
  })),
  parseWordEntries: MULTILINE.map((input) => ({
    input,
    output: parseWordEntries(input).map((e) => ({
      word: e.word,
      pos: e.pos ?? null,
      meaning: e.meaning ?? null,
    })),
  })),
  splitSenses: MEANINGS.map(([meaning, pos]) => ({
    meaning,
    pos: pos ?? null,
    output: splitSenses(meaning, pos),
  })),
  sensesClamped: CLAMP_CASES.map(([senses, lines, cpl]) => ({
    senses,
    collapsedLines: lines,
    charsPerLine: cpl,
    output: sensesClamped(senses, lines, cpl),
  })),
  extractWordsFromOcrText: OCR_TEXTS.map((input) => ({
    input,
    output: extractWordsFromOcrText(input),
  })),
  lookupWordMeta: LOOKUP_WORDS.map((input) => {
    const m = lookupWordMeta(input);
    return { input, pos: m?.pos ?? null, meaning: m?.meaning ?? null };
  }),
  enrichWordListText: ENRICH_TEXTS.map((input) => ({
    input,
    output: enrichWordListText(input),
  })),
};

fs.writeFileSync(process.argv[2], JSON.stringify(golden, null, 2));
console.log(
  Object.entries(golden)
    .map(([k, v]) => `${k}: ${(v as unknown[]).length}`)
    .join("\n"),
);

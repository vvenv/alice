import * as fs from "node:fs";
import { parseWords, parseWordLine, parseWordEntries, entryToLine, speakTextFromEntry, normalizePos, speakableMeaning } from "./dictation";
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
  ["interj. 喂；exclam. 啊", "int."],
  ["na. 名词性用法；un. 不可数", "n."],
  ["vbl. 动词形式；pp. 过去分词", "v."],
  ["pref. 前缀；suff. 后缀", "abbr."],
  ["n. 苹果；interj. 喂", "a."],
  ["pl. 复数形式", "pl."],
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
  // 以下针对 main 的 leadingEnglishRun / englishPhrase / englishCandidates：
  "apple /\u02c8\u00e6pl/ n. \u82f9\u679c",
  "apple /\u02c8\u00e6pl/ | n. | \u82f9\u679c",
  "\u82f9\u679c apple",
  "\u82f9\u679c | n. | apple",
  "/\u02c8\u00e6pl/",
  "actor / actress | n. | \u6f14\u5458",
  "apple /",
  "/ apple",
  "actor / actress / singer",
  "apple / banana / cat / dog / elephant",
  "look forward to \u671f\u5f85",
  "ice cream n. \u51b0\u6dc7\u6dcb\n\u5de7\u514b\u529b chocolate",
  "well-known adj. \u8457\u540d\u7684, famous adj. \u51fa\u540d\u7684",
  "one two three four five six \u4e2d\u6587",
  "X-ray /\u02c8eks re\u026a/ n. X \u5149",
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


/** normalizePos：ECDICT 原文与教材习惯的词性缩写差异。 */
const POS_INPUTS = [
  "n.", "N.", " v. ", "vt.", "vi.", "adj.", "a.", "adv.", "prep.", "conj.",
  "pron.", "num.", "art.", "int.", "interj.", "exclam.", "aux.", "abbr.",
  "contr.", "pl.", "na.", "un.", "pla.", "pn.", "vbl.", "pp.", "pref.",
  "suf.", "suff.", "comb.", "stuff.", "quant.", "phr.", "ph.", "st.",
  "pr.", "ind.", "pers.", "col.", "ing.", "", "  ", "zzz.", "N.  ",
];

/** speakableMeaning：朗读用的中文释义（去词性、取首义项、去括号、超长截断）。 */
const SPEAK_MEANINGS: (string | undefined)[] = [
  undefined,
  "",
  "苹果",
  "n. 苹果",
  "n. 苹果；v. 摘苹果",
  "adj. 著名的；adv. 很好地",
  "跑；经营；运转",
  "（缩）美国国家航空航天局",
  "n. （美）人行道",
  "n.",
  "；；",
  "苹果，梨，橘子，葡萄，西瓜，草莓，蓝莓，樱桃",
  "计算机辅助教育, 计算机辅助测试, 计算机辅助翻译, 计算机辅助排版",
  "a very long english meaning that goes on and on and on and on",
  "  n.   苹果  ；  香蕉  ",
  "（break 的过去时）折断；打破",
  "n. (pl.knives) 小刀",
  "，、。",
  "abbr. CD player",
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
  normalizePos: POS_INPUTS.map((input) => ({
    input,
    output: normalizePos(input),
  })),
  speakableMeaning: SPEAK_MEANINGS.map((input) => ({
    input: input ?? null,
    output: speakableMeaning(input),
  })),
};

fs.writeFileSync(process.argv[2], JSON.stringify(golden, null, 2));
console.log(
  Object.entries(golden)
    .map(([k, v]) => `${k}: ${(v as unknown[]).length}`)
    .join("\n"),
);

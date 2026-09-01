/**
 * Split multiline word-list input into entries (one per non-empty line).
 */
export function parseWords(text: string): string[] {
  return text
    .split(/[\n\r]+/)
    .map((word) => word.trim())
    .filter((word) => word.length > 0);
}

export interface WordEntry {
  /** 单词/词组（可能含 = 展开语法） */
  word: string;
  /** 词性，如 "n." "v." "adj." */
  pos?: string;
  /** 中文释义 */
  meaning?: string;
}

/** 词性前缀（ECDICT 与用户词表通用），如 "n." "vt." "adj."。 */
export const POS_PREFIX_RE =
  /^(n\.|v\.|vt\.|vi\.|adj\.|adv\.|prep\.|conj\.|pron\.|num\.|art\.|int\.|interj\.|aux\.|abbr\.|contr\.|pl\.|a\.|na\.|un\.|vbl\.|pp\.|pn\.|exclam\.|pref\.|suf\.|suff\.|comb\.|quant\.|phr\.|ph\.|st\.|pr\.|ind\.|pers\.|col\.|ing\.|pla\.|stuff\.)\s*/i;

/**
 * 归一化词性缩写（ECDICT 原文与教材习惯的差异，构建脚本同款映射）：
 * interj./exclam.→int.，na./un./pla./pn.→n.，vbl./pp.→v.，
 * pref./suf./suff./comb./stuff.→abbr.，a.→adj.，pl.→n.
 */
export function normalizePos(pos: string): string {
  const key = pos.trim().toLowerCase();
  if (key === "a.") return "adj.";
  if (key === "pl.") return "n.";
  if (key === "interj." || key === "exclam.") return "int.";
  if (key === "na." || key === "un." || key === "pla." || key === "pn.")
    return "n.";
  if (key === "vbl." || key === "pp.") return "v.";
  if (
    key === "pref." ||
    key === "suf." ||
    key === "suff." ||
    key === "comb." ||
    key === "stuff."
  )
    return "abbr.";
  return key;
}
const PIPE = "|";
const FULLWIDTH_PIPE = "｜";

/**
 * Parse a single line into a structured entry.
 *
 * Format: `word | pos | meaning` (pipe-separated). Only `word` is required;
 * `pos` and `meaning` are optional. A line with no pipe is just a word.
 */
export function parseWordLine(line: string): WordEntry {
  const trimmed = line.trim();
  if (!trimmed) return { word: "" };

  const parts = trimmed.split(new RegExp(`[${PIPE}${FULLWIDTH_PIPE}]`));
  const word = parts[0]?.trim() ?? "";
  const pos = parts[1]?.trim() || undefined;
  const meaning = parts[2]?.trim() || undefined;

  return { word, pos, meaning };
}

/**
 * Parse multiline text into structured entries.
 */
export function parseWordEntries(text: string): WordEntry[] {
  return parseWords(text).map(parseWordLine);
}

/**
 * Serialize a WordEntry back to a line string.
 */
export function entryToLine(entry: WordEntry): string {
  const { word, pos, meaning } = entry;
  if (!pos && !meaning) return word;
  return [word, pos ?? "", meaning ?? ""].join(` ${PIPE} `);
}

/**
 * Text to speak for a list entry.
 *
 * - Strips `|`-delimited pos/meaning suffix (TTS must not read them).
 * - Supports expansion-style entries like `you're = you are`: speak the left
 *   side (`you're`), while the full line remains the display/answer text.
 */
export function speakTextFromEntry(entry: string): string {
  let text = entry.trim();
  if (!text) return "";

  // Strip pos/meaning after the pipe delimiter
  const pipe = text.indexOf(PIPE);
  if (pipe !== -1) text = text.slice(0, pipe).trim();
  if (!text) return "";

  const eq = text.search(/[=＝]/);
  if (eq === -1) return text;

  const left = text.slice(0, eq).trim();
  return left || text;
}

const SENSE_SPLIT_RE = /[；;]/;
const GLOSS_SPLIT_RE = /[，,、]/;
const MEANING_PAREN_RE = /[（(][^（）()]*[）)]/g;
const MEANING_EDGE_PUNCT_RE = /^[\s，,、。.：:；;]+|[\s，,、。.：:；;]+$/g;
/** 朗读释义的长度上限（视觉宽度，全角 1、半角 0.5），超过则截取首个词条。 */
const SPEAK_MEANING_MAX_WIDTH = 12;

/** 全角记 1 字宽、半角记 0.5（与 dictionary.ts 的 sensesClamped 同一口径）。 */
function meaningWidth(text: string): number {
  let width = 0;
  for (const ch of text) width += ch.charCodeAt(0) > 0x2e7f ? 1 : 0.5;
  return width;
}

/**
 * 朗读用的中文释义。与释义展示不同，TTS 只需要最核心的一个意思：
 *
 * - 去掉词性前缀（"n." "vt." 等会被 TTS 逐字念出）；
 * - 多义项（「；」分隔，构建脚本与 enrichWordListText 保证）只取第一个非空义项；
 * - 括号补注（缩写的英文全称等）不朗读；
 * - 首义项仍超长时（同义词枚举）截取首个词条。
 *
 * 返回空串表示没有可朗读的内容（如整个释义只有词性标记）。
 */
export function speakableMeaning(meaning: string | undefined): string {
  if (!meaning) return "";
  for (const raw of meaning.split(SENSE_SPLIT_RE)) {
    let text = raw.trim();
    const pos = text.match(POS_PREFIX_RE);
    if (pos) text = text.slice(pos[0].length).trim();
    text = text.replace(MEANING_PAREN_RE, "").trim();
    text = text.replace(MEANING_EDGE_PUNCT_RE, "");
    if (!text) continue;

    if (meaningWidth(text) > SPEAK_MEANING_MAX_WIDTH) {
      text = text.split(GLOSS_SPLIT_RE)[0] ?? text;
      text = text.replace(MEANING_EDGE_PUNCT_RE, "");
      if (!text) continue;
    }
    return text;
  }
  return "";
}

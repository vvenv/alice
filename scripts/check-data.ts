import * as fs from "fs";
import * as path from "path";

/**
 * Validates the word lists under data/ (same layout generate-library.ts reads).
 * Run via `pnpm data:check`; wired into CI next to `pnpm lint`.
 *
 * Field conventions (mirrors the header of scripts/generate-library.ts):
 * `word | pos | meaning` — 1 or 3 pipe-separated columns, fullwidth ｜ accepted.
 *
 * Errors (contract violations that break dictation behaviour):
 * - line is not 1 or 3 columns, or word column is empty
 * - CJK single-char entry whose pos is not a pinyin syllable (latin/ü with
 *   optional tone marks; digit-toned "hao2" rejected) — dictation.ts
 *   toneToDigit() relies on tone marks for polyphone candidate filtering
 * - duplicate word within one file
 *
 * Warnings (style/convention drift, not blocking):
 * - CJK single-char entry with empty meaning (组词 column expected)
 * - CJK single-char entry whose meaning has no 2-char chunk containing the
 *   head char — 组词朗读 (dictation.ts cjkWordSpeech) then falls back to
 *   learned/common-word candidates
 * - empty file
 *
 * Cross-file duplicates are reported as info only: the same char recurs
 * across lessons by design (e.g. 似 in 阅读 17 and 阅读 18).
 */

const DATA_DIR = path.resolve(import.meta.dirname, "../data");

const CJK_CHAR_RE = /^[\u4e00-\u9fff]$/;
// Pinyin syllable: lowercase latin incl. ü, tone-marked vowels allowed, no digits/spaces.
const PINYIN_RE = /^[a-zāáǎàēéěèīíǐìōóǒòūúǔùǖǘǚǜ]+$/;
const CHUNK_SPLIT_RE = /[；;，,、。.\s]+/;

interface FileReport {
  label: string;
  entries: number;
  words: string[];
  errors: string[];
  warnings: string[];
}

function collectFiles(): { category: string; file: string }[] {
  const files: { category: string; file: string }[] = [];
  for (const top of fs.readdirSync(DATA_DIR, { withFileTypes: true })) {
    if (top.isDirectory()) {
      for (const f of fs.readdirSync(path.join(DATA_DIR, top.name))) {
        if (f.endsWith(".txt")) {
          files.push({ category: top.name, file: path.join(DATA_DIR, top.name, f) });
        }
      }
    } else if (top.isFile() && top.name.endsWith(".txt")) {
      files.push({ category: "其他", file: path.join(DATA_DIR, top.name) });
    }
  }
  return files.sort((a, b) => a.file.localeCompare(b.file));
}

function checkFile(category: string, file: string): FileReport {
  const label = `${path.relative(DATA_DIR, file)} [${category}]`;
  const report: FileReport = { label, entries: 0, words: [], errors: [], warnings: [] };
  const firstLineOf = new Map<string, number>();

  const content = fs.readFileSync(file, "utf-8");
  if (content.trim() === "") {
    report.warnings.push("empty file");
    return report;
  }

  content.split(/[\n\r]+/).forEach((raw, i) => {
    const line = raw.trim();
    if (!line) return;
    const lineNo = i + 1;
    report.entries += 1;

    const parts = line.split(/[|｜]/).map((p) => p.trim());
    if (parts.length !== 1 && parts.length !== 3) {
      report.errors.push(`L${lineNo}: expected 1 or 3 columns, got ${parts.length}: ${JSON.stringify(line)}`);
      return;
    }
    const [word, pos, meaning] = parts;
    if (!word) {
      report.errors.push(`L${lineNo}: empty word column`);
      return;
    }
    report.words.push(word);

    const prev = firstLineOf.get(word);
    if (prev !== undefined) {
      report.errors.push(`L${lineNo}: duplicate word ${JSON.stringify(word)} (first at L${prev})`);
    } else {
      firstLineOf.set(word, lineNo);
    }

    if (CJK_CHAR_RE.test(word)) {
      if (pos !== undefined && !PINYIN_RE.test(pos)) {
        report.errors.push(
          `L${lineNo}: ${word} | ${JSON.stringify(pos)} is not a pinyin syllable (use tone marks, e.g. "háo"; neutral tones unmarked, e.g. "ma")`,
        );
      }
      if (!meaning) {
        report.warnings.push(`L${lineNo}: ${word} has empty 组词/meaning column`);
      } else if (!meaning.split(CHUNK_SPLIT_RE).some((chunk) => chunk.includes(word))) {
        report.warnings.push(`L${lineNo}: ${word} meaning ${JSON.stringify(meaning)} has no chunk containing the head char`);
      }
    }
  });

  return report;
}

const reports = collectFiles().map(({ category, file }) => checkFile(category, file));

const totalEntries = reports.reduce((n, r) => n + r.entries, 0);
const errors = reports.flatMap((r) => r.errors.map((e) => `${r.label}: ${e}`));
const warnings = reports.flatMap((r) => r.warnings.map((w) => `${r.label}: ${w}`));

// Info only: words recurring across files are expected (lessons reuse chars/words).
const seenAnywhere = new Set<string>();
const multiFileWords = new Set<string>();
for (const r of reports) {
  for (const word of r.words) {
    if (seenAnywhere.has(word)) multiFileWords.add(word);
    else seenAnywhere.add(word);
  }
}

for (const w of warnings) console.warn(`WARN  ${w}`);
if (multiFileWords.size > 0) {
  console.warn(`INFO  ${multiFileWords.size} word(s) appear in multiple files (expected across lessons)`);
}

if (errors.length > 0) {
  for (const e of errors) console.error(`ERROR ${e}`);
  console.error(
    `\ndata:check FAILED — ${reports.length} files, ${totalEntries} entries, ${errors.length} error(s), ${warnings.length} warning(s)`,
  );
  process.exit(1);
}

console.log(
  `data:check OK — ${reports.length} files, ${totalEntries} entries, 0 errors, ${warnings.length} warning(s), ${multiFileWords.size} cross-file dup word(s)`,
);

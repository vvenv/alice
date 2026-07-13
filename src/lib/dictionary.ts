import { Platform } from "react-native";

import { config } from "./config";
import { createLogger } from "./logger";

const log = createLogger("DICT");

/**
 * Youdao's jsonapi rejects cross-origin browser requests with 403
 * "Invalid CORS request" — the browser auto-attaches an Origin header that
 * can't be removed. Native (RN) fetch has no CORS, so Youdao works there.
 * Skip the Youdao phase entirely on web and rely on the LLM batch.
 */
const YOUDAO_DISABLED = Platform.OS === "web";

const YOUDAO_API = "https://dict.youdao.com/jsonapi";
/** Per-word Youdao request timeout. Youdao 403s return fast, so this mainly
 *  caps slow/hanging connections. */
const YOUDAO_FETCH_TIMEOUT_MS = 4000;
/** Per LLM batch request timeout. */
const LLM_BATCH_TIMEOUT_MS = 20000;
/** Max words per LLM batch request — keeps prompt/response within token
 *  limits and reduces the blast radius of a single failed request. */
const LLM_BATCH_SIZE = 25;

export interface WordMeta {
  pos?: string;
  meaning?: string;
}

// ---------------------------------------------------------------------------
// Youdao dictionary (unofficial, free, no API key)
// ---------------------------------------------------------------------------

interface YoudaoSimpleWord {
  pos?: string;
  tran?: string;
}

interface YoudaoResponse {
  simple?: { word?: YoudaoSimpleWord[] };
  ec?: {
    word?: {
      trs?: YoudaoSimpleWord[];
    };
  };
}

/**
 * Query a single word from Youdao's free jsonapi.
 *
 * The endpoint rejects bare requests with 403, so we send browser-like
 * Referer/User-Agent headers. Best-effort: returns null on any failure
 * (403, network, parse, timeout) so the caller can fall back to the LLM.
 *
 * Self-manages a per-request timeout and links to an optional parent signal
 * (so an abort from the caller — e.g. exiting dictation — cancels in-flight
 * requests).
 */
async function fetchFromYoudao(
  word: string,
  parentSignal?: AbortSignal,
): Promise<WordMeta | null> {
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), YOUDAO_FETCH_TIMEOUT_MS);
  const onParentAbort = () => controller.abort();
  if (parentSignal) {
    if (parentSignal.aborted) controller.abort();
    else parentSignal.addEventListener("abort", onParentAbort, { once: true });
  }

  try {
    const url = `${YOUDAO_API}?q=${encodeURIComponent(word)}`;
    const resp = await fetch(url, {
      signal: controller.signal,
      headers: {
        Referer: `https://dict.youdao.com/w/${encodeURIComponent(word)}/`,
        "User-Agent":
          "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1",
      },
    });
    if (!resp.ok) return null;

    const data = (await resp.json()) as YoudaoResponse;

    // Prefer the "simple" dictionary (most concise), then "ec" (English-Chinese)
    const simple = data.simple?.word?.[0];
    if (simple?.tran) {
      return { pos: simple.pos || undefined, meaning: simple.tran };
    }

    const ecTr = data.ec?.word?.trs?.[0];
    if (ecTr?.tran) {
      return { pos: ecTr.pos || undefined, meaning: ecTr.tran };
    }

    return null;
  } finally {
    clearTimeout(timer);
    if (parentSignal) parentSignal.removeEventListener("abort", onParentAbort);
  }
}

// ---------------------------------------------------------------------------
// Zhipu LLM — batch
// ---------------------------------------------------------------------------

/**
 * Strip markdown code fences (```json ... ```) from an LLM response.
 */
function stripCodeFences(text: string): string {
  return text
    .replace(/^```(?:json)?\s*/i, "")
    .replace(/\s*```$/i, "")
    .trim();
}

/**
 * Batch-fetch meta for multiple words in a single LLM call.
 *
 * Returns a map of word -> {pos, meaning} for words the model responded to.
 * Words the model omitted or hallucinated are simply absent from the result.
 * Self-manages timeout + parent-signal linking.
 */
async function fetchFromZhipuBatch(
  words: string[],
  parentSignal?: AbortSignal,
): Promise<Map<string, WordMeta>> {
  const result = new Map<string, WordMeta>();
  const url = `${config.zhipuBaseUrl}/chat/completions`;

  const list = words.map((w, i) => `${i + 1}. ${w}`).join("\n");
  const prompt = [
    "请为以下英文单词或词组批量提供词性和中文释义。",
    "",
    "单词列表：",
    list,
    "",
    "只返回 JSON，格式为：",
    '{"单词1":{"pos":"词性缩写","meaning":"中文释义"},"单词2":{"pos":"...","meaning":"..."},...}',
    "不要输出其他内容。词性用缩写（n. v. adj. adv. prep. conj. pron. 等），多义词只给最常用释义。",
  ].join("\n");

  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), LLM_BATCH_TIMEOUT_MS);
  const onParentAbort = () => controller.abort();
  if (parentSignal) {
    if (parentSignal.aborted) controller.abort();
    else parentSignal.addEventListener("abort", onParentAbort, { once: true });
  }

  try {
    const resp = await fetch(url, {
      method: "POST",
      headers: {
        Authorization: `Bearer ${config.zhipuApiKey}`,
        "Content-Type": "application/json",
      },
      signal: controller.signal,
      body: JSON.stringify({
        model: config.textModel,
        temperature: 0.1,
        messages: [{ role: "user", content: prompt }],
      }),
    });

    if (!resp.ok) {
      log.debug("Zhipu batch HTTP", resp.status);
      return result;
    }

    const payload = (await resp.json()) as {
      choices?: Array<{ message?: { content?: string } }>;
    };
    const content = payload.choices?.[0]?.message?.content?.trim() ?? "";
    if (!content) return result;

    const jsonStr = stripCodeFences(content);

    let parsed: Record<string, { pos?: string; meaning?: string }>;
    try {
      parsed = JSON.parse(jsonStr);
    } catch {
      log.debug("Zhipu batch response not valid JSON:", content);
      return result;
    }

    // Only accept words we actually requested (ignore hallucinated keys).
    const requested = new Set(words);
    for (const [word, meta] of Object.entries(parsed)) {
      if (!requested.has(word)) continue;
      if (!meta || (!meta.pos && !meta.meaning)) continue;
      result.set(word, {
        pos: meta.pos || undefined,
        meaning: meta.meaning || undefined,
      });
    }
  } catch (e) {
    if (!controller.signal.aborted || parentSignal?.aborted) {
      log.debug("Zhipu batch failed:", words, e);
    }
  } finally {
    clearTimeout(timer);
    if (parentSignal) parentSignal.removeEventListener("abort", onParentAbort);
  }

  return result;
}

// ---------------------------------------------------------------------------
// Public API — batch
// ---------------------------------------------------------------------------

/**
 * Batch-fetch word meta (pos + meaning) for a list of words.
 *
 * Strategy (Youdao-first, LLM batch fallback):
 * 1. Query Youdao per-word concurrently (free, fast when it works). Each hit
 *    is reported via `onPartial` immediately so the UI can populate as
 *    results arrive.
 * 2. Collect Youdao misses and query them in chunked Zhipu LLM batch calls
 *    (LLM_BATCH_SIZE words per call). Each hit is reported via `onPartial`.
 *
 * Both phases are best-effort: words that fail both sources simply stay
 * absent from the result map, and the caller displays them without meta.
 *
 * @param words     Clean words/phrases to look up (no pipe or = syntax).
 * @param onPartial Called as each word's meta becomes available (progressive).
 * @param signal    Optional abort signal — aborts all in-flight requests.
 * @returns Complete map of word -> meta for all words that resolved.
 */
export async function fetchWordMetaBatch(
  words: string[],
  onPartial?: (word: string, meta: WordMeta) => void,
  signal?: AbortSignal,
): Promise<Map<string, WordMeta>> {
  const result = new Map<string, WordMeta>();
  const clean = words.map((w) => w.trim()).filter(Boolean);
  if (clean.length === 0) return result;

  // ---- Phase 1: Youdao per-word (concurrent, best-effort) ----
  // Skipped on web — Youdao blocks cross-origin browser requests with 403.
  const misses: string[] = YOUDAO_DISABLED ? [...clean] : [];
  if (!YOUDAO_DISABLED) {
    await Promise.all(
      clean.map(async (word) => {
        if (signal?.aborted) return;
        try {
          const meta = await fetchFromYoudao(word, signal);
          if (meta && (meta.pos || meta.meaning)) {
            result.set(word, meta);
            onPartial?.(word, meta);
          } else {
            misses.push(word);
          }
        } catch {
          misses.push(word);
        }
      }),
    );
  }

  if (signal?.aborted) return result;

  // ---- Phase 2: Zhipu LLM batch for misses (chunked) ----
  for (let i = 0; i < misses.length; i += LLM_BATCH_SIZE) {
    if (signal?.aborted) break;
    const chunk = misses.slice(i, i + LLM_BATCH_SIZE);
    const batchResult = await fetchFromZhipuBatch(chunk, signal);
    for (const [word, meta] of batchResult) {
      result.set(word, meta);
      onPartial?.(word, meta);
    }
  }

  return result;
}

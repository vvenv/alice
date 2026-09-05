import * as ImageManipulator from "expo-image-manipulator";
import * as ImagePicker from "expo-image-picker";
import { Platform } from "react-native";

import { config } from "./config";
import {
  ensureCreditsLoaded,
  getBuiltinModel,
  loadSelectedModelId,
  trySpendCredits,
} from "./credits";
import {
  buildChatCompletionsUrl,
  isCustomOcrConfigSet,
  loadOcrProviderConfig,
  requiresCustomOcrConfig,
} from "./ocrConfig";

const OCR_MAX_EDGE = 1600;
const OCR_JPEG_QUALITY = 0.82;
const OCR_IMAGE_PICKER: ImagePicker.ImagePickerOptions = {
  mediaTypes: ["images"],
  quality: 1,
  // Android system crop is square-only and flaky on some OEMs.
  allowsEditing: Platform.OS === "ios",
};

/** Disclaimer surfaced at OCR entry points so users know results may be off. */
export const OCR_DISCLAIMER = "AI 识图可能存在误差，请核对识别结果";

/**
 * Thrown when a premium built-in model is selected but the credit balance is
 * insufficient. The UI catches this to open the recharge flow instead of
 * showing a generic error toast.
 */
export class InsufficientCreditsError extends Error {
  constructor(public cost: number) {
    super("Credits 不足，请充值后使用高级识别");
    this.name = "InsufficientCreditsError";
  }
}

/** In-flight progress phases (header). Terminal copy lives in OCR_OUTCOME_MESSAGES. */
export type OcrProgressPhase =
  | "preparing_photo"
  | "preparing_album"
  | "compressing"
  | "recognizing";

export const OCR_PROGRESS_MESSAGES: Record<OcrProgressPhase, string> = {
  preparing_photo: "已拍摄，准备识别…",
  preparing_album: "已选图，准备识别…",
  compressing: "处理图片中…",
  recognizing: "识别中…",
};

export const OCR_OUTCOME_MESSAGES = {
  success: (count: number) => `已识别 ${count} 个单词`,
  empty: "未识别到英文单词，请换一张更清晰的图片再试",
  emptyUnparsed:
    "未能从识别结果中提取英文单词，请换一张更清晰的单词列表再试",
  failed: "识别失败",
} as const;

export type OcrUiState = {
  busy: boolean;
  message: string;
};

export const OCR_UI_IDLE: OcrUiState = { busy: false, message: "" };

function uriToBase64(uri: string): Promise<string> {
  return new Promise((resolve, reject) => {
    const xhr = new XMLHttpRequest();
    xhr.onload = () => {
      const reader = new FileReader();
      reader.onload = () => {
        const result = reader.result as string;
        const commaIndex = result.indexOf(",");
        resolve(commaIndex >= 0 ? result.slice(commaIndex + 1) : result);
      };
      reader.onerror = () => reject(new Error("读取图片失败"));
      reader.readAsDataURL(xhr.response);
    };
    xhr.onerror = () => reject(new Error("读取图片失败"));
    xhr.responseType = "blob";
    xhr.open("GET", uri);
    xhr.send();
  });
}

async function compressImageForOcr(
  uri: string,
): Promise<{ base64: string; mimeType: string }> {
  const resized = await ImageManipulator.manipulateAsync(
    uri,
    [
      {
        resize: {
          width: OCR_MAX_EDGE,
        },
      },
    ],
    {
      compress: OCR_JPEG_QUALITY,
      format: ImageManipulator.SaveFormat.JPEG,
    },
  );

  const base64 = await uriToBase64(resized.uri);
  return { base64, mimeType: "image/jpeg" };
}

export async function takePhoto(): Promise<string | null> {
  const permission = await ImagePicker.requestCameraPermissionsAsync();
  if (!permission.granted) {
    throw new Error("需要相机权限");
  }

  const result = await ImagePicker.launchCameraAsync(OCR_IMAGE_PICKER);

  if (result.canceled || !result.assets.length) return null;
  return result.assets[0]!.uri;
}

export async function pickFromAlbum(): Promise<string | null> {
  const permission = await ImagePicker.requestMediaLibraryPermissionsAsync();
  if (!permission.granted) {
    throw new Error("需要相册权限");
  }

  const result = await ImagePicker.launchImageLibraryAsync(OCR_IMAGE_PICKER);

  if (result.canceled || !result.assets.length) return null;
  return result.assets[0]!.uri;
}

interface OcrRequestConfig {
  baseUrl: string;
  apiKey: string;
  model: string;
  /** Credits to deduct after a successful call. 0 for free / BYOK. */
  premiumCost: number;
}

/**
 * Resolve the effective OCR provider for this run:
 *  1. A complete BYOK custom config wins (user's own key — never charges).
 *  2. Otherwise the selected built-in model is used against the app's embedded
 *     key. Premium built-in models require enough credits up-front.
 */
async function resolveOcrRequest(): Promise<OcrRequestConfig> {
  const custom = await loadOcrProviderConfig();
  if (isCustomOcrConfigSet(custom)) {
    return {
      baseUrl: custom!.baseUrl.trim(),
      apiKey: custom!.apiKey.trim(),
      model: custom!.model.trim(),
      premiumCost: 0,
    };
  }

  if (requiresCustomOcrConfig()) {
    throw new Error("请先在设置中配置 OCR 服务（Web 版需自备 API Key）");
  }
  if (!config.zhipuApiKey.trim()) {
    throw new Error("请先在设置中配置 OCR 服务");
  }

  const selectedId = await loadSelectedModelId();
  const selected = getBuiltinModel(selectedId);
  if (selected.tier === "premium") {
    const balance = await ensureCreditsLoaded();
    if (balance < selected.creditCost) {
      throw new InsufficientCreditsError(selected.creditCost);
    }
    return {
      baseUrl: config.zhipuBaseUrl,
      apiKey: config.zhipuApiKey,
      model: selected.model,
      premiumCost: selected.creditCost,
    };
  }

  return {
    baseUrl: config.zhipuBaseUrl,
    apiKey: config.zhipuApiKey,
    model: selected.model,
    premiumCost: 0,
  };
}

export async function ocrWordsFromImage(
  imageUri: string,
  onProgress?: (phase: OcrProgressPhase) => void,
): Promise<{ words: string[]; rawText: string }> {
  onProgress?.("compressing");
  const { base64, mimeType } = await compressImageForOcr(imageUri);
  const dataUrl = `data:${mimeType};base64,${base64}`;

  onProgress?.("recognizing");

  const { baseUrl, apiKey, model, premiumCost } = await resolveOcrRequest();
  const endpoint = buildChatCompletionsUrl(baseUrl);

  let response: Response;
  try {
    response = await fetch(endpoint, {
      method: "POST",
      headers: {
        Authorization: `Bearer ${apiKey}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({
        model,
        temperature: 0.1,
        messages: [
          {
            role: "user",
            content: [
              {
                type: "image_url",
                image_url: { url: dataUrl },
              },
              {
                type: "text",
                text: [
                  "这是一张包含英文单词列表的图片。",
                  "请识别图中所有英文单词或词组。",
                  "如果单词旁边标注了词性和中文释义，请一并提取，每行格式：单词 | 词性 | 中文释义",
                  "如果图中没有词性或释义信息，只输出单词本身。",
                  "像 actor / actress 这样的斜杠词组应作为一整行输出，不要拆开。",
                  "不要用逗号连接、不要编号、不要输出其他标点或解释。",
                ].join(""),
              },
            ],
          },
        ],
      }),
    });
  } catch {
    throw new Error("网络请求失败，请检查网络后重试");
  }

  if (!response.ok) {
    // Read the error body BEFORE throwing: the old shape threw inside its
    // own try/catch, which swallowed the detailed message and always
    // surfaced the generic fallback to the user.
    const detail = await response.text().catch(() => "");
    throw new Error(detail ? `视觉识别失败: ${detail}` : "视觉识别服务异常");
  }

  // Charge credits only after a successful API response so failed/errored
  // calls don't consume the user's balance. OcrSection's runningRef
  // prevents a double-tap from starting two spends.
  if (premiumCost > 0) {
    await trySpendCredits(premiumCost);
  }

  const payload = (await response.json()) as {
    choices?: Array<{ message?: { content?: string } }>;
  };
  const rawText = payload.choices?.[0]?.message?.content?.trim() ?? "";
  const words = extractWordsFromOcrText(rawText);

  return { words, rawText };
}

/**
 * Verify a candidate OCR provider config by sending a minimal text-only
 * chat/completions request. Throws with a descriptive message on failure.
 * Used by the OCR settings panel before saving.
 */
export async function testOcrConfig(cfg: {
  baseUrl: string;
  apiKey: string;
  model: string;
}): Promise<void> {
  const endpoint = buildChatCompletionsUrl(cfg.baseUrl);
  let response: Response;
  try {
    response = await fetch(endpoint, {
      method: "POST",
      headers: {
        Authorization: `Bearer ${cfg.apiKey}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({
        model: cfg.model,
        temperature: 0,
        max_tokens: 1,
        messages: [{ role: "user", content: "hi" }],
      }),
    });
  } catch {
    throw new Error("网络请求失败，请检查 URL 与网络");
  }

  if (!response.ok) {
    let detail = "";
    try {
      const text = await response.text();
      try {
        const j = JSON.parse(text) as { error?: { message?: string } };
        detail = j.error?.message ?? text;
      } catch {
        detail = text;
      }
    } catch {
      // ignore
    }
    const hint = detail ? `: ${detail.slice(0, 160)}` : "";
    if (response.status === 401 || response.status === 403) {
      throw new Error(`认证失败（${response.status}）${hint}`);
    }
    if (response.status === 404) {
      throw new Error(`未找到接口（404），请检查 URL${hint}`);
    }
    throw new Error(`请求失败（${response.status}）${hint}`);
  }
}

/**
 * Real dictation phrases are almost never longer than this many space-separated
 * tokens (e.g. "ice cream", "look forward to", "actor / actress"). Longer runs
 * are treated as a failed one-line dump from the vision model.
 */
const MAX_PHRASE_TOKENS = 4;

/**
 * Strip list markers, wrapping quotes, and trailing punctuation from a token.
 */
function cleanToken(s: string): string {
  return s
    .replace(/^[\d.)\-•*、]+\s*/, "")
    .replace(/^["'`“”‘’]+|["'`“”‘’]+$/g, "")
    .replace(/[.。:：]+$/g, "")
    .trim();
}

const WORD_RE = /^[a-zA-Z][a-zA-Z'/\-\s]*$/;

/**
 * The leading English token run of `tokens` — the headword phrase. Empty
 * when the row does not begin with English, so a row that opens with
 * Chinese (or pure 音标) is not an English entry at all. A lone `/` keeps
 * the run going only while it is flanked by word tokens, so spaced slash
 * phrases (`actor / actress`) survive whole — the format the OCR prompt
 * asks for — while a trailing `/` or annotation tokens still end the run.
 */
function leadingEnglishRun(tokens: string[]): string[] {
  const run: string[] = [];
  for (let i = 0; i < tokens.length; i++) {
    const token = tokens[i];
    if (WORD_RE.test(token)) {
      run.push(token);
    } else if (
      token === "/" &&
      run.length > 0 &&
      i + 1 < tokens.length &&
      WORD_RE.test(tokens[i + 1])
    ) {
      run.push(token);
    } else {
      break;
    }
  }
  return run;
}

/**
 * English tokens that start a cleaned token run — the headword phrase.
 * Null when the run does not start with English, so a row that begins
 * with Chinese (or pure 音标) is not an English entry at all.
 */
function englishPhrase(tokenRun: string): string | null {
  const phrase = leadingEnglishRun(tokenRun.split(/\s+/).filter(Boolean)).slice(
    0,
    MAX_PHRASE_TOKENS,
  );
  return phrase.length > 0 ? phrase.join(" ") : null;
}

/**
 * Candidate words from one cleaned comma-part. Pure-English runs keep the
 * original behavior: the whole phrase up to MAX_PHRASE_TOKENS tokens,
 * longer dumps flattened into single tokens. Mixed runs — the word
 * followed by 音标/词性/中文 (the vision model echoing a textbook row
 * instead of the `word | pos | meaning` format) — yield the leading
 * English phrase; the trailing annotations are noise and never become
 * entries.
 */
function englishCandidates(candidate: string): string[] {
  const tokens = candidate.split(/\s+/).filter(Boolean);
  const leading = leadingEnglishRun(tokens);
  if (leading.length === 0) return [];
  if (leading.length === tokens.length) {
    if (leading.length <= MAX_PHRASE_TOKENS) return [candidate];
    // Over-long pure dump flattened to single tokens; lone "/" separators
    // are noise and never become entries.
    return tokens.filter((t) => WORD_RE.test(t));
  }
  return leading.length <= MAX_PHRASE_TOKENS
    ? [leading.join(" ")]
    : leading.filter((t) => WORD_RE.test(t));
}
/**
 * Vision models often ignore "one per line" and return comma- or space-separated
 * lists. This function normalizes the output into a clean word list.
 *
 * Supports enriched entries with `|`-delimited pos/meaning:
 *   `apple | n. | 苹果` — the leading English phrase of the word part is kept
 * (a 音标 run trailing the headword is dropped); the meta is preserved. Plain
 * entries (no `|`) are comma-split; each part yields only its leading English
 * phrase — the whole phrase (≤ MAX_PHRASE_TOKENS tokens), individual tokens
 * of an over-long dump, or the headword of a row that also carries
 * 音标/词性/中文. Chinese text never becomes an entry.
 */
export function extractWordsFromOcrText(rawText: string): string[] {
  const cleaned = rawText
    .replace(/```[\s\S]*?```/g, (block) =>
      block.replace(/^```\w*\n?/, "").replace(/\n?```$/, ""),
    )
    .replace(/\r\n?/g, "\n");

  // Split by newlines first to keep enriched entries intact
  const lines = cleaned
    .split(/\n/)
    .map((l) => l.trim())
    .filter((l) => l.length > 0);

  const seen = new Set<string>();
  const words: string[] = [];

  for (const line of lines) {
    const pipeIdx = line.indexOf("|");

    if (pipeIdx !== -1) {
      // Enriched entry: salvage the leading English phrase of the word
      // part (a 音标 run trailing the headword is dropped), keep the meta.
      const wordPart = englishPhrase(cleanToken(line.slice(0, pipeIdx)));
      if (!wordPart) continue;

      const key = wordPart.toLowerCase();
      if (seen.has(key)) continue;
      seen.add(key);

      const metaParts = line
        .slice(pipeIdx + 1)
        .split("|")
        .map((s) => s.trim())
        .filter((s) => s.length > 0);

      // Reassemble with consistent spacing
      words.push([wordPart, ...metaParts].join(" | "));
    } else {
      // Plain line: split by commas/semicolons (the vision model may
      // ignore one-per-line), then keep the headword of each part.
      const candidates = line
        .split(/[,，;；、]+/)
        .map((p) => cleanToken(p))
        .filter(Boolean)
        .flatMap(englishCandidates);

      for (const word of candidates) {
        const key = word.toLowerCase();
        if (seen.has(key)) continue;
        seen.add(key);
        words.push(word);
      }
    }
  }

  return words;
}

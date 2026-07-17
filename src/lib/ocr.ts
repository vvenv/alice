import * as ImageManipulator from "expo-image-manipulator";
import * as ImagePicker from "expo-image-picker";

import {
  buildChatCompletionsUrl,
  loadOcrProviderConfig,
  requiresCustomOcrConfig,
  resolveOcrConfig,
} from "./ocrConfig";

const OCR_MAX_EDGE = 1600;
const OCR_JPEG_QUALITY = 0.82;

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

  const result = await ImagePicker.launchCameraAsync({
    mediaTypes: ["images"],
    quality: 1,
  });

  if (result.canceled || !result.assets.length) return null;
  return result.assets[0]!.uri;
}

export async function pickFromAlbum(): Promise<string | null> {
  const permission = await ImagePicker.requestMediaLibraryPermissionsAsync();
  if (!permission.granted) {
    throw new Error("需要相册权限");
  }

  const result = await ImagePicker.launchImageLibraryAsync({
    mediaTypes: ["images"],
    quality: 1,
  });

  if (result.canceled || !result.assets.length) return null;
  return result.assets[0]!.uri;
}

export async function ocrWordsFromImage(
  imageUri: string,
  onProgress?: (phase: OcrProgressPhase) => void,
): Promise<{ words: string[]; rawText: string }> {
  onProgress?.("compressing");
  const { base64, mimeType } = await compressImageForOcr(imageUri);
  const dataUrl = `data:${mimeType};base64,${base64}`;

  onProgress?.("recognizing");

  const custom = await loadOcrProviderConfig();
  const resolved = resolveOcrConfig(custom);
  if (!resolved) {
    throw new Error(
      requiresCustomOcrConfig()
        ? "请先在设置中配置 OCR 服务（Web 版需自备 API Key）"
        : "请先在设置中配置 OCR 服务",
    );
  }
  const { baseUrl, apiKey, model } = resolved;
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
    try {
      const detail = await response.text();
      throw new Error(`视觉识别失败: ${detail}`);
    } catch {
      throw new Error("视觉识别服务异常");
    }
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
 * Vision models often ignore "one per line" and return comma- or space-separated
 * lists. This function normalizes the output into a clean word list.
 *
 * Supports enriched entries with `|`-delimited pos/meaning:
 *   `apple | n. | 苹果` — the word part is validated; the meta is preserved.
 * Plain entries (no `|`) use the original comma-splitting + token-flattening
 * logic.
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
      // Enriched entry: clean & validate the word part, preserve the meta
      const rawWord = line.slice(0, pipeIdx);
      const metaParts = line
        .slice(pipeIdx + 1)
        .split("|")
        .map((s) => s.trim())
        .filter((s) => s.length > 0);

      const wordPart = cleanToken(rawWord);
      if (!wordPart || !WORD_RE.test(wordPart)) continue;

      const key = wordPart.toLowerCase();
      if (seen.has(key)) continue;
      seen.add(key);

      // Reassemble with consistent spacing
      words.push([wordPart, ...metaParts].join(" | "));
    } else {
      // Plain word: split by commas/semicolons (vision model may ignore
      // one-per-line), then flatten overly long runs into individual tokens
      const candidates = line
        .split(/[,，;；、]+/)
        .map((p) => cleanToken(p))
        .filter(Boolean)
        .flatMap((candidate) => {
          const tokens = candidate.split(/\s+/).filter(Boolean);
          return tokens.length <= MAX_PHRASE_TOKENS ? [candidate] : tokens;
        });

      for (const word of candidates) {
        if (!WORD_RE.test(word)) continue;
        const key = word.toLowerCase();
        if (seen.has(key)) continue;
        seen.add(key);
        words.push(word);
      }
    }
  }

  return words;
}

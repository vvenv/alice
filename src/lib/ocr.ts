import * as ImageManipulator from "expo-image-manipulator";
import * as ImagePicker from "expo-image-picker";

import { config } from "./config";

const OCR_MAX_EDGE = 1600;
const OCR_JPEG_QUALITY = 0.82;
const OCR_URL = `${config.zhipuBaseUrl}/chat/completions`;

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

  let response: Response;
  try {
    response = await fetch(OCR_URL, {
      method: "POST",
      headers: {
        Authorization: `Bearer ${config.zhipuApiKey}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({
        model: config.visionModel,
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
                  "请识别图中所有英文单词或词组，每个单词单独占一行，只输出单词/词组本身。",
                  "像 actor / actress 这样的斜杠词组应作为一整行输出，不要拆开。",
                  "不要用逗号连接、不要编号、不要解释、不要其他标点。",
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
 * Real dictation phrases are almost never longer than this many space-separated
 * tokens (e.g. "ice cream", "look forward to", "actor / actress"). Longer runs
 * are treated as a failed one-line dump from the vision model.
 */
const MAX_PHRASE_TOKENS = 4;

/**
 * Vision models often ignore "one per line" and return comma- or space-separated
 * lists. Also strip list markers / trailing punctuation.
 */
export function extractWordsFromOcrText(rawText: string): string[] {
  const cleaned = rawText
    .replace(/```[\s\S]*?```/g, (block) =>
      block.replace(/^```\w*\n?/, "").replace(/\n?```$/, ""),
    )
    .replace(/\r\n?/g, "\n");

  const candidates = cleaned
    .split(/[\n,，;；、]+/)
    .map((part) =>
      part
        .replace(/^[\d.)\-•*、]+\s*/, "")
        .replace(/^["'`“”‘’]+|["'`“”‘’]+$/g, "")
        .replace(/[.。:：]+$/g, "")
        .trim(),
    )
    .filter((word) => word.length > 0)
    .flatMap((candidate) => {
      const tokens = candidate.split(/\s+/).filter(Boolean);
      return tokens.length <= MAX_PHRASE_TOKENS ? [candidate] : tokens;
    });

  const seen = new Set<string>();
  const words: string[] = [];
  for (const word of candidates) {
    if (!/^[a-zA-Z][a-zA-Z'/\-\s]*$/.test(word)) continue;
    const key = word.toLowerCase();
    if (seen.has(key)) continue;
    seen.add(key);
    words.push(word);
  }
  return words;
}

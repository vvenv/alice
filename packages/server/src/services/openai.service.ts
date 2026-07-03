import { config } from "../lib/config.js";

export class OpenAiApiError extends Error {
  constructor(
    message: string,
    readonly status: number,
  ) {
    super(message);
    this.name = "OpenAiApiError";
  }
}

function requireApiKey(): string {
  const key = config.openai.apiKey.trim();
  if (!key) {
    throw new OpenAiApiError("OPENAI_API_KEY 未配置", 503);
  }
  return key;
}

export async function synthesizeSpeech(options: {
  text: string;
  voice?: string;
  speed?: number;
}): Promise<{ buffer: Buffer; contentType: string }> {
  const apiKey = requireApiKey();
  const response = await fetch(`${config.openai.baseUrl}/audio/speech`, {
    method: "POST",
    headers: {
      Authorization: `Bearer ${apiKey}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify({
      model: config.openai.ttsModel,
      input: options.text,
      voice: options.voice ?? config.openai.ttsVoice,
      speed: options.speed ?? 0.9,
      volume: 1.0,
      response_format: "wav",
    }),
  });

  if (!response.ok) {
    const detail = await response.text();
    throw new OpenAiApiError(
      `智谱 TTS 调用失败: ${detail || response.statusText}`,
      response.status,
    );
  }

  const contentType =
    response.headers.get("content-type") ?? "audio/wav";
  const buffer = Buffer.from(await response.arrayBuffer());
  return { buffer, contentType };
}

export async function extractWordsFromImage(options: {
  imageBase64: string;
  mimeType: string;
}): Promise<{ words: string[]; rawText: string }> {
  const apiKey = requireApiKey();
  const dataUrl = `data:${options.mimeType};base64,${options.imageBase64}`;

  const response = await fetch(`${config.openai.baseUrl}/chat/completions`, {
    method: "POST",
    headers: {
      Authorization: `Bearer ${apiKey}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify({
      model: config.openai.visionModel,
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
                "请识别图中所有英文单词，每行一个，只输出单词本身。",
                "不要编号、不要解释、不要标点。",
              ].join(""),
            },
          ],
        },
      ],
    }),
  });

  if (!response.ok) {
    const detail = await response.text();
    throw new OpenAiApiError(
      `智谱视觉识别失败: ${detail || response.statusText}`,
      response.status,
    );
  }

  const payload = (await response.json()) as {
    choices?: Array<{ message?: { content?: string } }>;
  };
  const rawText = payload.choices?.[0]?.message?.content?.trim() ?? "";
  const words = rawText
    .split(/[\n\r,，\t]+/)
    .flatMap((part) => part.trim().split(/\s+/))
    .map((word) => word.replace(/^[\d.)\-•]+\s*/, "").trim())
    .filter((word) => /^[a-zA-Z][a-zA-Z'-]*$/.test(word));

  return { words, rawText };
}

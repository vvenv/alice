import AsyncStorage from "@react-native-async-storage/async-storage";
import { Platform } from "react-native";

import { config } from "./config";

const OCR_CONFIG_KEY = "alice_ocr_provider_config";

/** Web builds never embed a shared OCR key — users must bring their own. */
export function requiresCustomOcrConfig(): boolean {
  return Platform.OS === "web";
}

export interface OcrProviderConfig {
  baseUrl: string;
  apiKey: string;
  model: string;
}

export interface OcrProviderPreset {
  id: string;
  label: string;
  baseUrl: string;
  /** Suggested vision-capable model for the preset. */
  model: string;
  /** Short hint shown under the preset, e.g. where to get a key. */
  hint?: string;
}

/**
 * Mainstream OpenAI-compatible vision providers. All of them expose a
 * `/chat/completions` endpoint that accepts `image_url` content parts, so the
 * same request body works across them — only the base URL, key and model name
 * differ.
 */
export const OCR_PROVIDER_PRESETS: OcrProviderPreset[] = [
  {
    id: "zhipu",
    label: "智谱 GLM",
    baseUrl: "https://open.bigmodel.cn/api/paas/v4",
    model: "glm-4v-flash",
    hint: "open.bigmodel.cn",
  },
  {
    id: "openai",
    label: "OpenAI",
    baseUrl: "https://api.openai.com/v1",
    model: "gpt-4o-mini",
    hint: "platform.openai.com",
  },
  {
    id: "qwen",
    label: "通义千问 VL",
    baseUrl: "https://dashscope.aliyuncs.com/compatible-mode/v1",
    model: "qwen-vl-plus",
    hint: "dashscope.aliyuncs.com",
  },
  {
    id: "moonshot",
    label: "Kimi (Moonshot)",
    baseUrl: "https://api.moonshot.cn/v1",
    model: "moonshot-v1-8k-vision-preview",
    hint: "platform.moonshot.cn",
  },
  {
    id: "siliconflow",
    label: "硅基流动",
    baseUrl: "https://api.siliconflow.cn/v1",
    model: "Qwen/Qwen2-VL-7B-Instruct",
    hint: "siliconflow.cn",
  },
  {
    id: "openrouter",
    label: "OpenRouter",
    baseUrl: "https://openrouter.ai/api/v1",
    model: "google/gemini-flash-1.5",
    hint: "openrouter.ai",
  },
  {
    id: "ollama",
    label: "Ollama (本地)",
    baseUrl: "http://localhost:11434/v1",
    model: "llama3.2-vision",
    hint: "无需 KEY，需开启本地服务",
  },
  {
    id: "custom",
    label: "自定义",
    baseUrl: "",
    model: "",
  },
];

/** A config is usable only when all three fields are non-empty. */
export function isCustomOcrConfigSet(
  cfg: OcrProviderConfig | null | undefined,
): boolean {
  return Boolean(cfg && cfg.baseUrl.trim() && cfg.apiKey.trim() && cfg.model.trim());
}

let _cached: OcrProviderConfig | null = null;
let _loaded = false;

export async function loadOcrProviderConfig(): Promise<OcrProviderConfig | null> {
  try {
    const data = await AsyncStorage.getItem(OCR_CONFIG_KEY);
    if (!data) {
      _cached = null;
      _loaded = true;
      return null;
    }
    const parsed = JSON.parse(data) as Partial<OcrProviderConfig>;
    if (
      typeof parsed.baseUrl === "string" &&
      typeof parsed.apiKey === "string" &&
      typeof parsed.model === "string"
    ) {
      _cached = {
        baseUrl: parsed.baseUrl,
        apiKey: parsed.apiKey,
        model: parsed.model,
      };
    } else {
      _cached = null;
    }
    _loaded = true;
    return _cached;
  } catch {
    _cached = null;
    _loaded = true;
    return null;
  }
}

/** Sync accessor for the cached value; null until loadOcrProviderConfig() has run. */
export function getCachedOcrProviderConfig(): OcrProviderConfig | null {
  return _loaded ? _cached : null;
}

export async function saveOcrProviderConfig(
  cfg: OcrProviderConfig | null,
): Promise<void> {
  _cached = cfg;
  _loaded = true;
  try {
    if (cfg) {
      await AsyncStorage.setItem(OCR_CONFIG_KEY, JSON.stringify(cfg));
    } else {
      await AsyncStorage.removeItem(OCR_CONFIG_KEY);
    }
  } catch {
    // ignore — config is also kept in-memory for the running session
  }
}

/**
 * Resolve the effective OCR config: a complete custom config wins; otherwise
 * fall back to the bundled Zhipu config on native only. Web never uses a
 * built-in key (it would be public in the JS bundle).
 */
export function resolveOcrConfig(
  custom: OcrProviderConfig | null | undefined,
): { baseUrl: string; apiKey: string; model: string } | null {
  if (isCustomOcrConfigSet(custom)) {
    return {
      baseUrl: custom!.baseUrl.trim(),
      apiKey: custom!.apiKey.trim(),
      model: custom!.model.trim(),
    };
  }
  if (requiresCustomOcrConfig()) return null;
  if (!config.zhipuApiKey.trim()) return null;
  return {
    baseUrl: config.zhipuBaseUrl,
    apiKey: config.zhipuApiKey,
    model: config.visionModel,
  };
}

/** Whether OCR can run with the given custom config (or built-in on native). */
export function hasUsableOcrConfig(
  custom: OcrProviderConfig | null | undefined,
): boolean {
  return resolveOcrConfig(custom) !== null;
}

/** Whether the effective config is the user's custom one (not the built-in). */
export function isUsingCustomConfig(
  custom: OcrProviderConfig | null | undefined,
): boolean {
  return isCustomOcrConfigSet(custom);
}

/**
 * Build the `/chat/completions` URL from a base URL. Tolerates base URLs that
 * already end with the path so users can paste a full endpoint if they like.
 */
export function buildChatCompletionsUrl(baseUrl: string): string {
  const trimmed = baseUrl.trim().replace(/\/+$/, "");
  if (/\/chat\/completions$/.test(trimmed)) return trimmed;
  return `${trimmed}/chat/completions`;
}

import AsyncStorage from "@react-native-async-storage/async-storage";

/** Where dictation word audio comes from. */
export type TtsSource = "youdao" | "custom";

/**
 * Wire shape of the configured OpenAI-compatible TTS endpoint:
 * - `speech`: standard `POST {base}/audio/speech` returning binary audio
 *   (OpenAI TTS, 智谱 GLM-TTS, 硅基流动, …).
 * - `chat`: `POST {base}/chat/completions` with an `audio` option returning
 *   base64 audio inside `choices[0].message.audio.data` (小米 MiMo).
 */
export type TtsApiKind = "chat" | "speech";

export interface TtsProviderConfig {
  api: TtsApiKind;
  baseUrl: string;
  apiKey: string;
  model: string;
  /** Voice for English text; empty = provider default voice. */
  voiceEn: string;
  /** Voice for Chinese text; empty = provider default voice. */
  voiceZh: string;
  /** Response format for the `speech` wire shape (default "mp3"). */
  responseFormat?: string;
}

export interface TtsProviderPreset {
  id: string;
  label: string;
  api: TtsApiKind;
  baseUrl: string;
  model: string;
  voiceEn: string;
  voiceZh: string;
  responseFormat?: string;
  /** Short hint shown under the preset, e.g. where to get a key. */
  hint?: string;
}

/**
 * OpenAI-compatible TTS providers. Only MiMo is free at the moment; the rest
 * are pre-filled convenience presets whose fields stay editable.
 */
export const TTS_PROVIDER_PRESETS: TtsProviderPreset[] = [
  {
    id: "mimo",
    label: "小米 MiMo",
    api: "chat",
    baseUrl: "https://api.xiaomimimo.com/v1",
    model: "mimo-v2.5-tts",
    voiceEn: "Chloe",
    voiceZh: "冰糖",
    hint: "限时免费 · mimo.mi.com",
  },
  {
    id: "zhipu",
    label: "智谱 GLM",
    api: "speech",
    baseUrl: "https://open.bigmodel.cn/api/paas/v4",
    model: "glm-tts",
    voiceEn: "tongtong",
    voiceZh: "tongtong",
    responseFormat: "wav",
    hint: "open.bigmodel.cn",
  },
  {
    id: "siliconflow",
    label: "硅基流动",
    api: "speech",
    baseUrl: "https://api.siliconflow.cn/v1",
    model: "FunAudioLLM/CosyVoice2-0.5B",
    voiceEn: "FunAudioLLM/CosyVoice2-0.5B:alex",
    voiceZh: "FunAudioLLM/CosyVoice2-0.5B:anna",
    hint: "siliconflow.cn",
  },
  {
    id: "openai",
    label: "OpenAI",
    api: "speech",
    baseUrl: "https://api.openai.com/v1",
    model: "gpt-4o-mini-tts",
    voiceEn: "alloy",
    voiceZh: "alloy",
    hint: "需可访问 OpenAI 的网络",
  },
  {
    id: "custom",
    label: "自定义",
    api: "speech",
    baseUrl: "",
    model: "",
    voiceEn: "",
    voiceZh: "",
  },
];

const TTS_SOURCE_KEY = "alice_tts_source";
const TTS_CONFIG_KEY = "alice_tts_provider_config";

let _cachedSource: TtsSource = "youdao";
let _cachedConfig: TtsProviderConfig | null = null;
let _loaded = false;

export interface TtsSettings {
  source: TtsSource;
  config: TtsProviderConfig | null;
}

export async function loadTtsSettings(): Promise<TtsSettings> {
  try {
    const [source, raw] = await Promise.all([
      AsyncStorage.getItem(TTS_SOURCE_KEY),
      AsyncStorage.getItem(TTS_CONFIG_KEY),
    ]);
    _cachedSource = source === "custom" ? "custom" : "youdao";
    if (raw) {
      try {
        const parsed = JSON.parse(raw) as TtsProviderConfig;
        if (
          (parsed.api === "chat" || parsed.api === "speech") &&
          typeof parsed.baseUrl === "string" &&
          typeof parsed.apiKey === "string" &&
          typeof parsed.model === "string"
        ) {
          _cachedConfig = {
            api: parsed.api,
            baseUrl: parsed.baseUrl,
            apiKey: parsed.apiKey,
            model: parsed.model,
            voiceEn: parsed.voiceEn ?? "",
            voiceZh: parsed.voiceZh ?? "",
            responseFormat: parsed.responseFormat,
          };
        }
      } catch {}
    } else {
      _cachedConfig = null;
    }
  } catch {}
  _loaded = true;
  return { source: _cachedSource, config: _cachedConfig };
}


/** Sync accessor for the selected source; "youdao" until load has run. */
export function getCachedTtsSource(): TtsSource {
  return _loaded ? _cachedSource : "youdao";
}

/** Sync accessor for the provider config; null until load has run. */
export function getCachedTtsProviderConfig(): TtsProviderConfig | null {
  return _loaded ? _cachedConfig : null;
}

/** A config is usable only when the endpoint, key and model are non-empty. */
export function isTtsProviderConfigSet(
  cfg: TtsProviderConfig | null | undefined,
): cfg is TtsProviderConfig {
  return Boolean(
    cfg &&
      (cfg.api === "chat" || cfg.api === "speech") &&
      cfg.baseUrl.trim() &&
      cfg.apiKey.trim() &&
      cfg.model.trim(),
  );
}

export async function saveTtsSource(source: TtsSource): Promise<void> {
  _cachedSource = source;
  _loaded = true;
  try {
    await AsyncStorage.setItem(TTS_SOURCE_KEY, source);
  } catch {}
}

export async function saveTtsProviderConfig(
  cfg: TtsProviderConfig | null,
): Promise<void> {
  _cachedConfig = cfg;
  _loaded = true;
  try {
    if (cfg) {
      await AsyncStorage.setItem(TTS_CONFIG_KEY, JSON.stringify(cfg));
    } else {
      await AsyncStorage.removeItem(TTS_CONFIG_KEY);
    }
  } catch {}
}

/**
 * Build the `/audio/speech` URL from a base URL. Tolerates base URLs that
 * already end with the path so users can paste a full endpoint if they like.
 */
export function buildSpeechUrl(baseUrl: string): string {
  const trimmed = baseUrl.trim().replace(/\/+$/, "");
  if (/\/audio\/speech$/.test(trimmed)) return trimmed;
  return `${trimmed}/audio/speech`;
}

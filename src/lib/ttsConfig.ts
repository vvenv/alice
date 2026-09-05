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
let _inflight: Promise<TtsSettings> | null = null;
/** Bumped by saves so an in-flight disk read cannot clobber them. */
let _saveGen = 0;

export interface TtsSettings {
  source: TtsSource;
  config: TtsProviderConfig | null;
}

function parseStoredConfig(raw: string): TtsProviderConfig | null {
  try {
    const parsed = JSON.parse(raw) as TtsProviderConfig;
    if (
      (parsed.api === "chat" || parsed.api === "speech") &&
      typeof parsed.baseUrl === "string" &&
      typeof parsed.apiKey === "string" &&
      typeof parsed.model === "string"
    ) {
      return {
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
  return null;
}

async function readTtsSettingsFromStorage(): Promise<TtsSettings> {
  const gen = _saveGen;
  let source: TtsSource = "youdao";
  let config: TtsProviderConfig | null = null;
  try {
    const [storedSource, raw] = await Promise.all([
      AsyncStorage.getItem(TTS_SOURCE_KEY),
      AsyncStorage.getItem(TTS_CONFIG_KEY),
    ]);
    source = storedSource === "custom" ? "custom" : "youdao";
    config = raw ? parseStoredConfig(raw) : null;
  } catch {}
  if (gen === _saveGen) {
    _cachedSource = source;
    _cachedConfig = config;
    _loaded = true;
  }
  return { source: _cachedSource, config: _cachedConfig };
}

export function loadTtsSettings(): Promise<TtsSettings> {
  if (_inflight) return _inflight;
  _inflight = readTtsSettingsFromStorage().finally(() => {
    _inflight = null;
  });
  return _inflight;
}

/** Resolve after the first disk read; later calls are sync-cheap. */
export function ensureTtsSettingsLoaded(): Promise<TtsSettings> {
  if (_loaded) return Promise.resolve({ source: _cachedSource, config: _cachedConfig });
  return loadTtsSettings();
}

/** Sync accessor; "youdao" until `ensureTtsSettingsLoaded` / `loadTtsSettings` finishes. */
export function getCachedTtsSource(): TtsSource {
  return _loaded ? _cachedSource : "youdao";
}

/** Sync accessor; null until the first load finishes. */
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
  _saveGen += 1;
  _cachedSource = source;
  _loaded = true;
  try {
    await AsyncStorage.setItem(TTS_SOURCE_KEY, source);
  } catch {}
}

export async function saveTtsProviderConfig(
  cfg: TtsProviderConfig | null,
): Promise<void> {
  _saveGen += 1;
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

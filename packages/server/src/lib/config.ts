/**
 * 服务器配置 — 从 monorepo 根目录加载 .env
 */
import path from "path";
import { fileURLToPath } from "url";

import { config as dotenvConfig } from "dotenv";

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const monorepoRoot = path.resolve(__dirname, "../../../..");

dotenvConfig({ path: path.resolve(monorepoRoot, ".env") });
dotenvConfig({
  path: path.resolve(monorepoRoot, process.env.ALICE_ENV_FILE ?? ".env.local"),
  override: true,
});

function strEnv(name: string, fallback: string): string {
  return process.env[name] ?? fallback;
}

function intEnv(name: string, fallback: number): number {
  const value = Number(process.env[name]);
  return Number.isFinite(value) ? value : fallback;
}

export const config = {
  server: {
    port: intEnv("PORT", 3600),
    host: strEnv("HOST", "0.0.0.0"),
    logLevel: strEnv("LOG_LEVEL", "info"),
  },
  /** 四位使用码，保护 /api 接口。 */
  accessCode: strEnv("ACCESS_CODE", "1024"),
  openai: {
    apiKey: strEnv("OPENAI_API_KEY", ""),
    baseUrl: strEnv("OPENAI_BASE_URL", "https://open.bigmodel.cn/api/paas/v4"),
    ttsModel: strEnv("OPENAI_TTS_MODEL", "glm-tts"),
    // Cloned from Pronunciation_Listen_and_circle.mp3 (account-bound).
    ttsVoice: strEnv(
      "OPENAI_TTS_VOICE",
      "6f62ac26-895b-512e-990f-7a0bbf06e75e",
    ),
    visionModel: strEnv("OPENAI_VISION_MODEL", "glm-4v-flash"),
  },
} as const;

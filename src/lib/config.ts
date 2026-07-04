import Constants from "expo-constants";

interface AppConfig {
  zhipuApiKey: string;
  zhipuBaseUrl: string;
  ttsModel: string;
  ttsVoice: string;
  visionModel: string;
  accessCode: string;
}

function extraString(key: string, fallback: string): string {
  const val = (Constants.expoConfig?.extra as Record<string, unknown>)?.[key];
  return typeof val === "string" && val.length > 0 ? val : fallback;
}

export const config: AppConfig = {
  zhipuApiKey: extraString("zhipuApiKey", ""),
  zhipuBaseUrl: extraString("zhipuBaseUrl", "https://open.bigmodel.cn/api/paas/v4"),
  ttsModel: extraString("ttsModel", "glm-tts"),
  ttsVoice: extraString(
    "ttsVoice",
    "6f62ac26-895b-512e-990f-7a0bbf06e75e",
  ),
  visionModel: extraString("visionModel", "glm-4v-flash"),
  accessCode: extraString("accessCode", "1024"),
};

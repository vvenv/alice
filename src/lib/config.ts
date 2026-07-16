import Constants from "expo-constants";

interface AppConfig {
  zhipuApiKey: string;
  zhipuBaseUrl: string;
  visionModel: string;
  /** Secret key for local HMAC-SHA256 unlock code verification. */
  hmacSecret: string;
  /** WeChat ID shown to users for payment. */
  wechatId: string;
}

function extraString(key: string, fallback: string): string {
  const val = (Constants.expoConfig?.extra as Record<string, unknown>)?.[key];
  return typeof val === "string" && val.length > 0 ? val : fallback;
}

export const config: AppConfig = {
  zhipuApiKey: extraString("zhipuApiKey", ""),
  zhipuBaseUrl: extraString("zhipuBaseUrl", "https://open.bigmodel.cn/api/paas/v4"),
  visionModel: extraString("visionModel", "glm-4v-flash"),
  hmacSecret: extraString("hmacSecret", ""),
  wechatId: extraString("wechatId", "vvenvw"),
};

export const SITE_URL = "https://alice.wenfu.dev";
export const SITE_NAME = "Alice 听写";
export const SITE_TAGLINE = "拍照即听写";
export const SITE_TITLE = `${SITE_NAME} — ${SITE_TAGLINE}`;
export const SITE_DESCRIPTION =
  "Alice 听写 — 拍照即听写。拍照、粘贴或分享成词表，Edge 朗读，听写中可调语速与重听。内置 290 套中考高考与教材词库，数据保存在本机。";
export const SITE_KEYWORDS = [
  "Alice听写",
  "英语听写",
  "单词听写",
  "拍照识别单词",
  "英语学习App",
  "错词本",
  "教材词库",
  "中考英语单词",
  "高考英语单词",
].join(",");
export const GITHUB_URL = "https://github.com/vvenv/alice";
export const APP_VERSION = "0.8.0";
export const APK_URL =
  "https://file.wenfu.dev/alice-0.8.0-20261012-2221.apk";
/** App screenshots on Cloudflare R2 (`pnpm screenshots:upload`). */
export const SCREENSHOTS_BASE = "https://file.wenfu.dev/screenshots";
export const SCREENSHOTS = {
  home: `${SCREENSHOTS_BASE}/home.png`,
  library: `${SCREENSHOTS_BASE}/library.png`,
  dictation: `${SCREENSHOTS_BASE}/dictation.png`,
  finish: `${SCREENSHOTS_BASE}/finish.png`,
} as const;
/** Flutter Web build, hosted under the marketing site. */
export const WEB_APP_URL = `${SITE_URL}/app/`;
export const OG_IMAGE_URL = `${SITE_URL}/og.png`;

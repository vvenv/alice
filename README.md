# Alice 听写

英文单词听写应用，基于 Expo (React Native)，支持 iOS / Android / Web。

## 功能

- 粘贴英文单词列表 / 拍照 OCR 识别
- 可调间隔、自动播放下一个
- 显示 / 隐藏当前单词
- 标记错词，本地持久化
- 导出错词到剪贴板
- 亮色 / 暗色主题

## 技术栈

- **Expo** — React Native 跨平台框架
- **系统 en-US TTS** — 英文单词发音（`expo-speech`）
- **智谱 GLM-4V** — 视觉 OCR 识别

## 快速开始

```bash
pnpm install
pnpm start          # Expo dev server
pnpm web            # Web 模式
pnpm ios            # iOS 模拟器
pnpm android        # Android 模拟器
```

## 配置

编辑 `app.json` 的 `extra` 字段：

| 字段 | 说明 | 默认值 |
|------|------|--------|
| `zhipuApiKey` | 智谱 API Key（OCR） | 空（必填） |
| `zhipuBaseUrl` | 智谱 API 地址 | `https://open.bigmodel.cn/api/paas/v4` |
| `visionModel` | OCR 模型 | `glm-4v-flash` |
| `accessCode` | 使用码 | `1024` |

## 移动端发版（EAS）

首次发版前在本地完成 EAS 初始化，并将 Access Token 配置到 GitHub Secrets：

```bash
pnpm exec eas login
pnpm exec eas init          # 写入 app.json 的 expo.extra.eas.projectId
```

在 GitHub → Settings → Secrets → Actions 添加 `EXPO_TOKEN`（Expo 账号 → Access Tokens）。

### GitHub Actions 手动发版

仓库 **Actions → Release → Run workflow**，可选择：

| 参数 | 说明 |
|------|------|
| platform | `all` / `android` / `ios` |
| profile | `preview`（内测 APK）/ `production`（商店包） |
| submit | 是否自动提交应用商店（仅 production） |

推送 `v*` 标签（如 `v0.1.0`）会自动触发 production 全平台构建。

### 本地发版

```bash
pnpm build:android -- --profile preview
pnpm build:ios -- --profile production
pnpm build:mobile -- --profile preview
```

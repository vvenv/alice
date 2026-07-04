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
- **智谱 GLM-TTS** — TTS 语音合成
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
| `zhipuApiKey` | 智谱 API Key | 空（必填） |
| `zhipuBaseUrl` | 智谱 API 地址 | `https://open.bigmodel.cn/api/paas/v4` |
| `ttsModel` | TTS 模型 | `glm-tts` |
| `ttsVoice` | 发音人 | 教材考试发音 |
| `visionModel` | OCR 模型 | `glm-4v-flash` |
| `accessCode` | 使用码 | `1024` |

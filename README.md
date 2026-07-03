# 极简听写 (Alice)

英文单词听写 Web 应用，采用 **pnpm monorepo + shell scripts** 架构（对齐 [regora](https://github.com/) 同构仓库）。

## 功能

- 粘贴 / 拍照识别英文单词列表
- 可调间隔、自动播放下一个
- 显示 / 隐藏当前单词
- 标记错词，本地持久化（localStorage）
- 导出错词到剪贴板

## 技术栈

| 模块 | 方案 |
|------|------|
| 前端 | React 19 + Vite (`packages/client`) |
| 后端 | Fastify (`packages/server`) — 代理智谱 API，保护 Key |
| 共享类型 | `@alice/shared` |
| TTS | **智谱 GLM-TTS**（服务端 `/api/tts/speech`） |
| OCR | **智谱 GLM-4V** 视觉识别（`/api/ocr/words`） |
| 降级 | 浏览器 Web Speech API（TTS Key 未配置时） |
| 部署 | 蓝绿发布脚本（`scripts/`） |

## 项目结构

```
alice/
├── packages/
│   ├── client/     # 听写 UI
│   ├── server/     # API 服务（智谱 TTS / OCR）
│   └── shared/     # 共享类型
├── scripts/        # release / deploy / bootstrap（regora 同构）
├── package.json
└── pnpm-workspace.yaml
```

## 快速开始

```bash
# 安装依赖
pnpm install

# 配置智谱 API Key
cp .env.example .env.local
# 编辑 .env.local，填入 OPENAI_API_KEY

# 开发（client :5176，server :3600）
pnpm dev
```

浏览器访问 http://localhost:5176

## 环境变量

| 变量 | 说明 |
|------|------|
| `OPENAI_API_KEY` | 智谱开放平台 API Key |
| `OPENAI_TTS_MODEL` | TTS 模型，默认 `glm-tts` |
| `OPENAI_TTS_VOICE` | 发音人，默认 `female` |
| `OPENAI_VISION_MODEL` | 视觉 OCR 模型，默认 `glm-4v-flash` |
| `PORT` | 服务端口，默认 `3600` |

部署变量见 `scripts/env.production.example`。

## 发版与部署

```bash
# 本地发版 + SSH 部署
pnpm release patch -- --deploy-local

# 仅构建部署（不 bump 版本）
pnpm deploy
```

详见 `scripts/` 与同构仓库 regora / moms 的部署文档。

## 智谱模型说明

- **GLM-TTS**：英文单词发音，通过服务端代理调用，避免在前端暴露 API Key
- **GLM-4V-Flash**：拍照识别单词列表，替代纯前端 Tesseract
- 后续可扩展 **GLM-Realtime** 实时语音交互、**CogVideoX** 等音视频能力

API 文档：https://docs.bigmodel.cn

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
| `hmacSecret` | 生成/验证解锁码的密钥 | `alice-dictation-default-secret` |
| `wechatId` | 付费解锁展示的微信号 | `your_wechat_id` |

## OCR 付费解锁

OCR 拍照识别功能为付费功能，付费流程：

1. **付费墙**：用户看到功能介绍 + 微信号，添加微信完成支付
2. **输入解锁码**：支付完成后，输入 4 位字母/数字解锁码即可解锁
3. **持久化**：解锁状态保存在本地，下次启动无需重复输入

解锁码通过 HMAC-SHA256 本地校验，无需远程 API。

### 生成解锁码

你本地运行脚本即可生成解锁码，每个用户可以领取不同的码：

```bash
# 生成 1 个解锁码
pnpm generate-code

# 生成 5 个解锁码
pnpm generate-code --count 5

# 使用自定义密钥（需与 app.json 中的 hmacSecret 一致）
pnpm generate-code --secret "你的密钥" --count 3
```

输出示例：

```
Secret: alice-dictation-default-secret
Prefix: 00
Count:  3

  1. FUFW
     HMAC: 009909f8c5d6483e... (starts with "00" ✓)

  2. GLA8
     HMAC: 00c265428c950c59... (starts with "00" ✓)

  3. HNRX
     HMAC: 00a68c057b1a850a... (starts with "00" ✓)

All codes: FUFW, GLA8, HNRX
```

> **注意**：生成的解锁码必须与 app 内置的 `hmacSecret` 匹配。如果修改了 `app.json` 中的密钥，需要用新密钥重新生成解锁码。

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

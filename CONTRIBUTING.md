# 贡献指南

感谢你有兴趣为 Alice 听写做贡献！

## 开发环境

```bash
git clone https://github.com/vvenv/alice.git
cd alice
pnpm install
cp .env.example .env   # 按需填入自己的密钥（OCR 功能需要智谱 API Key）
pnpm start             # Expo dev server
```

网站（`website/` 子包）：

```bash
pnpm --filter website dev
```

## 提交前检查

```bash
pnpm lint   # TypeScript 类型检查
```

## 提交规范

- 提交信息使用 [Conventional Commits](https://www.conventionalcommits.org/) 风格：`feat: ...`、`fix: ...`、`chore: ...` 等
- 一个 PR 只做一件事，附上必要的截图（UI 改动）
- Bug 修复请尽量附带复现步骤

## 安全

**不要**在代码、提交历史或 Issue 中包含任何密钥（API Key、HMAC 密钥、服务器地址等）。所有敏感配置都应放在 gitignored 的 `.env` 中（见 `.env.example`）。如发现安全问题，请通过 Issue 或私下联系维护者。

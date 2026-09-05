# 贡献指南

感谢你有兴趣为 Alice 听写做贡献！

## 开发环境

应用是 Flutter，仓库根目录就是 Flutter 工程。

```bash
git clone https://github.com/vvenv/alice.git
cd alice
cp .env.example .env   # 按需填入自己的密钥（OCR 功能需要智谱 API Key）

flutter pub get
flutter run            # 连着设备或模拟器；-d chrome 跑 Web
```

平台目录（`android/`、`ios/`、`web/`）是 `flutter create` 生成的，重新生成用
`bash scripts/bootstrap.sh` —— 它会把包名、权限、应用名再写回去，别直接跑
`flutter create`。

网站（`website/` 子包，React + Vite）与仓库脚本走 pnpm：

```bash
pnpm install
pnpm --filter website dev
```

## 提交前检查

```bash
flutter analyze              # 应用：静态分析
flutter test                 # 应用：单元 + widget 测试
pnpm lint                    # scripts/ 的 TypeScript 类型检查
pnpm --filter website check  # 网站类型检查
```

改过 `data/` 下的词表之后，先校验格式，再重新生成资源，两者一起提交
（CI 会卡住格式错误和不一致的提交）：

```bash
pnpm data:check
pnpm data:gen
```

## 提交规范

- 提交信息使用 [Conventional Commits](https://www.conventionalcommits.org/) 风格：`feat: ...`、`fix: ...`、`chore: ...` 等
- 一个 PR 只做一件事，附上必要的截图（UI 改动）
- Bug 修复请尽量附带复现步骤

## 安全

**不要**在代码、提交历史或 Issue 中包含任何密钥（API Key、服务器地址等）。所有敏感配置都应放在 gitignored 的 `.env` 中（见 `.env.example`）。如发现安全问题，请通过 Issue 或私下联系维护者。

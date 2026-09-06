# Alice 听写 · 官网

<https://alice.edao.plus> —— 产品介绍与 APK 下载页。Vite + React 19 + Tailwind CSS v4
的静态站，构建时用 Playwright 预渲染成纯 HTML（`scripts/prerender.mjs`），
部署在 Cloudflare Pages。

```bash
pnpm install                    # 在仓库根目录跑
pnpm --filter website dev       # 本地开发
pnpm --filter website check     # 类型检查（CI 跑这条）
pnpm --filter website lint      # ESLint
pnpm --filter website build     # 预渲染产物到 dist/
```

发版见仓库根目录的 `scripts/release-website.sh`。

## 约定

- **设计令牌全在 `src/index.css`**。Tailwind v4 用 `@theme` / `@utility` /
  `@custom-variant` 声明颜色、字体、动画与 `container`，没有 `tailwind.config.js`。
- **路径别名 `@/`** 指向 `src/`，由 `vite-tsconfig-paths` 从 `tsconfig.json` 读取。
- **暗色模式走 `.dark` class**（`@custom-variant dark`），不是 `prefers-color-scheme`。
- 站点文案、下载链接等集中在 `src/data/site.ts`；FAQ 在 `src/data/faq.ts`，
  同时喂给页面和 `JsonLd` 的结构化数据。

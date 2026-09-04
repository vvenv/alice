// 把 RN 版的 src/lib/library.ts（16k 行、代码即数据）导出成
// flutter_app/assets/data/library.json。
//
// library.ts 本身是 scripts/generate-library.ts 从 data/ 目录生成的，
// 所以这里只做「TS 模块 → JSON 资源」这一步转换，不重新解析原始词表。
//
// 用法：node scripts/export-library-json.mjs

import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

const root = path.dirname(path.dirname(fileURLToPath(import.meta.url)));
const src = path.join(root, "src/lib/library.ts");
const dest = path.join(root, "flutter_app/assets/data/library.json");

const source = fs.readFileSync(src, "utf8");
const marker = "export const LIBRARY_ITEMS: LibraryItem[] =";
const start = source.indexOf(marker);
if (start < 0) {
  throw new Error(`在 ${src} 里找不到 LIBRARY_ITEMS 定义`);
}

// 数组字面量里只有字符串和模板字符串，直接求值即可。
let body = source.slice(start + marker.length).trim();
if (body.endsWith(";")) body = body.slice(0, -1);
const items = eval(body);

if (!Array.isArray(items) || items.length === 0) {
  throw new Error("解析出的词库为空");
}

fs.mkdirSync(path.dirname(dest), { recursive: true });
fs.writeFileSync(dest, JSON.stringify(items));

console.log(`已导出 ${items.length} 条词表 → ${path.relative(root, dest)}`);

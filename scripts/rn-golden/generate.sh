#!/usr/bin/env bash
# 用 RN 版的 TypeScript 生成等价性测试的黄金语料。
# 详见同目录 README.md。
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
OUT="$ROOT/flutter_app/test/golden/rn_golden.json"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

cd "$ROOT"

# dictation.ts / dictionary.ts 可以直接编译；ocr.ts 顶层 import 了 expo 模块，
# 只取 MAX_PHRASE_TOKENS 之后的纯函数部分。
cp src/lib/dictation.ts src/lib/dictionary.ts src/lib/ecdict-meta.json "$WORK/"
sed -n '/^const MAX_PHRASE_TOKENS/,$p' src/lib/ocr.ts > "$WORK/ocrwords.ts"
cp scripts/rn-golden/gen.ts "$WORK/"

# typeRoots 指回仓库的 node_modules —— 编译发生在临时目录里，
# 否则 tsc 找不到 @types/node。
cat > "$WORK/tsconfig.json" <<JSON
{
  "compilerOptions": {
    "target": "ES2022",
    "module": "CommonJS",
    "moduleResolution": "node",
    "ignoreDeprecations": "6.0",
    "resolveJsonModule": true,
    "esModuleInterop": true,
    "strict": false,
    "skipLibCheck": true,
    "typeRoots": ["$ROOT/node_modules/@types"],
    "types": ["node"],
    "outDir": "out"
  },
  "include": ["dictation.ts", "dictionary.ts", "ocrwords.ts", "gen.ts"]
}
JSON

(cd "$WORK" && "$ROOT/node_modules/.bin/tsc" -p tsconfig.json)

mkdir -p "$(dirname "$OUT")"
node "$WORK/out/gen.js" "$OUT"
echo "→ $OUT"

#!/usr/bin/env bash
# 重新生成 test/golden/rn_golden.json —— 等价性测试的黄金语料。
#
# 语料不是手写的期望值，是**真的跑 Expo 版的 TypeScript** 得到的输出。
# Expo 实现已经从工作区删掉（见 docs/migration-from-expo.md），所以这个脚本
# 从 git ref 里取源码，默认 main：
#
#   bash scripts/rn-golden/generate.sh            # 对齐 main
#   bash scripts/rn-golden/generate.sh rn-final   # 对齐迁移那一刻的实现
#
# 覆盖 src/lib/dictation.ts、dictionary.ts 的全部导出函数，以及 ocr.ts 里的
# extractWordsFromOcrText（ocr.ts 顶层 import 了 expo 模块，没法直接在 node 里
# 跑，只切出 MAX_PHRASE_TOKENS 之后那段纯函数）。
#
# gen.ts 由下面这份临时 tsconfig 单独编译（CommonJS + 相对导入），不参与仓库的
# `pnpm lint`（tsconfig.scripts.json 里排除了这个目录）。
#
# ⚠️ main 上没有 Expo 代码之后，这个脚本就跑不动了。到那时语料变成一份冻结的
#    行为基线：仍然拦得住 Dart 侧漂移，但不能再重新生成 —— 把这个目录删掉即可。
set -euo pipefail

REF="${1:-main}"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
OUT="$ROOT/test/golden/rn_golden.json"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

cd "$ROOT"

git rev-parse --verify "$REF" >/dev/null 2>&1 ||
  { echo "ERROR: 找不到 ref $REF" >&2; exit 1; }
git cat-file -e "$REF:src/lib/dictation.ts" 2>/dev/null ||
  { echo "ERROR: $REF 上没有 src/lib/dictation.ts —— Expo 实现已经不在那个 ref 上了" >&2; exit 1; }

git show "$REF:src/lib/dictation.ts"     > "$WORK/dictation.ts"
git show "$REF:src/lib/dictionary.ts"    > "$WORK/dictionary.ts"
git show "$REF:src/lib/ecdict-meta.json" > "$WORK/ecdict-meta.json"
git show "$REF:src/lib/ocr.ts" | sed -n '/^const MAX_PHRASE_TOKENS/,$p' > "$WORK/ocrwords.ts"
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
echo "→ $OUT （对齐 ${REF}）"

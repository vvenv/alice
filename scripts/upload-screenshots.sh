#!/usr/bin/env bash
# Upload App screenshots from docs/screenshots/ to Cloudflare R2 and point the
# marketing site at the public URLs.
#
# Objects land at content-hashed keys:
#   $R2_PUBLIC_BASE/screenshots/{home,library,dictation,finish}.<sha8>.png
#
# 文件名带内容哈希、缓存一年 immutable：截图一变 URL 就变，浏览器和 CF 边缘
# 不会拿着旧图不放，也不用 purge。以前是覆盖同名对象 + max-age=1 天，
# 换了截图官网最多要一天才看得到。旧对象留在 R2 上，缓存着旧 HTML 的访客
# 也不会裂图。
#
# Source of truth for the PNGs stays in docs/screenshots/ (README embeds those).
# website/public/screenshots/ is not used — the site loads from R2.
#
# Usage:
#   pnpm screenshots:upload
#   bash scripts/upload-screenshots.sh
#   ./do.sh screenshots
#   bash scripts/upload-screenshots.sh --check   # 只检查 site.ts 是否指向当前截图，
#                                                # 不上传、不需要 R2 凭据；过期则退出码 1
#   bash scripts/upload-screenshots.sh --ensure  # 发版脚本构建官网前调用：已是最新就
#                                                # 直接过；过期时终端里问要不要上传，
#                                                # 非交互则报错退出
#
# Prereqs (same R2 block as release.sh, see .env.example):
#   R2_BUCKET / R2_PUBLIC_BASE / CLOUDFLARE_ACCOUNT_ID / CLOUDFLARE_API_TOKEN

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

error() { echo "ERROR: $*" >&2; exit 1; }

MODE=upload
while [ $# -gt 0 ]; do
  case "$1" in
    --check) MODE=check ;;
    --ensure) MODE=ensure ;;
    -h|--help) sed -n '2,27p' "$0"; exit 0 ;;
    *) error "未知选项: $1" ;;
  esac
  shift
done

SHOTS=(home library dictation finish)
SRC_DIR="$ROOT/docs/screenshots"
SITE_TS="$ROOT/website/src/data/site.ts"
PUBLIC_SHOTS="$ROOT/website/public/screenshots"

for name in "${SHOTS[@]}"; do
  [ -f "$SRC_DIR/$name.png" ] || error "缺少截图: $SRC_DIR/$name.png"
done

# If the constant is missing, fail loudly so we don't silently ship local paths.
grep -q 'export const SCREENSHOTS_BASE' "$SITE_TS" \
  || error "site.ts 缺少 SCREENSHOTS_BASE — 先加常量再跑本脚本"

# 截图在 R2 上的文件名：内容哈希前 8 位。
hashed_name() {
  echo "$1.$(shasum -a 256 "$SRC_DIR/$1.png" | cut -c1-8).png"
}

if [ "$MODE" != upload ]; then
  stale=()
  for name in "${SHOTS[@]}"; do
    grep -q "/$(hashed_name "$name")\`" "$SITE_TS" || stale+=("$name")
  done
  if [ ${#stale[@]} -eq 0 ]; then
    echo "✓ site.ts 已指向当前截图"
    exit 0
  fi
  echo "截图未上传或已过期: ${stale[*]}" >&2
  [ "$MODE" = check ] && exit 1

  # --ensure：换了 docs/screenshots/ 却没上传就构建，官网会带着旧图上线。
  [ -t 0 ] || error "截图未上传 — 先跑 ./do.sh screenshots（或 pnpm screenshots:upload）"
  read -r -p "截图有更新，先上传？ [Y/n]: " ans </dev/tty || true
  case "${ans:-y}" in
    [Yy]|[Yy][Ee][Ss]) ;;
    *)
      echo "⚠ 跳过上传：官网将继续使用 site.ts 里的旧截图"
      exit 0
      ;;
  esac
fi

if [ -f "$ROOT/.env" ]; then
  set -a
  # shellcheck disable=SC1091
  source "$ROOT/.env"
  set +a
fi

R2_BUCKET="${R2_BUCKET:?R2_BUCKET not set — add it to .env (see .env.example)}"
R2_PUBLIC_BASE="${R2_PUBLIC_BASE:?R2_PUBLIC_BASE not set — add it to .env (see .env.example)}"
R2_PUBLIC_BASE="${R2_PUBLIC_BASE%/}"
: "${CLOUDFLARE_ACCOUNT_ID:?CLOUDFLARE_ACCOUNT_ID not set — add it to .env (see .env.example)}"
: "${CLOUDFLARE_API_TOKEN:?CLOUDFLARE_API_TOKEN not set — add it to .env (see .env.example)}"

echo "▶ Uploading screenshots → $R2_BUCKET/screenshots/"
for name in "${SHOTS[@]}"; do
  file="$(hashed_name "$name")"
  key="screenshots/$file"
  pnpm exec wrangler r2 object put "$R2_BUCKET/$key" \
    --file "$SRC_DIR/$name.png" \
    --remote \
    --content-type "image/png" \
    --cache-control "public, max-age=31536000, immutable"
  echo "  ✓ $R2_PUBLIC_BASE/$key"

  # site.ts 里那一行：home: `${SCREENSHOTS_BASE}/home[.xxxxxxxx].png`,
  NAME="$name" FILE="$file" perl -0777 -pi -e \
    's{(\b\Q$ENV{NAME}\E:\s*`\$\{SCREENSHOTS_BASE\}/)[^`]+(`)}{$1$ENV{FILE}$2}' \
    "$SITE_TS"
  grep -q "/$file\`" "$SITE_TS" \
    || error "site.ts 里没找到 $name 的截图 URL — 检查 SCREENSHOTS 对象"
done

echo "▶ Updating SCREENSHOTS_BASE in site.ts..."
SCREENSHOTS_BASE="$R2_PUBLIC_BASE/screenshots" perl -0777 -pi -e \
  's{(export const SCREENSHOTS_BASE\s*=\s*")[^"]+(")}{$1$ENV{SCREENSHOTS_BASE}$2}' \
  "$SITE_TS"
echo "  → $R2_PUBLIC_BASE/screenshots"

# Drop any leftover copies under public/ so the build never ships them.
if [ -d "$PUBLIC_SHOTS" ]; then
  echo "▶ Removing website/public/screenshots/ (served from R2 now)..."
  rm -rf "$PUBLIC_SHOTS"
fi

echo ""
echo "✓ Screenshots on R2"
echo "  Base: $R2_PUBLIC_BASE/screenshots/"
echo "  Next: ./do.sh website --skip-webapp"

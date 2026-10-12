#!/usr/bin/env bash
# Upload App screenshots from docs/screenshots/ to Cloudflare R2 and point the
# marketing site at the public URLs.
#
# Objects land at:
#   $R2_PUBLIC_BASE/screenshots/{home,library,dictation,finish}.png
#
# Source of truth for the PNGs stays in docs/screenshots/ (README embeds those).
# website/public/screenshots/ is not used — the site loads from R2.
#
# Usage:
#   pnpm screenshots:upload
#   bash scripts/upload-screenshots.sh
#
# Prereqs (same R2 block as release.sh, see .env.example):
#   R2_BUCKET / R2_PUBLIC_BASE / CLOUDFLARE_ACCOUNT_ID / CLOUDFLARE_API_TOKEN

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

error() { echo "ERROR: $*" >&2; exit 1; }

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

SHOTS=(home library dictation finish)
SRC_DIR="$ROOT/docs/screenshots"
SITE_TS="$ROOT/website/src/data/site.ts"
PUBLIC_SHOTS="$ROOT/website/public/screenshots"

for name in "${SHOTS[@]}"; do
  [ -f "$SRC_DIR/$name.png" ] || error "缺少截图: $SRC_DIR/$name.png"
done

echo "▶ Uploading screenshots → $R2_BUCKET/screenshots/"
for name in "${SHOTS[@]}"; do
  key="screenshots/$name.png"
  url="$R2_PUBLIC_BASE/$key"
  pnpm exec wrangler r2 object put "$R2_BUCKET/$key" \
    --file "$SRC_DIR/$name.png" \
    --remote \
    --content-type "image/png" \
    --cache-control "public, max-age=86400"
  echo "  ✓ $url"
done

echo "▶ Updating SCREENSHOTS_BASE in site.ts..."
SCREENSHOTS_BASE="$R2_PUBLIC_BASE/screenshots" perl -0777 -pi -e \
  's{(export const SCREENSHOTS_BASE\s*=\s*")[^"]+(")}{$1$ENV{SCREENSHOTS_BASE}$2}' \
  "$SITE_TS"
# If the constant is missing, fail loudly so we don't silently ship local paths.
grep -q 'export const SCREENSHOTS_BASE' "$SITE_TS" \
  || error "site.ts 缺少 SCREENSHOTS_BASE — 先加常量再跑本脚本"
echo "  → $R2_PUBLIC_BASE/screenshots"

# Drop any leftover copies under public/ so the build never ships them.
if [ -d "$PUBLIC_SHOTS" ]; then
  echo "▶ Removing website/public/screenshots/ (served from R2 now)..."
  rm -rf "$PUBLIC_SHOTS"
fi

echo ""
echo "✓ Screenshots on R2"
echo "  Base: $R2_PUBLIC_BASE/screenshots/"
echo "  Next: bash scripts/release-website.sh --skip-webapp"

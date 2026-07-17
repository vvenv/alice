#!/usr/bin/env bash
# Deploy the marketing website (and by default the Expo Web app under /app/).
#
# Flow:
#   1. Build the website (pnpm --filter website build)
#   2. rsync dist/ to the server, excluding downloads/ and app/ so the live
#      APK and Web app are never wiped by --delete
#   3. Unless --skip-webapp: build + rsync the Expo Web app to …/app/
#
# Website and webapp deploys are order-independent: each leaves the other alone.
#
# Usage:
#   pnpm release:website              # landing + /app/ web app
#   pnpm release:website -- --skip-webapp
#   bash scripts/release-website.sh --skip-webapp
#   bash scripts/release-website.sh
#
# Prereqs: SSH key auth to the deploy server (BatchMode).
# Config from .env (see .env.example):
#   DEPLOY_SERVER=user@your.server.ip
#   DEPLOY_REMOTE_DIR=/var/www/alice

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

error() { echo "ERROR: $*" >&2; exit 1; }

SKIP_WEBAPP=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --skip-webapp)
      SKIP_WEBAPP=1
      shift
      ;;
    --help|-h)
      sed -n '3,20p' "$0"
      exit 0
      ;;
    *)
      error "未知选项: $1"
      ;;
  esac
done

if [ -f "$ROOT/.env" ]; then
  set -a
  # shellcheck disable=SC1091
  source "$ROOT/.env"
  set +a
fi
SERVER="${DEPLOY_SERVER:?DEPLOY_SERVER not set — add it to .env (see .env.example)}"
REMOTE_DIR="${DEPLOY_REMOTE_DIR:-/var/www/alice}"
PUBLIC_HOST="https://alice.edao.plus"
WEBSITE_DIR="$ROOT/website"

echo "▶ Releasing website → $SERVER:$REMOTE_DIR"
echo ""

echo "▶ [1/2] Building website..."
pnpm --filter website build

# Never wipe live APKs or the Expo Web app directory when syncing the landing site.
echo "▶ [2/2] Deploying to $SERVER:$REMOTE_DIR (excluding downloads/ and app/)..."
rsync -avz --delete --exclude=downloads --exclude=app \
  "$WEBSITE_DIR/dist/" "$SERVER:$REMOTE_DIR/"

echo ""
echo "✓ Website deployed"
echo "  Site: $PUBLIC_HOST"
echo "  (server downloads/ and app/ left untouched)"

if [ "$SKIP_WEBAPP" -eq 0 ]; then
  echo ""
  bash "$ROOT/scripts/release-webapp.sh"
else
  echo "  (--skip-webapp: Expo Web app not updated)"
fi

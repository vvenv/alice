#!/usr/bin/env bash
# Deploy the marketing website only (no APK build).
#
# Flow:
#   1. Build the website (pnpm --filter website build)
#   2. rsync dist/ to the server, excluding downloads/ so the live APK
#      is never wiped (APKs are gitignored and usually absent locally)
#
# Usage:
#   pnpm release:website
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

while [[ $# -gt 0 ]]; do
  case "$1" in
    --help|-h)
      sed -n '3,16p' "$0"
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

echo "▶ [2/2] Deploying to $SERVER:$REMOTE_DIR (excluding downloads/)..."
rsync -avz --delete --exclude=downloads \
  "$WEBSITE_DIR/dist/" "$SERVER:$REMOTE_DIR/"

echo ""
echo "✓ Website deployed"
echo "  Site: $PUBLIC_HOST"
echo "  (server downloads/ left untouched — APK URL unchanged)"

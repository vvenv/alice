#!/usr/bin/env bash
# Deploy the Flutter Web build to /app/ on the marketing site host.
#
# Safe to run before or after release-website.sh: the website sync excludes
# app/, and this script only writes into …/app/.
#
# Flow:
#   1. flutter build web --release --base-href /app/, with no embedded OCR key
#   2. rsync build/web/ to $REMOTE_DIR/app/
#
# Usage:
#   pnpm release:webapp
#   bash scripts/release-webapp.sh
#   (also invoked by release-website.sh unless --skip-webapp)
#
# Prereqs: Flutter SDK on PATH, SSH key auth to the deploy server (BatchMode).
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
APP_REMOTE="$REMOTE_DIR/app"
DIST_DIR="$ROOT/build/web"

echo "▶ Releasing web app → $SERVER:$APP_REMOTE"
echo ""

echo "▶ [1/2] Building Flutter Web (no embedded OCR key)..."
# ★ 不要传 --dart-define=ZHIPU_API_KEY：Web 产物是公开的 JS，内嵌共享密钥等于
#   把它发出去。Web 上 OCR 由用户在设置里自备 API Key。
# ★ 必须带 --base-href /app/：默认是 /，相对路径会打到官网根上，
#   flutter_bootstrap.js / manifest.json 全部 404。
flutter build web --release --base-href /app/

if [ ! -f "$DIST_DIR/index.html" ]; then
  error "build did not produce dist/index.html"
fi
if ! grep -q '<base href="/app/">' "$DIST_DIR/index.html"; then
  error "build/web/index.html 的 base href 不是 /app/ —— 资源会打到官网根路径 404"
fi

echo "▶ [2/2] Deploying to $SERVER:$APP_REMOTE..."
ssh -o BatchMode=yes "$SERVER" "mkdir -p '$APP_REMOTE'"
# --partial + SSH keepalive: see release.sh for rationale (prevents mid-transfer
#   drops and lets retries resume).
rsync -avz --delete --partial \
  -e "ssh -o BatchMode=yes -o ServerAliveInterval=15 -o ServerAliveCountMax=4 -o TCPKeepAlive=yes" \
  "$DIST_DIR/" "$SERVER:$APP_REMOTE/"

echo ""
echo "✓ Web app deployed"
echo "  App:  $PUBLIC_HOST/app/"
echo "  Note: OCR on Web requires a user-provided API key in Settings"

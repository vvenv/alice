#!/usr/bin/env bash
# Deploy the Expo Web app to /app/ on the marketing site host.
#
# Flow:
#   1. Static-export the app (pnpm build → dist/), with no embedded OCR key
#   2. rsync dist/ to $REMOTE_DIR/app/
#
# Usage:
#   pnpm release:webapp
#   bash scripts/release-webapp.sh
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
APP_REMOTE="$REMOTE_DIR/app"
DIST_DIR="$ROOT/dist"

echo "▶ Releasing web app → $SERVER:$APP_REMOTE"
echo ""

echo "▶ [1/2] Building Expo Web (no embedded OCR key)..."
pnpm build

if [ ! -f "$DIST_DIR/index.html" ]; then
  error "build did not produce dist/index.html"
fi

echo "▶ [2/2] Deploying to $SERVER:$APP_REMOTE..."
ssh -o BatchMode=yes "$SERVER" "mkdir -p '$APP_REMOTE'"
rsync -avz --delete "$DIST_DIR/" "$SERVER:$APP_REMOTE/"

echo ""
echo "✓ Web app deployed"
echo "  App:  $PUBLIC_HOST/app/"
echo "  Note: OCR on Web requires a user-provided API key in Settings"

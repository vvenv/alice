#!/bin/bash
# 开发模式：确保 SSH 隧道可用、后台看门狗自动重连，再启动 pnpm dev。
#
# 用法: ./scripts/dev-tunnel.sh
# 等价于: pnpm dev:tunnel

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck source=scripts/lib/log.sh
source "$ROOT/scripts/lib/log.sh"

WATCH_PID=""

cleanup() {
  if [ -n "$WATCH_PID" ] && kill -0 "$WATCH_PID" 2>/dev/null; then
    kill "$WATCH_PID" 2>/dev/null || true
    wait "$WATCH_PID" 2>/dev/null || true
  fi
}

trap cleanup EXIT INT TERM

cd "$ROOT"

bash scripts/db-tunnel.sh ensure
bash scripts/db-tunnel.sh watch &
WATCH_PID=$!

export REGORA_ENV_FILE=.env.tunnel

pnpm --filter @alice/shared build

REGORA_ENV_FILE=.env.tunnel concurrently \
  --names "server,client" \
  --prefix-colors "blue,green" \
  --kill-others-on-fail \
  "pnpm --filter server dev" \
  "bash scripts/wait-for-server.sh && pnpm --filter client dev"

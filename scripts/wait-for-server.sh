#!/bin/bash
# 等待本地 API server 就绪后再启动 Vite，避免 /api 代理 502。
#
# 用法: ./scripts/wait-for-server.sh [host] [port]

set -euo pipefail

HOST="${1:-127.0.0.1}"
PORT="${2:-3400}"
INTERVAL=1

# shellcheck source=scripts/lib/log.sh
source "$(cd "$(dirname "$0")/.." && pwd)/scripts/lib/log.sh"

log_info "等待 server 就绪 (http://${HOST}:${PORT}/health)..."

while ! curl -sf "http://${HOST}:${PORT}/health" >/dev/null 2>&1; do
  sleep "$INTERVAL"
done

log_success "server 已就绪"

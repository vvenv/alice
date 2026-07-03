#!/bin/bash
# Edge 部署健康检查（数据库 + BR 端点）
# 用法: APP_DIR=/var/www/regora bash scripts/health-check-edge.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
APP_DIR="${APP_DIR:-$(cd "$SCRIPT_DIR/.." && pwd)}"

# shellcheck source=lib/log.sh
source "${SCRIPT_DIR}/lib/log.sh"

cd "$APP_DIR"
[ -f ".env" ] || log_die "缺少 .env"

set -a
# shellcheck source=/dev/null
. ".env"
set +a

pnpm --filter server exec tsx scripts/harvest-edge-verify.ts
APP_DIR="$APP_DIR" bash "${SCRIPT_DIR}/harvest-edge-cron.sh" status

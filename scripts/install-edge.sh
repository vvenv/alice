#!/bin/bash
# Edge 节点依赖安装（无 migration；迁移仅在主站执行）
# 用法: APP_DIR=/var/www/regora bash scripts/install-edge.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=lib/log.sh
source "${SCRIPT_DIR}/lib/log.sh"

APP_DIR="${APP_DIR:-$(cd "${SCRIPT_DIR}/.." && pwd)}"
cd "$APP_DIR"


[ -f "package.json" ] || log_die "缺少 package.json"
[ -d "packages/server" ] || log_die "缺少 packages/server"

if [ -f ".env" ]; then
  set -a
  # shellcheck source=/dev/null
  . ".env"
  set +a
fi

[ -n "${DATABASE_URL:-}" ] || log_die ".env 中未设置 DATABASE_URL"

if ! command -v node >/dev/null 2>&1; then
  log_die "未安装 Node.js"
fi

if ! command -v pnpm >/dev/null 2>&1; then
  log_info "安装 pnpm..."
  npm install -g pnpm
fi

log_info "pnpm install..."
pnpm install --frozen-lockfile

log_info "prisma generate..."
pnpm --filter server exec prisma generate

log_info "Edge 依赖就绪"

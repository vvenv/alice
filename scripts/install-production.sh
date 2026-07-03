#!/bin/bash
# 在目标服务器上安装依赖（alice 无数据库迁移）
# 用法:
#   APP_DIR=/var/www/alice ENVIRONMENT=production ./scripts/install-production.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
APP_DIR="${APP_DIR:-$SCRIPT_DIR/..}"
ENVIRONMENT="${ENVIRONMENT:-production}"
cd "$APP_DIR"

# shellcheck source=lib/log.sh
source "${SCRIPT_DIR}/lib/log.sh"

if [ "$ENVIRONMENT" != "production" ] && [ "$ENVIRONMENT" != "test" ]; then
  log_error "无效的环境: ${ENVIRONMENT}（仅支持 production 或 test）"
  exit 1
fi

if [ ! -f "package.json" ] || [ ! -d "packages/server" ]; then
  log_error "未在有效的 alice 部署目录中运行"
  exit 1
fi

resolve_env_file() {
  if [ -f ".env" ]; then
    return 0
  fi
  local candidate=""
  if [ "$ENVIRONMENT" = "test" ] && [ -f ".env.test" ]; then
    candidate=".env.test"
  elif [ "$ENVIRONMENT" = "production" ] && [ -f ".env.production" ]; then
    candidate=".env.production"
  fi
  if [ -n "$candidate" ]; then
    log_info "未找到 .env，使用 $candidate"
    ln -sf "$candidate" .env
  fi
}

resolve_env_file

if [ ! -f ".env" ]; then
  log_error "未找到 $APP_DIR/.env，请先配置环境变量"
  exit 1
fi

if ! command -v pnpm &> /dev/null; then
  log_error "需要 pnpm"
  exit 1
fi

NODE_MAJOR="$(node -v | sed 's/v//' | cut -d. -f1)"
if [ "$NODE_MAJOR" -lt 22 ]; then
  log_error "需要 Node.js >= 22，当前: $(node -v)"
  exit 1
fi

log_info "环境: $ENVIRONMENT ($APP_DIR)"
log_info "安装依赖..."
pnpm install --frozen-lockfile

log_info "初始化完成"

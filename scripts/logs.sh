#!/bin/bash
# 查看当前活跃槽位的 PM2 日志
# 用法: ./scripts/logs.sh [--env production|test] [lines]
# 示例: ./scripts/logs.sh --env test 100

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=lib/blue-green.sh
source "${SCRIPT_DIR}/lib/blue-green.sh"
# shellcheck source=lib/log.sh
source "${SCRIPT_DIR}/lib/log.sh"


ENVIRONMENT="production"
LINES="50"

while [[ $# -gt 0 ]]; do
  case $1 in
    --env)
      ENVIRONMENT="$2"
      shift 2
      ;;
    *)
      LINES="$1"
      shift
      ;;
  esac
done

if [ "$EUID" -ne 0 ]; then
  log_error "请使用 root 用户运行此脚本"
  exit 1
fi

if [ "$ENVIRONMENT" != "production" ] && [ "$ENVIRONMENT" != "test" ]; then
  log_error "无效的环境参数: $ENVIRONMENT (仅支持 production 或 test)"
  exit 1
fi

bg_load_env "$ENVIRONMENT"
bg_migrate_legacy_if_needed

ACTIVE_SLOT="$(bg_get_active_slot)"
ACTIVE_APP="$(bg_slot_app "$ACTIVE_SLOT")"

log_info "查看环境: $ENVIRONMENT"
log_info "活跃槽位: $ACTIVE_SLOT ($ACTIVE_APP)"
log_info "最近 $LINES 行日志..."

pm2 logs "$ACTIVE_APP" --lines "$LINES" --nostream

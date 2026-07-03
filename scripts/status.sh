#!/bin/bash
# 查看蓝绿部署状态
# 用法: ./scripts/status.sh [--env production|test]

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=lib/blue-green.sh
source "${SCRIPT_DIR}/lib/blue-green.sh"
# shellcheck source=lib/log.sh
source "${SCRIPT_DIR}/lib/log.sh"


ENVIRONMENT="production"

while [[ $# -gt 0 ]]; do
  case $1 in
    --env)
      ENVIRONMENT="$2"
      shift 2
      ;;
    *)
      shift
      ;;
  esac
done

if [ "$EUID" -ne 0 ]; then
  log_error "请使用 root 用户运行此脚本"
  exit 1
fi

bg_load_env "$ENVIRONMENT"
bg_migrate_legacy_if_needed

ACTIVE_SLOT="$(bg_get_active_slot)"
INACTIVE_SLOT="$(bg_get_inactive_slot)"

log_info "环境: ${ENVIRONMENT}"
log_info "活跃槽位: ${ACTIVE_SLOT}（端口 $(bg_slot_port "$ACTIVE_SLOT")，$(bg_slot_app "$ACTIVE_SLOT")）"
log_info "空闲槽位: ${INACTIVE_SLOT}（端口 $(bg_slot_port "$INACTIVE_SLOT")，$(bg_slot_app "$INACTIVE_SLOT")）"

pm2 status

for slot in a b; do
  app="$(bg_slot_app "$slot")"
  if pm2 describe "$app" &>/dev/null; then
    log_info "--- ${app} ---"
    pm2 log_info "$app" 2>/dev/null | head -20 || true
  fi
done

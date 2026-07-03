#!/bin/bash
# 重启当前活跃槽位
# 用法: ./scripts/restart.sh [--env production|test]

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
    regora|regora-test)
      if [ "$1" = "regora-test" ]; then
        ENVIRONMENT="test"
      else
        ENVIRONMENT="production"
      fi
      shift
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
ACTIVE_APP="$(bg_slot_app "$ACTIVE_SLOT")"
ACTIVE_PORT="$(bg_slot_port "$ACTIVE_SLOT")"

log_info "重启活跃槽位: ${ACTIVE_SLOT}（${ACTIVE_APP}，端口 ${ACTIVE_PORT}）"

pm2 restart "$ACTIVE_APP" || bg_start_slot_app "$ACTIVE_SLOT"

log_info "服务已重启"
log_info "查看状态: pm2 status"
log_info "查看日志: pm2 logs ${ACTIVE_APP}"

#!/bin/bash
# 启动当前活跃槽位（蓝绿部署）
# 用法: ./scripts/start.sh [--env production|test]

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
    alice|alice-test)
      if [ "$1" = "alice-test" ]; then
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

if ! bg_slot_has_release "$ACTIVE_SLOT"; then
  log_error "活跃槽位 ${ACTIVE_SLOT} 尚未部署，请先运行 deploy-local-archive.sh"
  exit 1
fi

bg_start_slot_app "$ACTIVE_SLOT"

pm2 startup systemd -u root --hp /root 2>/dev/null || true
pm2 save

log_info "服务启动完成（槽位 ${ACTIVE_SLOT}）"
log_info "查看状态: pm2 status"
log_info "查看日志: pm2 logs $(bg_slot_app "$ACTIVE_SLOT")"

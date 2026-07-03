#!/bin/bash
# 停止当前环境所有槽位
# 用法: ./scripts/stop.sh [--env production|test]

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

log_info "停止 ${ENVIRONMENT} 环境所有槽位..."
bg_stop_slot_app "a"
bg_stop_slot_app "b"
log_info "服务已停止"

#!/bin/bash
# 对当前活跃槽位做健康检查
# 用法: ./scripts/health-check.sh [--env production|test] [--attempts 30] [--interval 2]

set -euo pipefail

_SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=lib/blue-green.sh
source "${_SCRIPT_DIR}/lib/blue-green.sh"

ENVIRONMENT="production"
MAX_ATTEMPTS="30"
INTERVAL="2"

while [[ $# -gt 0 ]]; do
  case $1 in
    --env)
      ENVIRONMENT="$2"
      shift 2
      ;;
    --attempts)
      MAX_ATTEMPTS="$2"
      shift 2
      ;;
    --interval)
      INTERVAL="$2"
      shift 2
      ;;
    --help|-h)
      echo "用法: $0 [--env production|test] [--attempts 30] [--interval 2]"
      exit 0
      ;;
    *)
      echo "未知选项: $1" >&2
      exit 1
      ;;
  esac
done

bg_load_env "$ENVIRONMENT"
bg_migrate_legacy_if_needed

PORT="$(bg_get_active_port)"
ACTIVE_SLOT="$(bg_get_active_slot)"

echo "健康检查: ${ENVIRONMENT} 槽位 ${ACTIVE_SLOT}，端口 ${PORT}"

if bg_wait_health "$PORT" "$MAX_ATTEMPTS" "$INTERVAL"; then
  exit 0
fi

exit 1

#!/bin/bash
# 在远程服务器执行 env 同步（由 scripts/sync-env-remote.sh 上传并调用）
set -euo pipefail

SYNC_DIR="${1:-}"
ENVIRONMENT="${2:-production}"
RESTART_AFTER_SYNC="${3:-1}"

if [ -z "$SYNC_DIR" ] || [ ! -d "$SYNC_DIR" ]; then
  echo "sync-env-remote-run: 无效的 SYNC_DIR: ${SYNC_DIR:-<empty>}"
  exit 1
fi

SCRIPT="${SYNC_DIR}/scripts/sync-env-ci.sh"
if [ ! -f "$SCRIPT" ]; then
  echo "sync-env-ci.sh not found: $SCRIPT"
  exit 1
fi

set -a
# shellcheck disable=SC1090
source "${SYNC_DIR}/sync-vars.env"
set +a

chmod +x "$SCRIPT"
bash "$SCRIPT"

if [ "$RESTART_AFTER_SYNC" = "1" ]; then
  BG_SCRIPT=""
  for dir in /var/www/alice_a /var/www/alice_b /var/www/alice_test_a /var/www/alice_test_b; do
    if [ -f "${dir}/scripts/lib/blue-green.sh" ]; then
      BG_SCRIPT="${dir}/scripts/lib/blue-green.sh"
      break
    fi
  done
  if [ -z "$BG_SCRIPT" ]; then
    BG_SCRIPT="${SYNC_DIR}/scripts/lib/blue-green.sh"
  fi
  # shellcheck disable=SC1090
  source "$BG_SCRIPT"
  bg_load_env "$ENVIRONMENT"
  bg_migrate_legacy_if_needed
  ACTIVE_SLOT="$(bg_get_active_slot)"
  APP_NAME="$(bg_slot_app "$ACTIVE_SLOT")"
  if command -v pm2 >/dev/null 2>&1 && pm2 describe "$APP_NAME" >/dev/null 2>&1; then
    pm2 restart "$APP_NAME" --update-env
    pm2 save
    echo "PM2 已重启: $APP_NAME"
  else
    echo "PM2 进程 $APP_NAME 未运行，跳过重启"
  fi
fi

rm -rf "$SYNC_DIR"

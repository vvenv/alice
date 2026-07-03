#!/bin/bash
# 在远程 Edge 服务器安装 .env（由 scripts/sync-env-remote.sh 上传并调用）
set -euo pipefail

SYNC_DIR="${1:-}"
APP_DIR="${2:-/var/www/regora}"

if [ -z "$SYNC_DIR" ] || [ ! -f "${SYNC_DIR}/edge.env" ]; then
  echo "sync-env-remote-edge-run: 无效的 SYNC_DIR 或缺少 edge.env"
  exit 1
fi

# shellcheck disable=SC1090
source "${SYNC_DIR}/scripts/lib/edge-deploy.sh"
edge_install_env_file "$APP_DIR" "${SYNC_DIR}/edge.env"
rm -rf "$SYNC_DIR"
echo "Edge ${APP_DIR}/.env 已更新（cron 下次执行自动生效）"

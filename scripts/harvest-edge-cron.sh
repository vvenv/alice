#!/bin/bash
# 安装 / 更新 / 检查 Harvest Edge cron（采集 + 信号详情抓取）
# 用法: APP_DIR=/var/www/regora bash scripts/harvest-edge-cron.sh install|status|uninstall
#
# bootstrap-edge-ci.sh / deploy-edge-archive.sh 会自动调用 install。

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
APP_DIR="${APP_DIR:-$(cd "$SCRIPT_DIR/.." && pwd)}"
# shellcheck source=lib/edge-deploy.sh
source "${SCRIPT_DIR}/lib/edge-deploy.sh"

ACTION="${1:-install}"

if [ -f "${APP_DIR}/.env" ]; then
  set -a
  # shellcheck source=/dev/null
  . "${APP_DIR}/.env"
  set +a
fi

HARVEST_SCHEDULE="${HARVEST_EDGE_CRON:-0 * * * *}"
INGEST_SCHEDULE="${HARVEST_EDGE_INGEST_CRON:-*/2 * * * *}"

ensure_cron_service() {
  if systemctl is-active --quiet cron 2>/dev/null || systemctl is-active --quiet crond 2>/dev/null; then
    return 0
  fi
  edge_info "cron 服务未运行，尝试启动..."
  systemctl start cron 2>/dev/null || systemctl start crond 2>/dev/null || edge_error "无法启动 cron 服务"
  systemctl enable cron 2>/dev/null || systemctl enable crond 2>/dev/null || true
}

remove_edge_cron_lines() {
  local tmp
  tmp="$(mktemp)"
  crontab -l 2>/dev/null | grep -Fv "$EDGE_CRON_MARKER" >"$tmp" || true
  crontab "$tmp"
  rm -f "$tmp"
}

cron_contains_script() {
  local script_name="$1"
  crontab -l 2>/dev/null | grep -Fq "$script_name" || return 1
}

case "$ACTION" in
  uninstall|remove)
    remove_edge_cron_lines
    edge_info "已移除 Harvest Edge cron"
    exit 0
    ;;
  status)
    missing=0
    if cron_contains_script "harvest-edge-runner.ts"; then
      edge_info "cron: harvest-edge-runner 已安装 (${HARVEST_SCHEDULE})"
    else
      log_warn "cron: 缺少 harvest-edge-runner"
      missing=1
    fi
    if cron_contains_script "harvest-edge-ingest-runner.ts"; then
      edge_info "cron: harvest-edge-ingest-runner 已安装 (${INGEST_SCHEDULE})"
    else
      log_warn "cron: 缺少 harvest-edge-ingest-runner"
      missing=1
    fi
    exit "$missing"
    ;;
  install|update)
    ;;
  *)
    echo "用法: $0 install|status|uninstall" >&2
    exit 1
    ;;
esac

PNPM_BIN="$(command -v pnpm)"
[ -n "$PNPM_BIN" ] || edge_error "未找到 pnpm"

ensure_cron_service

# dash（cron 默认 /bin/sh）不会在当前目录查找 `. .env`，必须用 `./.env`
HARVEST_LINE="${HARVEST_SCHEDULE} cd ${APP_DIR} && set -a && . ./.env && set +a && ${PNPM_BIN} --filter server exec tsx scripts/harvest-edge-runner.ts >> /var/log/regora-harvest-edge.log 2>&1 ${EDGE_CRON_MARKER}"
INGEST_LINE="${INGEST_SCHEDULE} cd ${APP_DIR} && set -a && . ./.env && set +a && ${PNPM_BIN} --filter server exec tsx scripts/harvest-edge-ingest-runner.ts >> /var/log/regora-harvest-edge-ingest.log 2>&1 ${EDGE_CRON_MARKER}"

tmp="$(mktemp)"
crontab -l 2>/dev/null | grep -Fv "$EDGE_CRON_MARKER" >"$tmp" || true
printf '%s\n' "$HARVEST_LINE" >>"$tmp"
printf '%s\n' "$INGEST_LINE" >>"$tmp"
crontab "$tmp"
rm -f "$tmp"

edge_info "cron 已安装: harvest ${HARVEST_SCHEDULE}, ingest ${INGEST_SCHEDULE}"

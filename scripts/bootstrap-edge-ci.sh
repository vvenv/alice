#!/bin/bash
# Harvest Edge 首次引导（圣保罗 VPS：Node + 代码 + cron，连主站 Postgres）
#
# 必填参数:
#   --env-file <path>   Edge 运行时 env 文件（由本地 .env.edge 上传而来）
#                       含 DATABASE_URL / HARVEST_EXECUTION_REGION 等

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=lib/edge-deploy.sh
source "${SCRIPT_DIR}/lib/edge-deploy.sh"

ARCHIVE=""
ENV_FILE=""
while [[ $# -gt 0 ]]; do
  case $1 in
    --version) VERSION="$2"; shift 2 ;;
    --env-file) ENV_FILE="$2"; shift 2 ;;
    --) shift; break ;;
    -*) edge_error "未知选项: $1" ;;
    *) ARCHIVE="$1"; shift ;;
  esac
done

[ "$(id -u)" -eq 0 ] || edge_error "请以 root 运行"
[ -n "$ARCHIVE" ] && [ -f "$ARCHIVE" ] || edge_error "请传入有效 tarball"
[ -n "$ENV_FILE" ] && [ -f "$ENV_FILE" ] || edge_error "缺少 --env-file 或文件不存在（应由本地 .env.edge 上传）"

APP_DIR="$(edge_resolve_app_dir)"
if [ -z "${VERSION:-}" ]; then
  VERSION="$(basename "$ARCHIVE" .tar.gz)"
  VERSION="${VERSION#regora-}"
fi

install_nodejs() {
  if command -v node >/dev/null 2>&1 && [ "$(node -v | sed 's/v//' | cut -d. -f1)" -ge 22 ]; then
    edge_info "Node.js $(node -v) 已安装"
    return
  fi
  edge_info "安装 Node.js 22..."
  apt-get update -qq
  curl -fsSL https://deb.nodesource.com/setup_22.x | bash -
  apt-get install -y -qq nodejs
}

install_pnpm() {
  command -v pnpm >/dev/null 2>&1 || npm install -g pnpm
}

deploy_archive() {
  local tmp_extract
  tmp_extract="$(mktemp -d)"
  tar -xzf "$ARCHIVE" -C "$tmp_extract"
  mkdir -p "$APP_DIR"

  if [ -f "${APP_DIR}/.env" ]; then
    cp -a "${APP_DIR}/.env" "${tmp_extract}/.env.bak"
  fi

  rsync -a --delete \
    --exclude 'node_modules' \
    --exclude '.env' \
    --exclude 'data' \
    "$tmp_extract/" "$APP_DIR/"

  [ -f "${tmp_extract}/.env.bak" ] && cp -a "${tmp_extract}/.env.bak" "${APP_DIR}/.env" || true
  rm -rf "$tmp_extract"
}

edge_info "===== Harvest Edge Bootstrap ====="
edge_info "版本: $VERSION"
edge_info "目录: $APP_DIR"

install_nodejs
install_pnpm
deploy_archive
edge_install_env_file "$APP_DIR" "$ENV_FILE"
APP_DIR="$APP_DIR" bash "${APP_DIR}/scripts/install-edge.sh"
APP_DIR="$APP_DIR" bash "${APP_DIR}/scripts/harvest-edge-cron.sh" install
APP_DIR="$APP_DIR" bash "${APP_DIR}/scripts/health-check-edge.sh"

edge_info "===== Bootstrap 完成 ====="


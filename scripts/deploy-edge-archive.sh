#!/bin/bash
# Harvest Edge 日常更新：解压 release → install-edge → 刷新 cron
# 用法: ./scripts/deploy-edge-archive.sh <archive.tar.gz> [--version v1.0.0]

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=lib/edge-deploy.sh
source "${SCRIPT_DIR}/lib/edge-deploy.sh"

ARCHIVE=""
VERSION=""

while [[ $# -gt 0 ]]; do
  case $1 in
    --version) VERSION="$2"; shift 2 ;;
    --help|-h)
      echo "用法: $0 <archive.tar.gz> [--version v1.0.0]"
      exit 0
      ;;
    -*)
      edge_error "未知选项: $1"
      ;;
    *)
      ARCHIVE="$1"
      shift
      ;;
  esac
done

[ -n "$ARCHIVE" ] && [ -f "$ARCHIVE" ] || edge_error "请指定有效 tarball"
[ "$(id -u)" -eq 0 ] || edge_error "请以 root 运行"

if [ -z "$VERSION" ]; then
  VERSION="$(basename "$ARCHIVE" .tar.gz)"
  VERSION="${VERSION#regora-}"
fi

APP_DIR="$(edge_resolve_app_dir)"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

edge_info "Edge 部署版本: $VERSION"
edge_info "归档: $ARCHIVE"

mkdir -p "$TMP_DIR/extracted"
tar -xzf "$ARCHIVE" -C "$TMP_DIR/extracted"
mkdir -p "$APP_DIR"

for keep in .env data; do
  [ -e "${APP_DIR}/${keep}" ] && cp -a "${APP_DIR}/${keep}" "${TMP_DIR}/${keep}.bak" 2>/dev/null || true
done

rsync -a --delete \
  --exclude 'node_modules' \
  --exclude '.env' \
  --exclude 'data' \
  "$TMP_DIR/extracted/" "$APP_DIR/"

for keep in .env data; do
  [ -e "${TMP_DIR}/${keep}.bak" ] && cp -a "${TMP_DIR}/${keep}.bak" "${APP_DIR}/${keep}" || true
done

APP_DIR="$APP_DIR" bash "${APP_DIR}/scripts/install-edge.sh"
APP_DIR="$APP_DIR" bash "${APP_DIR}/scripts/harvest-edge-cron.sh" install
APP_DIR="$APP_DIR" bash "${APP_DIR}/scripts/health-check-edge.sh"

edge_info "Edge 部署完成: $VERSION"

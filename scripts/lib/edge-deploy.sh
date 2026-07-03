#!/bin/bash
# Harvest Edge 部署常量（圣保罗采集节点，无蓝绿 / 无 Nginx）

set -euo pipefail

# shellcheck source=log.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/log.sh"

EDGE_APP_DIR="${EDGE_APP_DIR:-/var/www/regora}"
EDGE_REMOTE_STAGING_DIR="${EDGE_REMOTE_STAGING_DIR:-/tmp/regora-edge-deploy}"
EDGE_BOOTSTRAP_STAGING_DIR="${EDGE_BOOTSTRAP_STAGING_DIR:-/tmp/regora-edge-bootstrap}"
EDGE_CRON_MARKER="# regora-harvest-edge"

edge_info()  { log_info "$@"; }
edge_error() { log_die "$@"; }

edge_is_valid_environment() {
  [ "${1:-}" = "edge" ]
}

edge_resolve_app_dir() {
  echo "$EDGE_APP_DIR"
}

# DATABASE_URL 查询串含 &，写入 .env 时必须加引号，否则 bash source 会截断/报错
edge_quote_database_url_in_env_file() {
  local env_file="$1"
  [ -f "$env_file" ] || return 0
  grep -q '^DATABASE_URL=' "$env_file" || return 0
  local db_url
  db_url="$(grep '^DATABASE_URL=' "$env_file" | head -1 | sed 's/^DATABASE_URL=//; s/^"//; s/"$//')"
  awk -v url="$db_url" '
    /^DATABASE_URL=/ { print "DATABASE_URL=\"" url "\""; next }
    { print }
  ' "$env_file" >"${env_file}.tmp" && mv "${env_file}.tmp" "$env_file"
}

# edge_install_env_file 写入 Edge 运行时 .env（剔除本机专用 DEPLOY_* 等键）
edge_install_env_file() {
  local app_dir="$1"
  local source_env_file="$2"

  [ -n "$source_env_file" ] || edge_error "edge_install_env_file: 缺少 env 文件路径"
  [ -f "$source_env_file" ] || edge_error "找不到 env 文件: $source_env_file"

  mkdir -p "$app_dir/data/attachments"
  awk '
    /^[[:space:]]*#/ { print; next }
    /^[[:space:]]*$/ { print; next }
    {
      key = $0
      sub(/=.*/, "", key)
      gsub(/[[:space:]]/, "", key)
      if (key ~ /^DEPLOY_/ || key == "REGORA_DOMAIN" || key == "REGORA_PORT" || key == "DEPLOY_ENV" || key == "DB_PASSWORD" || key == "SSL_EMAIL") next
      print
    }
  ' "$source_env_file" >"${app_dir}/.env"
  edge_quote_database_url_in_env_file "${app_dir}/.env"
  chmod 600 "${app_dir}/.env"
}

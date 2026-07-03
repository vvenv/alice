# 按目标环境加载仓库根目录 dotenv（本地开发 / SSH 部署 / bootstrap 共用）
# 用法: ROOT=/path/to/repo source scripts/lib/deploy-env.sh
#       load_deploy_env "$ROOT" production   # → .env.production
#       load_deploy_env "$ROOT" test         # → .env.test

if [ -z "${ROOT:-}" ]; then
  ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
fi

# shellcheck source=log.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/log.sh"

deploy_env_file_for() {
  local root="${1:-$ROOT}"
  local env="${2:-}"
  if [ -z "$env" ]; then
    env="${DEPLOY_ENV:-${ENVIRONMENT:-production}}"
  fi
  case "$env" in
    test) echo "$root/.env.test" ;;
    production) echo "$root/.env.production" ;;
    *)
      echo "$root/.env.production"
      ;;
  esac
}

load_deploy_env() {
  local root="${1:-$ROOT}"
  local env_file
  env_file="$(deploy_env_file_for "$root" "${2:-}")"
  if [ -f "$env_file" ]; then
    set -a
    # shellcheck source=/dev/null
    . "$env_file"
    set +a
  fi
}

deploy_env_has() {
  local value="${1:-}"
  [ -n "$value" ]
}

deploy_env_is_placeholder_db_password() {
  case "${1:-}" in
    ""|your-db-password|your-password|changeme|change-me*) return 0 ;;
    *) return 1 ;;
  esac
}

deploy_env_is_placeholder_jwt_secret() {
  case "${1:-}" in
    ""|your-64-char-random-jwt-secret|your-jwt-secret|changeme|change-me*) return 0 ;;
    *) return 1 ;;
  esac
}

# 本机专用变量：上传至远程服务器前必须剔除（DEPLOY_* 等）
deploy_env_is_local_only_key() {
  case "$1" in
    DEPLOY_*|REGORA_DOMAIN|REGORA_PORT|DEPLOY_ENV|DB_PASSWORD|SSL_EMAIL) return 0 ;;
    *) return 1 ;;
  esac
}

# node-postgres 将 sslmode=require 视为 verify-full，会拒绝自建库自签证书。
# 无 sslrootcert 时自动加 uselibpqcompat=true（与 libpq require 一致：仅加密、不校验 CA）。
deploy_env_normalize_database_url() {
  local url="${1:-}"
  case "$url" in
    postgresql://*|postgres://*) ;;
    *) echo "$url"; return ;;
  esac
  if [[ "$url" == *sslrootcert=* ]]; then
    echo "$url"
    return
  fi
  if [[ "$url" == *sslmode=require* && "$url" != *uselibpqcompat=* ]]; then
    if [[ "$url" == *\?* ]]; then
      echo "${url}&uselibpqcompat=true"
    else
      echo "${url}?uselibpqcompat=true"
    fi
    return
  fi
  echo "$url"
}

# 从源 env 文件写出远程运行时 env（去掉本机专用键）
deploy_env_write_runtime_file() {
  local source="$1"
  local dest="$2"

  [ -n "$source" ] || return 1
  [ -f "$source" ] || return 1

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
  ' "$source" >"$dest"

  if grep -q '^DATABASE_URL=' "$dest"; then
    local db_url normalized
    db_url="$(grep '^DATABASE_URL=' "$dest" | head -1 | sed 's/^DATABASE_URL=//; s/^"//; s/"$//')"
    normalized="$(deploy_env_normalize_database_url "$db_url")"
    awk -v normalized="$normalized" '
      /^DATABASE_URL=/ { print "DATABASE_URL=\"" normalized "\""; next }
      { print }
    ' "$dest" >"${dest}.tmp" && mv "${dest}.tmp" "$dest"
  fi

  chmod 600 "$dest"
}

# 将 env 文件中的示例占位值视为未配置，便于交互式补全或非交互式报错
deploy_env_clear_placeholder_secrets() {
  if deploy_env_is_placeholder_db_password "${DB_PASSWORD:-}"; then
    unset DB_PASSWORD
  fi
  if deploy_env_is_placeholder_jwt_secret "${JWT_SECRET:-}"; then
    unset JWT_SECRET
  fi
}

deploy_env_db_host_from_url() {
  echo "${1}" | sed -E 's|^postgresql://[^@]+@([^:/?]+).*|\1|'
}

deploy_env_db_port_from_url() {
  local port
  port="$(echo "${1}" | sed -nE 's|^postgresql://[^@]+@[^:/]+:([0-9]+).*|\1|p')"
  echo "${port:-5432}"
}

deploy_env_collect_placeholder_secrets() {
  local missing=()
  if deploy_env_is_placeholder_db_password "${DB_PASSWORD:-}"; then
    missing+=("DB_PASSWORD")
  fi
  if deploy_env_is_placeholder_jwt_secret "${JWT_SECRET:-}"; then
    missing+=("JWT_SECRET")
  fi
  if [ "${#missing[@]}" -gt 0 ]; then
    printf '%s\n' "${missing[@]}"
  fi
}

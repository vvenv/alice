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

# 本机专用变量：上传至远程服务器前必须剔除（DEPLOY_* 等）
deploy_env_is_local_only_key() {
  case "$1" in
    DEPLOY_*|REGORA_DOMAIN|REGORA_PORT|DEPLOY_ENV|SSL_EMAIL) return 0 ;;
    *) return 1 ;;
  esac
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
      if (key ~ /^DEPLOY_/ || key == "REGORA_DOMAIN" || key == "REGORA_PORT" || key == "DEPLOY_ENV" || key == "SSL_EMAIL") next
      print
    }
  ' "$source" >"$dest"

  chmod 600 "$dest"
}

#!/bin/bash
# 从 CI Secrets 写入共享 env（/etc/alice/env.production 或 env.test）
#
# 必填环境变量:
#   ENVIRONMENT                  production | test
#   DB_PASSWORD                  PostgreSQL alice 用户密码
#   JWT_SECRET                   JWT 签名密钥
#   TENANT_SECRET_ENCRYPTION_KEY 租户 secret AES-GCM 密钥（32 字节 hex；bootstrap 可自动生成）
#   BOOTSTRAP_UPSERT              true 时仅 upsert bootstrap 密钥（re-bootstrap 不抹掉其他配置）
# 可选环境变量:
#   PORT                         服务端口（默认 production=3600，test=3602）
#   SYNC_FORCE                   true 时覆盖已有 env 文件（sync-env 运维任务）
#   OPENAI_API_KEY / OPENAI_EMBEDDING_API_KEY / OPENAI_* / REDIS_PASSWORD
#   TENCENT_SECRET_ID / TENCENT_SECRET_KEY / TENCENT_TMT_*
#   PLATFORM_ADMIN_*
#
# 用法:
#   ENVIRONMENT=production DB_PASSWORD=... JWT_SECRET=... TENANT_SECRET_ENCRYPTION_KEY=... \
#     bash scripts/sync-env-ci.sh
#   pnpm sync-env -- --env production   # 本机 .env.production → 远程（见 scripts/sync-env-remote.sh）

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=lib/log.sh
source "${SCRIPT_DIR}/lib/log.sh"


ENVIRONMENT="${ENVIRONMENT:-production}"
[[ "$ENVIRONMENT" =~ ^(production|test)$ ]] || log_die "ENVIRONMENT 必须是 production 或 test"

[ -n "${DB_PASSWORD:-}" ] || log_die "必须设置 DB_PASSWORD"
[ -n "${JWT_SECRET:-}" ] || log_die "必须设置 JWT_SECRET"
if [ "${BOOTSTRAP_UPSERT:-false}" != "true" ]; then
  [ -n "${TENANT_SECRET_ENCRYPTION_KEY:-}" ] || log_die "必须设置 TENANT_SECRET_ENCRYPTION_KEY"
fi

# shellcheck source=lib/blue-green.sh
source "${SCRIPT_DIR}/lib/blue-green.sh"
bg_load_env "$ENVIRONMENT"

DB_USER="alice"

if [ "$ENVIRONMENT" = "test" ]; then
  DB_NAME="regora_test"
else
  DB_NAME="alice"
fi

target="$BG_SHARED_ENV_FILE"
SYNC_FORCE="${SYNC_FORCE:-false}"
BOOTSTRAP_UPSERT="${BOOTSTRAP_UPSERT:-false}"
PORT="${PORT:-$(bg_slot_port a)}"

_upsert_env_var() {
  local file="$1" key="$2" value="$3"
  local tmp
  tmp="$(mktemp)"
  if [ -f "$file" ]; then
    grep -v "^${key}=" "$file" >"$tmp" || true
  else
    : >"$tmp"
  fi
  printf '%s=%s\n' "$key" "$value" >>"$tmp"
  chmod 600 "$tmp"
  mv "$tmp" "$file"
}

_link_env_to_slots() {
  for slot in a b; do
    local slot_dir
    slot_dir="$(bg_slot_dir "$slot")"
    if [ -d "$slot_dir" ]; then
      ln -sf "$target" "${slot_dir}/.env"
      log_info "链接 ${target} -> ${slot_dir}/.env"
    fi
  done
}

if [ "$BOOTSTRAP_UPSERT" = "true" ]; then
  bg_ensure_state_dir
  if [ -f "$target" ]; then
    log_info "同步 ${target} 中的 bootstrap 密钥..."
  else
    log_info "写入共享 env ${target}..."
    touch "$target"
    chmod 600 "$target"
  fi

  _upsert_env_var "$target" "DATABASE_URL" "postgresql://${DB_USER}:${DB_PASSWORD}@localhost:5432/${DB_NAME}"
  _upsert_env_var "$target" "JWT_SECRET" "$JWT_SECRET"
  _upsert_env_var "$target" "TENANT_SECRET_ENCRYPTION_KEY" "${TENANT_SECRET_ENCRYPTION_KEY:-}"
  _upsert_env_var "$target" "PORT" "$PORT"
  _upsert_env_var "$target" "NODE_ENV" "$ENVIRONMENT"
  _upsert_env_var "$target" "REDIS_HOST" "localhost"
  _upsert_env_var "$target" "REDIS_PORT" "6379"
  if [ -n "${REDIS_PASSWORD:-}" ]; then
    _upsert_env_var "$target" "REDIS_PASSWORD" "$REDIS_PASSWORD"
  fi
  _upsert_env_var "$target" "REDIS_DB" "0"

  append_env_line() {
    local key="$1"
    local value="${2:-}"
    if [ -n "$value" ]; then
      _upsert_env_var "$target" "$key" "$value"
    fi
  }
  append_env_line "OPENAI_API_KEY" "${OPENAI_API_KEY:-}"
  append_env_line "OPENAI_BASE_URL" "${OPENAI_BASE_URL:-}"
  append_env_line "OPENAI_MODEL" "${OPENAI_MODEL:-}"
  append_env_line "OPENAI_EMBEDDING_API_KEY" "${OPENAI_EMBEDDING_API_KEY:-}"
  append_env_line "OPENAI_EMBEDDING_BASE_URL" "${OPENAI_EMBEDDING_BASE_URL:-}"
  append_env_line "OPENAI_EMBEDDING_MODEL" "${OPENAI_EMBEDDING_MODEL:-}"
  append_env_line "OPENAI_EMBEDDING_DIMENSIONS" "${OPENAI_EMBEDDING_DIMENSIONS:-}"
  append_env_line "TENCENT_SECRET_ID" "${TENCENT_SECRET_ID:-}"
  append_env_line "TENCENT_SECRET_KEY" "${TENCENT_SECRET_KEY:-}"
  append_env_line "TENCENT_TMT_REGION" "${TENCENT_TMT_REGION:-}"
  append_env_line "TENCENT_TMT_TARGET_LANG" "${TENCENT_TMT_TARGET_LANG:-}"
  append_env_line "PLATFORM_ADMIN_USERNAME" "${PLATFORM_ADMIN_USERNAME:-}"
  append_env_line "PLATFORM_ADMIN_PASSWORD" "${PLATFORM_ADMIN_PASSWORD:-}"
  append_env_line "PLATFORM_ADMIN_PASSWORD_HASH" "${PLATFORM_ADMIN_PASSWORD_HASH:-}"

  chmod 600 "$target"
  _link_env_to_slots
  log_info "共享 env 已同步"
  exit 0
fi

if [ -f "$target" ] && [ "$SYNC_FORCE" != "true" ]; then
  log_warn "${target} 已存在，跳过覆盖（设置 SYNC_FORCE=true 可强制更新）"
  exit 0
fi

PORT="${PORT:-$(bg_slot_port a)}"

append_env_line() {
  local key="$1"
  local value="${2:-}"
  if [ -n "$value" ]; then
    printf '%s=%s\n' "$key" "$value"
  fi
}

bg_ensure_state_dir
log_info "写入共享 env ${target}..."

{
  printf 'DATABASE_URL=postgresql://%s:%s@localhost:5432/%s\n' "$DB_USER" "$DB_PASSWORD" "$DB_NAME"
  append_env_line "JWT_SECRET" "$JWT_SECRET"
  append_env_line "TENANT_SECRET_ENCRYPTION_KEY" "$TENANT_SECRET_ENCRYPTION_KEY"
  append_env_line "PORT" "$PORT"
  printf 'NODE_ENV=%s\n' "$ENVIRONMENT"
  printf 'REDIS_HOST=localhost\n'
  printf 'REDIS_PORT=6379\n'
  append_env_line "REDIS_PASSWORD" "${REDIS_PASSWORD:-}"
  printf 'REDIS_DB=0\n'
  append_env_line "OPENAI_API_KEY" "${OPENAI_API_KEY:-}"
  append_env_line "OPENAI_BASE_URL" "${OPENAI_BASE_URL:-}"
  append_env_line "OPENAI_MODEL" "${OPENAI_MODEL:-}"
  append_env_line "OPENAI_EMBEDDING_API_KEY" "${OPENAI_EMBEDDING_API_KEY:-}"
  append_env_line "OPENAI_EMBEDDING_BASE_URL" "${OPENAI_EMBEDDING_BASE_URL:-}"
  append_env_line "OPENAI_EMBEDDING_MODEL" "${OPENAI_EMBEDDING_MODEL:-}"
  append_env_line "OPENAI_EMBEDDING_DIMENSIONS" "${OPENAI_EMBEDDING_DIMENSIONS:-}"
  append_env_line "TENCENT_SECRET_ID" "${TENCENT_SECRET_ID:-}"
  append_env_line "TENCENT_SECRET_KEY" "${TENCENT_SECRET_KEY:-}"
  append_env_line "TENCENT_TMT_REGION" "${TENCENT_TMT_REGION:-}"
  append_env_line "TENCENT_TMT_TARGET_LANG" "${TENCENT_TMT_TARGET_LANG:-}"
  append_env_line "PLATFORM_ADMIN_USERNAME" "${PLATFORM_ADMIN_USERNAME:-}"
  append_env_line "PLATFORM_ADMIN_PASSWORD" "${PLATFORM_ADMIN_PASSWORD:-}"
  append_env_line "PLATFORM_ADMIN_PASSWORD_HASH" "${PLATFORM_ADMIN_PASSWORD_HASH:-}"
} > "$target"

chmod 600 "$target"

for slot in a b; do
  slot_dir="$(bg_slot_dir "$slot")"
  if [ -d "$slot_dir" ]; then
    ln -sf "$target" "${slot_dir}/.env"
    log_info "链接 ${target} -> ${slot_dir}/.env"
  fi
done

log_info "共享 env 已写入"

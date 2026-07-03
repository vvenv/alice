#!/bin/bash
# 从 CI Secrets 写入共享 env（/etc/alice/env.production 或 env.test）
#
# 必填环境变量:
#   ENVIRONMENT                  production | test
#   BOOTSTRAP_UPSERT              true 时仅 upsert bootstrap 密钥（re-bootstrap 不抹掉其他配置）
# 可选环境变量:
#   PORT                         服务端口（默认 production=3600，test=3602）
#   SYNC_FORCE                   true 时覆盖已有 env 文件（sync-env 运维任务）
#   OPENAI_API_KEY / OPENAI_BASE_URL / OPENAI_TTS_* / OPENAI_VISION_*
#   HOST / LOG_LEVEL
#
# 用法:
#   ENVIRONMENT=production bash scripts/sync-env-ci.sh
#   pnpm sync-env -- --env production   # 本机 .env.production → 远程（见 scripts/sync-env-remote.sh）

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=lib/log.sh
source "${SCRIPT_DIR}/lib/log.sh"


ENVIRONMENT="${ENVIRONMENT:-production}"
[[ "$ENVIRONMENT" =~ ^(production|test)$ ]] || log_die "ENVIRONMENT 必须是 production 或 test"

# shellcheck source=lib/blue-green.sh
source "${SCRIPT_DIR}/lib/blue-green.sh"
bg_load_env "$ENVIRONMENT"

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

append_env_line() {
  local key="$1"
  local value="${2:-}"
  if [ -n "$value" ]; then
    _upsert_env_var "$target" "$key" "$value"
  fi
}

_write_runtime_env() {
  append_env_line "PORT" "$PORT"
  append_env_line "HOST" "${HOST:-0.0.0.0}"
  append_env_line "LOG_LEVEL" "${LOG_LEVEL:-info}"
  _upsert_env_var "$target" "NODE_ENV" "$ENVIRONMENT"
  append_env_line "OPENAI_API_KEY" "${OPENAI_API_KEY:-}"
  append_env_line "OPENAI_BASE_URL" "${OPENAI_BASE_URL:-}"
  append_env_line "OPENAI_TTS_MODEL" "${OPENAI_TTS_MODEL:-}"
  append_env_line "OPENAI_TTS_VOICE" "${OPENAI_TTS_VOICE:-}"
  append_env_line "OPENAI_VISION_MODEL" "${OPENAI_VISION_MODEL:-}"
}

if [ "$BOOTSTRAP_UPSERT" = "true" ]; then
  bg_ensure_state_dir
  if [ -f "$target" ]; then
    log_info "同步 ${target} 中的 bootstrap 配置..."
  else
    log_info "写入共享 env ${target}..."
    touch "$target"
    chmod 600 "$target"
  fi

  _write_runtime_env
  chmod 600 "$target"
  _link_env_to_slots
  log_info "共享 env 已同步"
  exit 0
fi

if [ -f "$target" ] && [ "$SYNC_FORCE" != "true" ]; then
  log_warn "${target} 已存在，跳过覆盖（设置 SYNC_FORCE=true 可强制更新）"
  exit 0
fi

bg_ensure_state_dir
log_info "写入共享 env ${target}..."

{
  printf 'PORT=%s\n' "$PORT"
  printf 'HOST=%s\n' "${HOST:-0.0.0.0}"
  printf 'LOG_LEVEL=%s\n' "${LOG_LEVEL:-info}"
  printf 'NODE_ENV=%s\n' "$ENVIRONMENT"
  [ -n "${OPENAI_API_KEY:-}" ] && printf 'OPENAI_API_KEY=%s\n' "$OPENAI_API_KEY"
  [ -n "${OPENAI_BASE_URL:-}" ] && printf 'OPENAI_BASE_URL=%s\n' "$OPENAI_BASE_URL"
  [ -n "${OPENAI_TTS_MODEL:-}" ] && printf 'OPENAI_TTS_MODEL=%s\n' "$OPENAI_TTS_MODEL"
  [ -n "${OPENAI_TTS_VOICE:-}" ] && printf 'OPENAI_TTS_VOICE=%s\n' "$OPENAI_TTS_VOICE"
  [ -n "${OPENAI_VISION_MODEL:-}" ] && printf 'OPENAI_VISION_MODEL=%s\n' "$OPENAI_VISION_MODEL"
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

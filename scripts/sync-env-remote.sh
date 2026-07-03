#!/bin/bash
# 从本机 .env.production / .env.test / .env.edge 同步运行时 env 到远程服务器
# 行为与 GitHub Actions「Sync env」一致（主站写共享 env + 可选 PM2 重启；Edge 写 /var/www/regora/.env）
#
# 用法:
#   ./scripts/sync-env-remote.sh                      # production，增量 upsert（默认）
#   ./scripts/sync-env-remote.sh --env test
#   ./scripts/sync-env-remote.sh --env edge
#   ./scripts/sync-env-remote.sh --force              # 全量覆盖共享 env（等同 CI SYNC_FORCE）
#   ./scripts/sync-env-remote.sh --no-restart         # 不同步后重启 PM2
#
# 凭证与密钥：复制 scripts/env.production.example → .env.production（test/edge 同理）

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

# shellcheck source=scripts/lib/release-deploy-config.sh
source "$ROOT/scripts/lib/release-deploy-config.sh"
# shellcheck source=scripts/lib/deploy-env.sh
source "$ROOT/scripts/lib/deploy-env.sh"
# shellcheck source=scripts/lib/deploy-remote.sh
source "$ROOT/scripts/lib/deploy-remote.sh"
# shellcheck source=scripts/lib/log.sh
source "$ROOT/scripts/lib/log.sh"

ENVIRONMENT="production"
UPSERT=1
RESTART_AFTER_SYNC=1
REMOTE_SYNC_DIR=/tmp/regora-sync-env

usage() {
  sed -n '3,14p' "$0"
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --env)
      ENVIRONMENT="$2"
      shift 2
      ;;
    --force) UPSERT=0; shift ;;
    --upsert) UPSERT=1; shift ;;
    --no-restart) RESTART_AFTER_SYNC=0; shift ;;
    --help|-h)
      usage
      exit 0
      ;;
    *)
      deploy_remote_error "未知选项: $1（可用 --env、--upsert、--force、--no-restart）"
      ;;
  esac
done

case "$ENVIRONMENT" in
  production|test|edge) ;;
  *)
    deploy_remote_error "无效环境: ${ENVIRONMENT}（仅支持 production / test / edge）"
    ;;
esac

load_deploy_credentials "$ENVIRONMENT"
deploy_env_clear_placeholder_secrets

_write_quoted_env_file() {
  local dest="$1"
  shift
  : >"$dest"
  chmod 600 "$dest"
  local key value
  for key in "$@"; do
    value="${!key-}"
    [ -n "$value" ] || continue
    printf '%s=%q\n' "$key" "$value" >>"$dest"
  done
}

_sync_main_env() {
  local missing=()
  [ -n "${DB_PASSWORD:-}" ] || missing+=("DB_PASSWORD")
  [ -n "${JWT_SECRET:-}" ] || missing+=("JWT_SECRET")
  if [ "$UPSERT" -eq 0 ] && [ -z "${TENANT_SECRET_ENCRYPTION_KEY:-}" ]; then
    missing+=("TENANT_SECRET_ENCRYPTION_KEY")
  fi
  if [ "${#missing[@]}" -gt 0 ]; then
    deploy_remote_error "缺少必填项: ${missing[*]}。请在 $(deploy_env_file_for "$ROOT" "$ENVIRONMENT") 中配置"
  fi

  export ENVIRONMENT
  if [ "$UPSERT" -eq 1 ]; then
    export BOOTSTRAP_UPSERT=true
    export SYNC_FORCE=true
  else
    unset BOOTSTRAP_UPSERT
    export SYNC_FORCE=true
  fi
  export RESTART_AFTER_SYNC

  local sync_vars
  sync_vars="$(mktemp)"
  _write_quoted_env_file "$sync_vars" \
    ENVIRONMENT DB_PASSWORD JWT_SECRET TENANT_SECRET_ENCRYPTION_KEY PORT \
    SYNC_FORCE BOOTSTRAP_UPSERT \
    OPENAI_API_KEY OPENAI_BASE_URL OPENAI_MODEL \
    OPENAI_EMBEDDING_API_KEY OPENAI_EMBEDDING_BASE_URL OPENAI_EMBEDDING_MODEL OPENAI_EMBEDDING_DIMENSIONS \
    REDIS_PASSWORD \
    PLATFORM_ADMIN_USERNAME PLATFORM_ADMIN_PASSWORD PLATFORM_ADMIN_PASSWORD_HASH \
    TENCENT_SECRET_ID TENCENT_SECRET_KEY TENCENT_TMT_REGION TENCENT_TMT_TARGET_LANG

  deploy_remote_info "目标: ${DEPLOY_SSH_USER}@${DEPLOY_HOST} (${ENVIRONMENT})"
  if [ "$UPSERT" -eq 1 ]; then
    deploy_remote_info "模式: 增量 upsert（保留服务器上未列出的 env 项）"
  else
    deploy_remote_info "模式: 全量覆盖（SYNC_FORCE）"
  fi

  _run_ssh "rm -rf '${REMOTE_SYNC_DIR}' && mkdir -p '${REMOTE_SYNC_DIR}/scripts/lib'"
  _run_scp "$sync_vars" "${DEPLOY_SSH_USER}@${DEPLOY_HOST}:${REMOTE_SYNC_DIR}/sync-vars.env"
  _run_scp "$ROOT/scripts/sync-env-ci.sh" "${DEPLOY_SSH_USER}@${DEPLOY_HOST}:${REMOTE_SYNC_DIR}/scripts/sync-env-ci.sh"
  _run_scp "$ROOT/scripts/sync-env-remote-run.sh" "${DEPLOY_SSH_USER}@${DEPLOY_HOST}:${REMOTE_SYNC_DIR}/run-sync-env.sh"
  _run_scp "$ROOT/scripts/lib/blue-green.sh" "${DEPLOY_SSH_USER}@${DEPLOY_HOST}:${REMOTE_SYNC_DIR}/scripts/lib/blue-green.sh"
  _run_scp "$ROOT/scripts/lib/log.sh" "${DEPLOY_SSH_USER}@${DEPLOY_HOST}:${REMOTE_SYNC_DIR}/scripts/lib/log.sh"
  rm -f "$sync_vars"

  _run_ssh "set -euo pipefail
chmod +x '${REMOTE_SYNC_DIR}/run-sync-env.sh'
bash '${REMOTE_SYNC_DIR}/run-sync-env.sh' '${REMOTE_SYNC_DIR}' '${ENVIRONMENT}' '${RESTART_AFTER_SYNC}'"

  deploy_remote_info "共享 env 已同步到 ${ENVIRONMENT}"
}

_sync_edge_env() {
  local env_file runtime_env
  env_file="$(deploy_env_file_for "$ROOT" edge)"
  [ -f "$env_file" ] || deploy_remote_error "未找到 ${env_file}"

  runtime_env="$(mktemp)"
  deploy_env_write_runtime_file "$env_file" "$runtime_env"

  deploy_remote_info "目标: ${DEPLOY_SSH_USER}@${DEPLOY_HOST} (edge)"

  _run_ssh "rm -rf '${REMOTE_SYNC_DIR}' && mkdir -p '${REMOTE_SYNC_DIR}/scripts/lib'"
  _run_scp "$runtime_env" "${DEPLOY_SSH_USER}@${DEPLOY_HOST}:${REMOTE_SYNC_DIR}/edge.env"
  _run_scp "$ROOT/scripts/lib/edge-deploy.sh" "${DEPLOY_SSH_USER}@${DEPLOY_HOST}:${REMOTE_SYNC_DIR}/scripts/lib/edge-deploy.sh"
  _run_scp "$ROOT/scripts/sync-env-remote-edge-run.sh" "${DEPLOY_SSH_USER}@${DEPLOY_HOST}:${REMOTE_SYNC_DIR}/run-sync-env-edge.sh"
  rm -f "$runtime_env"

  _run_ssh "set -euo pipefail
chmod +x '${REMOTE_SYNC_DIR}/run-sync-env-edge.sh'
bash '${REMOTE_SYNC_DIR}/run-sync-env-edge.sh' '${REMOTE_SYNC_DIR}' '${EDGE_APP_DIR}'"

  deploy_remote_info "Edge env 已同步"
}

if [ "$ENVIRONMENT" = "edge" ]; then
  _sync_edge_env
else
  _sync_main_env
fi

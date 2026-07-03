# 主应用本地 SSH bootstrap（与 .github/actions/bootstrap-server 行为一致）
# 用法:
#   ROOT=/path/to/repo source scripts/lib/bootstrap-remote.sh
#   bootstrap_release_server /path/to/alice-v1.0.0.tar.gz v1.0.0 production

if [ -z "${ROOT:-}" ]; then
  ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
fi

# shellcheck source=scripts/lib/deploy-remote.sh
source "$ROOT/scripts/lib/deploy-remote.sh"
# shellcheck source=scripts/lib/log.sh
source "$ROOT/scripts/lib/log.sh"

bootstrap_remote_info() { log_info "$@"; }

_bootstrap_env_append() {
  local key="$1"
  local value="${2:-}"
  if [ -n "$value" ]; then
    printf '%s=%s\n' "$key" "$value"
  fi
}

load_bootstrap_secrets() {
  local environment="${1:-production}"
  load_deploy_credentials "$environment"
}

_write_bootstrap_env_file() {
  local path="$1"
  local environment="$2"
  local version="$3"
  local port="$4"
  local domain="$5"
  local ssl_email="$6"

  {
    printf 'ENVIRONMENT=%s\n' "$environment"
    printf 'DEPLOY_VERSION=%s\n' "$version"
    printf 'PORT=%s\n' "$port"
    printf 'DOMAIN=%s\n' "$domain"
    printf 'SSL_EMAIL=%s\n' "$ssl_email"
    _bootstrap_env_append "HOST" "${HOST:-0.0.0.0}"
    _bootstrap_env_append "LOG_LEVEL" "${LOG_LEVEL:-info}"
    _bootstrap_env_append "OPENAI_API_KEY" "${OPENAI_API_KEY:-}"
    _bootstrap_env_append "OPENAI_BASE_URL" "${OPENAI_BASE_URL:-}"
    _bootstrap_env_append "OPENAI_TTS_MODEL" "${OPENAI_TTS_MODEL:-}"
    _bootstrap_env_append "OPENAI_TTS_VOICE" "${OPENAI_TTS_VOICE:-}"
    _bootstrap_env_append "OPENAI_VISION_MODEL" "${OPENAI_VISION_MODEL:-}"
  } >"$path"
  chmod 600 "$path"
}

bootstrap_release_server() {
  local tarball="$1"
  local version="$2"
  local environment="${3:-production}"
  local port="${4:-}"
  local domain="${5:-}"
  local ssl_email="${6:-}"

  if [ ! -f "$tarball" ]; then
    deploy_remote_error "找不到 tarball: $tarball"
  fi

  if [ "$environment" != "production" ] && [ "$environment" != "test" ]; then
    deploy_remote_error "无效环境: ${environment}（仅支持 production / test）"
  fi

  load_bootstrap_secrets "$environment"

  local tarball_name remote_dir health_dirs local_env
  tarball_name="$(basename "$tarball")"
  remote_dir="$BOOTSTRAP_REMOTE_STAGING_DIR"
  health_dirs="$HEALTH_CHECK_SLOT_DIRS"
  local_env="$(mktemp)"

  _write_bootstrap_env_file "$local_env" "$environment" "$version" "$port" "$domain" "$ssl_email"

  bootstrap_remote_info "目标: ${DEPLOY_SSH_USER}@${DEPLOY_HOST} (${environment})"
  bootstrap_remote_info "版本: $version"
  bootstrap_remote_info "上传 ${tarball_name} 与 bootstrap 脚本..."

  _run_ssh "rm -rf '$remote_dir' && mkdir -p '$remote_dir/scripts/lib'"

  _run_scp "$tarball" "${DEPLOY_SSH_USER}@${DEPLOY_HOST}:${remote_dir}/${tarball_name}"
  _run_scp "$ROOT/scripts/bootstrap-ci.sh" "${DEPLOY_SSH_USER}@${DEPLOY_HOST}:${remote_dir}/scripts/bootstrap-ci.sh"
  _run_scp "$ROOT/scripts/sync-env-ci.sh" "${DEPLOY_SSH_USER}@${DEPLOY_HOST}:${remote_dir}/scripts/sync-env-ci.sh"
  _run_scp "$ROOT/scripts/lib/blue-green.sh" "${DEPLOY_SSH_USER}@${DEPLOY_HOST}:${remote_dir}/scripts/lib/blue-green.sh"
  _run_scp "$ROOT/scripts/lib/log.sh" "${DEPLOY_SSH_USER}@${DEPLOY_HOST}:${remote_dir}/scripts/lib/log.sh"
  _run_scp "$local_env" "${DEPLOY_SSH_USER}@${DEPLOY_HOST}:${remote_dir}/bootstrap.env"
  rm -f "$local_env"

  bootstrap_remote_info "执行 bootstrap（可能需要数分钟）..."
  _run_ssh "set -euo pipefail
BOOTSTRAP_DIR='${remote_dir}'
ARCHIVE=\"\${BOOTSTRAP_DIR}/${tarball_name}\"
SCRIPT=\"\${BOOTSTRAP_DIR}/scripts/bootstrap-ci.sh\"
if [ ! -f \"\$ARCHIVE\" ]; then
  echo \"Archive not found: \$ARCHIVE\"
  ls -laR \"\$BOOTSTRAP_DIR\" || true
  exit 1
fi
if [ ! -f \"\$SCRIPT\" ]; then
  echo \"Bootstrap script not found: \$SCRIPT\"
  ls -laR \"\$BOOTSTRAP_DIR\" || true
  exit 1
fi
set -a
# shellcheck source=/dev/null
. \"\${BOOTSTRAP_DIR}/bootstrap.env\"
set +a
chmod +x \"\$SCRIPT\" \"\${BOOTSTRAP_DIR}/scripts/sync-env-ci.sh\"
bash \"\$SCRIPT\" \"\$ARCHIVE\"
rm -rf '${remote_dir}'"

  bootstrap_remote_info "健康检查..."
  _run_ssh "set -euo pipefail
HEALTH_SCRIPT=''
for dir in ${health_dirs}; do
  if [ -f \"\${dir}/scripts/health-check.sh\" ]; then
    HEALTH_SCRIPT=\"\${dir}/scripts/health-check.sh\"
    break
  fi
done
if [ -z \"\$HEALTH_SCRIPT\" ]; then
  PORT=3600
  [ '${environment}' = 'test' ] && PORT=3602
  curl -fsS \"http://127.0.0.1:\${PORT}/health\"
  exit \$?
fi
chmod +x \"\$HEALTH_SCRIPT\"
if ! bash \"\$HEALTH_SCRIPT\" --env '${environment}' --attempts 30 --interval 3; then
  echo '--- PM2 diagnostics ---'
  pm2 list || true
  pm2 logs alice-a --nostream --lines 40 2>/dev/null || true
  pm2 logs alice-b --nostream --lines 20 2>/dev/null || true
  pm2 logs alice-test-a --nostream --lines 20 2>/dev/null || true
  exit 1
fi"

  bootstrap_remote_info "Bootstrap 完成: ${version} → ${environment}"
}

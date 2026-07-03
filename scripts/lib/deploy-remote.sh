# 本地 SSH 部署（与 .github/actions/deploy-to-server 行为一致）
# 用法: ROOT=/path/to/repo source scripts/lib/deploy-remote.sh
#       load_deploy_credentials production
#       deploy_release_tarball "${PROJECT_SLUG}-v1.0.0.tar.gz" v1.0.0 production

if [ -z "${ROOT:-}" ]; then
  ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
fi

# shellcheck source=scripts/lib/release-deploy-config.sh
source "$ROOT/scripts/lib/release-deploy-config.sh"
# shellcheck source=scripts/lib/edge-deploy.sh
source "$ROOT/scripts/lib/edge-deploy.sh"
# shellcheck source=scripts/lib/deploy-env.sh
source "$ROOT/scripts/lib/deploy-env.sh"
# shellcheck source=scripts/lib/log.sh
source "$ROOT/scripts/lib/log.sh"

deploy_remote_info()  { log_info "$@"; }
deploy_remote_error() { log_die "$@"; }

_deploy_override_var() {
  local suffix="$1"
  eval "echo \"\${${DEPLOY_OVERRIDE_PREFIX}_DEPLOY_${suffix}:-}\""
}

_ssh_auth_failure_in_stderr() {
  local stderr_file="$1"
  grep -qiE 'permission denied.*(publickey|password|keyboard|please try again)|authentication fail' "$stderr_file"
}

# 加载目标环境 dotenv（.env.production / .env.test / .env.edge）
# 凭证统一使用 DEPLOY_HOST / DEPLOY_SSH_USER / DEPLOY_SSH_PASSWORD
load_deploy_credentials() {
  local environment="${1:-production}"

  load_deploy_env "$ROOT" "$environment"

  local override_host override_user override_password
  override_host="$(_deploy_override_var HOST)"
  override_user="$(_deploy_override_var SSH_USER)"
  override_password="$(_deploy_override_var SSH_PASSWORD)"

  DEPLOY_ENVIRONMENT="$environment"
  DEPLOY_HOST="${override_host:-${DEPLOY_HOST:-}}"
  DEPLOY_SSH_USER="${override_user:-${DEPLOY_SSH_USER:-root}}"
  DEPLOY_SSH_PASSWORD="${override_password:-${DEPLOY_SSH_PASSWORD:-}}"

  if [ -z "$DEPLOY_HOST" ]; then
    local env_file
    env_file="$(deploy_env_file_for "$ROOT" "$environment")"
    if edge_is_valid_environment "$environment"; then
      deploy_remote_error "未配置 Edge SSH。复制 packages/server/scripts/harvest-edge.env.example 为 .env.edge，设置 DEPLOY_HOST / DEPLOY_SSH_USER / DEPLOY_SSH_PASSWORD"
    fi
    deploy_remote_error "未配置 SSH 主机。复制 scripts/env.${environment}.example 为 ${env_file}，设置 DEPLOY_HOST / DEPLOY_SSH_USER / DEPLOY_SSH_PASSWORD"
  fi
}

_ssh_common_opts=(-o StrictHostKeyChecking=accept-new -o ConnectTimeout=15 -o TCPKeepAlive=yes -o ServerAliveInterval=30 -o ServerAliveCountMax=3)

_require_sshpass() {
  if ! command -v sshpass >/dev/null 2>&1; then
    deploy_remote_error "已配置 SSH 密码但未安装 sshpass。请 brew install sshpass，或改用 SSH 密钥并留空密码变量"
  fi
}

_ssh_auth_failure_hint() {
  deploy_remote_error "SSH 认证失败: ${DEPLOY_SSH_USER}@${DEPLOY_HOST}

请检查对应环境文件（.env.production / .env.test / .env.edge）中的 DEPLOY_SSH_PASSWORD 是否正确。
也可手动验证:
  ssh ${DEPLOY_SSH_USER}@${DEPLOY_HOST}
若已配置 SSH 密钥，可删除或注释 DEPLOY_SSH_PASSWORD（脚本会优先使用密钥）。"
}

_ssh_try_key() {
  local mode="$1"
  local stderr_file="$2"
  shift 2

  if [ "$mode" = "scp" ]; then
    scp "${_ssh_common_opts[@]}" -o BatchMode=yes "$@" 2>"$stderr_file"
    return $?
  fi

  local remote_cmd="$1"
  ssh "${_ssh_common_opts[@]}" -o BatchMode=yes \
    "${DEPLOY_SSH_USER}@${DEPLOY_HOST}" "$remote_cmd" 2>"$stderr_file"
}

_ssh_try_password() {
  local mode="$1"
  local stderr_file="$2"
  shift 2

  _require_sshpass
  if [ "$mode" = "scp" ]; then
    SSHPASS="$DEPLOY_SSH_PASSWORD" sshpass -e scp \
      "${_ssh_common_opts[@]}" \
      -o PreferredAuthentications=password \
      -o PubkeyAuthentication=no \
      "$@" 2>"$stderr_file"
    return $?
  fi

  local remote_cmd="$1"
  SSHPASS="$DEPLOY_SSH_PASSWORD" sshpass -e ssh \
    "${_ssh_common_opts[@]}" \
    -o PreferredAuthentications=password \
    -o PubkeyAuthentication=no \
    "${DEPLOY_SSH_USER}@${DEPLOY_HOST}" "$remote_cmd" 2>"$stderr_file"
}

_run_scp() {
  local stderr_file rc
  stderr_file="$(mktemp)"

  if _ssh_try_key scp "$stderr_file" "$@"; then
    rm -f "$stderr_file"
    return 0
  fi
  rc=$?
  if [ "$rc" -eq 255 ] || _ssh_auth_failure_in_stderr "$stderr_file"; then
    if [ -n "$DEPLOY_SSH_PASSWORD" ] && _ssh_try_password scp "$stderr_file" "$@"; then
      rm -f "$stderr_file"
      return 0
    fi
    if [ "$rc" -eq 255 ] || _ssh_auth_failure_in_stderr "$stderr_file"; then
      rm -f "$stderr_file"
      _ssh_auth_failure_hint
    fi
  fi
  cat "$stderr_file" >&2
  rm -f "$stderr_file"
  exit "$rc"
}

_run_ssh() {
  local remote_cmd="$1"
  local stderr_file rc
  stderr_file="$(mktemp)"

  if _ssh_try_key ssh "$stderr_file" "$remote_cmd"; then
    rm -f "$stderr_file"
    return 0
  fi
  rc=$?
  if [ "$rc" -eq 255 ] || _ssh_auth_failure_in_stderr "$stderr_file"; then
    if [ -n "$DEPLOY_SSH_PASSWORD" ] && _ssh_try_password ssh "$stderr_file" "$remote_cmd"; then
      rm -f "$stderr_file"
      return 0
    fi
    if [ "$rc" -eq 255 ] || _ssh_auth_failure_in_stderr "$stderr_file"; then
      rm -f "$stderr_file"
      _ssh_auth_failure_hint
    fi
  fi
  cat "$stderr_file" >&2
  rm -f "$stderr_file"
  exit "$rc"
}

deploy_release_tarball() {
  local tarball="$1"
  local version="$2"
  local environment="${3:-production}"

  if [ ! -f "$tarball" ]; then
    deploy_remote_error "找不到 tarball: $tarball"
  fi

  if [ "$environment" != "production" ] && [ "$environment" != "test" ] && [ "$environment" != "edge" ]; then
    deploy_remote_error "无效环境: ${environment}（仅支持 production / test / edge）"
  fi

  if [ "$environment" = "edge" ]; then
    # shellcheck source=scripts/lib/edge-remote.sh
    source "$ROOT/scripts/lib/edge-remote.sh"
    deploy_edge_tarball "$tarball" "$version"
    return
  fi

  load_deploy_credentials "$environment"

  local tarball_name remote_dir health_dirs
  tarball_name="$(basename "$tarball")"
  remote_dir="$REMOTE_STAGING_DIR"
  health_dirs="$HEALTH_CHECK_SLOT_DIRS"

  deploy_remote_info "目标: ${DEPLOY_SSH_USER}@${DEPLOY_HOST} (${environment})"
  deploy_remote_info "上传 ${tarball_name} 与部署脚本..."

  _run_ssh "rm -rf '$remote_dir' && mkdir -p '$remote_dir/scripts/lib'"

  _run_scp "$tarball" "${DEPLOY_SSH_USER}@${DEPLOY_HOST}:${remote_dir}/${tarball_name}"
  _run_scp "$ROOT/scripts/deploy-local-archive.sh" "${DEPLOY_SSH_USER}@${DEPLOY_HOST}:${remote_dir}/scripts/deploy-local-archive.sh"
  _run_scp "$ROOT/scripts/health-check.sh" "${DEPLOY_SSH_USER}@${DEPLOY_HOST}:${remote_dir}/scripts/health-check.sh"
  _run_scp "$ROOT/scripts/resync-nginx-slot.sh" "${DEPLOY_SSH_USER}@${DEPLOY_HOST}:${remote_dir}/scripts/resync-nginx-slot.sh"
  _run_scp "$ROOT/scripts/lib/blue-green.sh" "${DEPLOY_SSH_USER}@${DEPLOY_HOST}:${remote_dir}/scripts/lib/blue-green.sh"
  _run_scp "$ROOT/scripts/lib/log.sh" "${DEPLOY_SSH_USER}@${DEPLOY_HOST}:${remote_dir}/scripts/lib/log.sh"

  deploy_remote_info "执行蓝绿部署..."
  _run_ssh "set -euo pipefail
ARCHIVE='${remote_dir}/${tarball_name}'
SCRIPT='${remote_dir}/scripts/deploy-local-archive.sh'
chmod +x \"\$SCRIPT\"
bash \"\$SCRIPT\" \"\$ARCHIVE\" --env '${environment}' --version '${version}'
rm -rf '${remote_dir}'"

  deploy_remote_info "健康检查..."
  _run_ssh "set -euo pipefail
HEALTH_SCRIPT=''
for dir in ${health_dirs}; do
  if [ -f \"\${dir}/scripts/health-check.sh\" ]; then
    HEALTH_SCRIPT=\"\${dir}/scripts/health-check.sh\"
    break
  fi
done
if [ -z \"\$HEALTH_SCRIPT\" ]; then
  echo 'health-check.sh not found'
  exit 1
fi
chmod +x \"\$HEALTH_SCRIPT\"
bash \"\$HEALTH_SCRIPT\" --env '${environment}' --attempts 10 --interval 3"

  deploy_remote_info "部署完成: ${version} → ${environment}"
}

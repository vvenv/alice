# 本地 SSH 部署 — Harvest Edge（圣保罗采集节点）
# 用法: ROOT=/path/to/repo source scripts/lib/edge-remote.sh
#       deploy_edge_tarball regora-v1.0.0.tar.gz v1.0.0

if [ -z "${ROOT:-}" ]; then
  ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
fi

# shellcheck source=scripts/lib/deploy-remote.sh
source "$ROOT/scripts/lib/deploy-remote.sh"
# shellcheck source=scripts/lib/edge-deploy.sh
source "$ROOT/scripts/lib/edge-deploy.sh"

load_edge_deploy_credentials() {
  load_deploy_credentials "edge"
}

deploy_edge_tarball() {
  local tarball="$1"
  local version="$2"

  [ -f "$tarball" ] || deploy_remote_error "找不到 tarball: $tarball"

  load_edge_deploy_credentials

  local tarball_name remote_dir
  tarball_name="$(basename "$tarball")"
  remote_dir="$EDGE_REMOTE_STAGING_DIR"

  deploy_remote_info "Edge 目标: ${DEPLOY_SSH_USER}@${DEPLOY_HOST}"
  deploy_remote_info "上传 ${tarball_name}..."

  _run_ssh "rm -rf '$remote_dir' && mkdir -p '$remote_dir/scripts/lib'"
  _run_scp "$tarball" "${DEPLOY_SSH_USER}@${DEPLOY_HOST}:${remote_dir}/${tarball_name}"
  _run_scp "$ROOT/scripts/deploy-edge-archive.sh" "${DEPLOY_SSH_USER}@${DEPLOY_HOST}:${remote_dir}/scripts/deploy-edge-archive.sh"
  _run_scp "$ROOT/scripts/lib/edge-deploy.sh" "${DEPLOY_SSH_USER}@${DEPLOY_HOST}:${remote_dir}/scripts/lib/edge-deploy.sh"
  _run_scp "$ROOT/scripts/lib/log.sh" "${DEPLOY_SSH_USER}@${DEPLOY_HOST}:${remote_dir}/scripts/lib/log.sh"

  deploy_remote_info "执行 Edge 部署..."
  _run_ssh "set -euo pipefail
chmod +x '${remote_dir}/scripts/deploy-edge-archive.sh'
bash '${remote_dir}/scripts/deploy-edge-archive.sh' '${remote_dir}/${tarball_name}' --version '${version}'
rm -rf '${remote_dir}'"

  deploy_remote_info "Edge 健康检查..."
  _run_ssh "set -euo pipefail
APP_DIR='$(edge_resolve_app_dir)'
bash \"\${APP_DIR}/scripts/health-check-edge.sh\""

  deploy_remote_info "Edge 部署完成: ${version}"
}

bootstrap_edge_server() {
  local tarball="$1"
  local version="$2"

  [ -f "$tarball" ] || deploy_remote_error "找不到 tarball: $tarball"

  load_edge_deploy_credentials

  local edge_env="$ROOT/.env.edge"
  if [ ! -f "$edge_env" ]; then
    deploy_remote_error "未找到 .env.edge。复制 packages/server/scripts/harvest-edge.env.example 为仓库根 .env.edge 并填入主库 DATABASE_URL"
  fi

  local edge_runtime_env
  edge_runtime_env="$(mktemp)"
  deploy_env_write_runtime_file "$edge_env" "$edge_runtime_env"

  local tarball_name remote_dir
  tarball_name="$(basename "$tarball")"
  remote_dir="$EDGE_BOOTSTRAP_STAGING_DIR"

  deploy_remote_info "Edge Bootstrap: ${DEPLOY_SSH_USER}@${DEPLOY_HOST}"
  _run_ssh "rm -rf '$remote_dir' && mkdir -p '$remote_dir/scripts/lib'"
  _run_scp "$tarball" "${DEPLOY_SSH_USER}@${DEPLOY_HOST}:${remote_dir}/${tarball_name}"
  _run_scp "$ROOT/scripts/bootstrap-edge-ci.sh" "${DEPLOY_SSH_USER}@${DEPLOY_HOST}:${remote_dir}/scripts/bootstrap-edge-ci.sh"
  _run_scp "$ROOT/scripts/lib/edge-deploy.sh" "${DEPLOY_SSH_USER}@${DEPLOY_HOST}:${remote_dir}/scripts/lib/edge-deploy.sh"
  _run_scp "$ROOT/scripts/lib/log.sh" "${DEPLOY_SSH_USER}@${DEPLOY_HOST}:${remote_dir}/scripts/lib/log.sh"
  _run_scp "$edge_runtime_env" "${DEPLOY_SSH_USER}@${DEPLOY_HOST}:${remote_dir}/edge.env"
  rm -f "$edge_runtime_env"

  _run_ssh "set -euo pipefail
chmod +x '${remote_dir}/scripts/bootstrap-edge-ci.sh'
bash '${remote_dir}/scripts/bootstrap-edge-ci.sh' '${remote_dir}/${tarball_name}' --version '${version}' --env-file '${remote_dir}/edge.env'
rm -rf '${remote_dir}'"

  deploy_remote_info "Edge Bootstrap 完成: ${version}"
}

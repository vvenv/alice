#!/bin/bash
# 将 release tarball SCP 到服务器并执行蓝绿部署（与 CI deploy-to-server 相同）
#
# 用法:
#   ./scripts/deploy-remote.sh ${PROJECT_SLUG}-v1.0.0.tar.gz
#   ./scripts/deploy-remote.sh ${PROJECT_SLUG}-v1.0.0.tar.gz --env test
#   ./scripts/deploy-remote.sh ${PROJECT_SLUG}-v1.0.0.tar.gz --env edge
#   ./scripts/deploy-remote.sh ${PROJECT_SLUG}-v1.0.0.tar.gz --env test,production   # 一次部署多个环境
#   ./scripts/deploy-remote.sh ${PROJECT_SLUG}-v1.0.0.tar.gz --env test --env edge   # 重复 --env 等价
#
# 多环境按给定顺序串行部署，前序环境失败则中止（fail-fast）。
# 凭证：复制 scripts/env.production.example → .env.production（test/edge 同理）

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

# shellcheck source=scripts/lib/deploy-remote.sh
source "$ROOT/scripts/lib/deploy-remote.sh"

TARBALL=""
VERSION=""
ENVS=()

# 解析 --env（支持逗号分隔或重复 --env），去重并保持顺序
_add_envs() {
  local input="$1"
  local IFS=','
  local -a parts
  read -ra parts <<<"$input"
  local item found i
  for item in "${parts[@]}"; do
    item="${item// /}"
    # 注意：用 if 而非 [ ... ] && continue，避免 set -e 在短路失败时误退出
    if [ -z "$item" ]; then
      continue
    fi
    found=0
    for ((i = 0; i < ${#ENVS[@]}; i++)); do
      if [ "${ENVS[$i]}" = "$item" ]; then
        found=1
        break
      fi
    done
    if [ "$found" -eq 0 ]; then
      ENVS+=("$item")
    fi
  done
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --env)
      _add_envs "$2"
      shift 2
      ;;
    --env=*)
      _add_envs "${1#--env=}"
      shift
      ;;
    --version)
      VERSION="$2"
      shift 2
      ;;
    --help|-h)
      sed -n '3,12p' "$0"
      exit 0
      ;;
    -*)
      deploy_remote_error "未知选项: $1"
      ;;
    *)
      if [ -n "$TARBALL" ]; then
        deploy_remote_error "多余的参数: $1"
      fi
      TARBALL="$1"
      shift
      ;;
  esac
done

if [ -z "$TARBALL" ]; then
  deploy_remote_error "请指定 tarball 路径"
fi

if [[ "$TARBALL" != /* ]]; then
  TARBALL="$ROOT/$TARBALL"
fi

if [ -z "$VERSION" ]; then
  VERSION="$(basename "$TARBALL" .tar.gz)"
  VERSION="${VERSION#${PROJECT_SLUG}-}"
  if [[ "$VERSION" != v* ]]; then
    VERSION="v${VERSION}"
  fi
fi

# 未指定环境时默认 production
if [ "${#ENVS[@]}" -eq 0 ]; then
  ENVS=("production")
fi

# 部署前统一校验所有环境（fail fast：任一无效立即中止，避免部署到一半才失败）
for _env in "${ENVS[@]}"; do
  case "$_env" in
    production|test|edge) ;;
    *) deploy_remote_error "无效环境: ${_env}（仅支持 production / test / edge）" ;;
  esac
done

if [ "${#ENVS[@]}" -eq 1 ]; then
  deploy_release_tarball "$TARBALL" "$VERSION" "${ENVS[0]}"
else
  deploy_remote_info "多环境部署: ${ENVS[*]}（共 ${#ENVS[@]} 个环境，串行 fail-fast）"
  for _env in "${ENVS[@]}"; do
    deploy_remote_info "── 部署到 ${_env} ──"
    deploy_release_tarball "$TARBALL" "$VERSION" "$_env"
  done
  deploy_remote_info "全部部署完成: ${VERSION} → ${ENVS[*]}"
fi

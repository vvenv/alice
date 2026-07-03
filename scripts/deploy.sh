#!/bin/bash
# 直接构建并部署「当前（默认）或指定」版本到服务器，不做版本 bump / commit / tag。
# 适用于：重新部署当前版本、热修复后直推、CI 不可用时快速上线。
#
# 用法:
#   ./scripts/deploy.sh                          # 交互式选择版本 / 环境
#   ./scripts/deploy.sh v1.2.3                   # 部署指定版本（非交互）
#   ./scripts/deploy.sh --env test              # 部署到测试环境
#   ./scripts/deploy.sh --env test,production   # 一次部署多个环境（串行 fail-fast）
#   ./scripts/deploy.sh v1.2.3 --reuse           # 复用已存在的 tarball，跳过构建
#   ./scripts/deploy.sh --via-docker             # 强制使用 Docker (linux/amd64) 构建
#
# 与 release.sh 区别：本脚本只「构建 + 部署」，不修改版本号、不提交、不打 tag、不 push。

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

VERSION_ROOT="$ROOT"
# shellcheck source=scripts/lib/version.sh
source "$ROOT/scripts/lib/version.sh"
# shellcheck source=scripts/lib/release-deploy-config.sh
source "$ROOT/scripts/lib/release-deploy-config.sh"
# shellcheck source=scripts/lib/log.sh
source "$ROOT/scripts/lib/log.sh"


VERSION_ARG=""
DEPLOY_ENV="production"
VIA_DOCKER=0
REUSE=0
ENV_PRESET=0
REUSE_PRESET=0
INTERACTIVE=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --env)
      DEPLOY_ENV="$2"
      ENV_PRESET=1
      shift 2
      ;;
    --via-docker) VIA_DOCKER=1; shift ;;
    --reuse) REUSE=1; REUSE_PRESET=1; shift ;;
    --help|-h)
      sed -n '3,16p' "$0"
      exit 0
      ;;
    -*)
      log_die "未知选项: $1（可用 --env、--via-docker、--reuse）"
      ;;
    *)
      if [ -n "$VERSION_ARG" ]; then
        log_die "多余的参数: $1"
      fi
      VERSION_ARG="$1"
      shift
      ;;
  esac
done

if [ -z "$VERSION_ARG" ] && [ -t 0 ]; then
  INTERACTIVE=1
fi

prompt_confirm() {
  local message="$1"
  local default="${2:-y}"

  if [ ! -t 0 ]; then
    [ "$default" = "y" ]
    return
  fi

  local hint="Y/n"
  if [ "$default" = "n" ]; then
    hint="y/N"
  fi

  local answer
  read -r -p "$message [$hint]: " answer </dev/tty
  if [ -z "$answer" ]; then
    answer="$default"
  fi

  case "$answer" in
    [Yy]|[Yy][Ee][Ss]) return 0 ;;
    *) return 1 ;;
  esac
}

run_interactive() {
  # shellcheck source=scripts/lib/prompt-menu.sh
  source "$ROOT/scripts/lib/prompt-menu.sh"

  local current choice custom_version
  current="$(get_current_version)"

  log_info "当前版本: $current"
  echo ""

  choice="$(prompt_menu "请选择要部署的版本" --default=1 \
    "current:部署当前版本 v${current}" \
    "custom:指定其他版本号")"

  if [ "$choice" = "custom" ]; then
    while true; do
      read -r -p "请输入版本号 (如 1.2.3 或 v1.2.3): " custom_version </dev/tty
      custom_version="${custom_version// /}"
      if [ -z "$custom_version" ]; then
        echo "版本号不能为空" >&2
        continue
      fi
      VERSION="${custom_version#v}"
      break
    done
  else
    VERSION="$current"
  fi

  if [ "$ENV_PRESET" -eq 0 ]; then
    DEPLOY_ENV="$(prompt_multi_menu "部署环境（空格多选，回车确认）" --default=1 \
      "production:生产环境" \
      "test:测试环境""
  fi

  local candidate_tarball="$ROOT/${PROJECT_SLUG}-v${VERSION}.tar.gz"
  if [ "$REUSE_PRESET" -eq 0 ] && [ -f "$candidate_tarball" ]; then
    local reuse_choice
    reuse_choice="$(prompt_menu "检测到已存在的构建包，是否复用？" --default=1 \
      "reuse:复用已有 tarball（更快）" \
      "rebuild:重新构建")"
    if [ "$reuse_choice" = "reuse" ]; then
      REUSE=1
    fi
  fi

  TAG="v${VERSION}"
  echo ""
  log_info "部署预览"
  log_info "  版本: ${TAG}"
  log_info "  目标: ${DEPLOY_ENV}"
  if [ "$REUSE" -eq 1 ]; then
    log_info "  构建: 复用已有 tarball"
  else
    log_info "  构建: 重新构建"
  fi
  echo ""

  if ! prompt_confirm "确认开始部署？" "y"; then
    log_info "已取消"
    exit 0
  fi
}

if [ "$INTERACTIVE" -eq 1 ]; then
  run_interactive
elif [ -n "$VERSION_ARG" ]; then
  VERSION="${VERSION_ARG#v}"
else
  VERSION="$(get_current_version)"
fi

TAG="v${VERSION}"
TARBALL="$ROOT/${PROJECT_SLUG}-${TAG}.tar.gz"

if [ "$INTERACTIVE" -eq 0 ]; then
  log_info "版本: ${TAG}"
  log_info "目标: ${DEPLOY_ENV}"
fi

chmod +x scripts/build-release-package.sh scripts/deploy-remote.sh

if [ "$REUSE" -eq 1 ] && [ -f "$TARBALL" ]; then
  log_info "复用已存在的 tarball: $TARBALL"
else
  if [ "$REUSE" -eq 1 ]; then
    log_info "未找到已存在的 tarball，将重新构建"
  fi
  log_info "构建 release 包..."
  build_args=("$TAG")
  if [ "$VIA_DOCKER" -eq 1 ]; then
    build_args+=(--via-docker)
  fi
  TARBALL="$(./scripts/build-release-package.sh "${build_args[@]}" | tail -n 1)"
fi

log_info "部署到 ${DEPLOY_ENV}..."
./scripts/deploy-remote.sh "$TARBALL" --env "$DEPLOY_ENV" --version "$TAG"

log_info "部署完成: ${TAG} → ${DEPLOY_ENV}"

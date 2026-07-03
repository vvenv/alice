#!/bin/bash
# 本地构建 release tarball（与 CI release.yml build job 一致）
#
# 用法:
#   ./scripts/build-release-package.sh v1.0.0
#   ./scripts/build-release-package.sh v1.0.0 --via-docker   # 非 Linux 或强制容器构建
#
# macOS 等非 Linux 环境会在 Docker 隔离目录中构建（只读挂载源码，不污染本机 node_modules）。
#
# 产出: ${PROJECT_SLUG}-v1.0.0.tar.gz（路径写入 stdout 最后一行）

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

# shellcheck source=scripts/lib/release-deploy-config.sh
source "$ROOT/scripts/lib/release-deploy-config.sh"
# shellcheck source=scripts/lib/log.sh
source "$ROOT/scripts/lib/log.sh"


VERSION=""
VIA_DOCKER=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --via-docker) VIA_DOCKER=1 ;;
    --help|-h)
      sed -n '3,8p' "$0"
      exit 0
      ;;
    -*)
      log_die "未知选项: $1"
      ;;
    *)
      if [ -n "$VERSION" ]; then
        log_die "多余的参数: $1"
      fi
      VERSION="$1"
      ;;
  esac
  shift
done

if [ -z "$VERSION" ]; then
  log_die "请指定版本号，如 v1.0.0"
fi

VERSION="${VERSION#v}"
TAG="v${VERSION}"
TARBALL="$ROOT/${PROJECT_SLUG}-${TAG}.tar.gz"
PNPM_VERSION="11.9.0"
NODE_VERSION="22"

build_on_host() {
  log_info "安装依赖..."
  pnpm install --frozen-lockfile --prefer-offline

  log_info "构建 packages（shared 先行，client/server 并行）..."
  pnpm build

  log_info "打包 release 目录..."
  chmod +x scripts/prepare-release.sh
  ./scripts/prepare-release.sh release "$TAG"

  log_info "创建 tarball..."
  tar -czf "$TARBALL" -C release .
}

ensure_release_builder_image() {
  local builder_image="${PROJECT_SLUG}-release-builder:node${NODE_VERSION}-pnpm${PNPM_VERSION}"
  local dockerfile="$ROOT/scripts/docker/release-builder.Dockerfile"

  log_info "确保 release 构建镜像已就绪（apt/pnpm 层可跨次复用）..."
  # 不指定 --platform：用宿主原生架构（Apple Silicon = arm64）。
  # release tarball 仅含 JS dist / 源码 / prisma / 静态资源，架构无关；
  # 原生依赖（bcrypt 等）在目标 amd64 服务器 pnpm install 时安装。
  # 跨架构 QEMU 模拟会让 tsc/Vite 慢 3-10x，本地构建务必用原生架构。
  DOCKER_BUILDKIT=1 docker build \
    --build-arg "NODE_VERSION=${NODE_VERSION}" \
    --build-arg "PNPM_VERSION=${PNPM_VERSION}" \
    -f "$dockerfile" \
    -t "$builder_image" \
    "$ROOT/scripts/docker"
  RELEASE_BUILDER_IMAGE="$builder_image"
}

build_in_docker() {
  if ! command -v docker >/dev/null 2>&1; then
    log_die "未检测到 Docker。生产 release 需在 Linux x64 构建；请安装 Docker 或使用 Linux 机器/CI"
  fi

  ensure_release_builder_image

  local pnpm_store_volume="${PROJECT_SLUG}-release-pnpm-store"
  local artifact_dir tarball_name
  tarball_name="${PROJECT_SLUG}-${TAG}.tar.gz"
  artifact_dir="$(mktemp -d "${TMPDIR:-/tmp}/${PROJECT_SLUG}-release-artifact.XXXXXX")"

  log_info "在 Docker 隔离环境中构建 release 包（不修改本机 node_modules）..."
  log_info "原生 arm64 构建；复用构建镜像与 pnpm store 后主要耗时在 pnpm build"
  docker run --rm -i \
    -e CI=true \
    -e DEBIAN_FRONTEND=noninteractive \
    -e "TAG=${TAG}" \
    -e "TARBALL_NAME=${tarball_name}" \
    -v "$ROOT:/src:ro" \
    -v "${pnpm_store_volume}:/root/.local/share/pnpm/store" \
    -v "${artifact_dir}:/artifact-out" \
    "$RELEASE_BUILDER_IMAGE" bash -s <<'DOCKER_SCRIPT'
set -euo pipefail

step() { echo "[build-release] >>> $*"; }

copy_source_into_build_dir() {
  tar -cf - \
    --exclude=./node_modules \
    --exclude=./packages/server/node_modules \
    --exclude=./packages/client/node_modules \
    --exclude=./packages/shared/node_modules \
    --exclude=./packages/server/dist \
    --exclude=./packages/client/dist \
    --exclude=./packages/shared/dist \
    --exclude=./release \
    --exclude=./.git \
    --exclude='./*.tar.gz' \
    -C /src . | tar -xf - -C /build
}

step '复制源码到隔离构建目录 (/build)...'
rm -rf /build
mkdir -p /build
copy_source_into_build_dir
cd /build

step '安装 Node 依赖 (pnpm install --prefer-offline)...'
pnpm install --frozen-lockfile --prefer-offline
step '依赖安装完成'

step '构建 packages (shared 先行，client/server 并行)...'
pnpm build
step '构建完成'

step '打包 release 目录...'
chmod +x scripts/prepare-release.sh
./scripts/prepare-release.sh release "${TAG}"
step 'release 目录就绪'

step '创建 tarball...'
tar -czf "/artifact-out/${TARBALL_NAME}" -C release .
step 'tarball 创建完成'
DOCKER_SCRIPT

  mv "${artifact_dir}/${tarball_name}" "$TARBALL"
  rm -rf "$artifact_dir"
}

if [ "$VIA_DOCKER" -eq 1 ]; then
  build_in_docker
elif [ "$(uname -s)" = "Linux" ]; then
  build_on_host
elif command -v docker >/dev/null 2>&1 && docker info >/dev/null 2>&1; then
  log_info "检测到非 Linux 环境，自动使用 Docker 构建（与生产 Linux x64 一致）"
  build_in_docker
else
  log_die "非 Linux 环境且 Docker 不可用。请安装 Docker 后重试，或使用 --via-docker"
fi

if [ ! -f "$TARBALL" ]; then
  log_die "构建失败，未生成 $TARBALL"
fi

log_info "Release 包已就绪: $TARBALL ($(du -sh "$TARBALL" | cut -f1))"
echo "$TARBALL"

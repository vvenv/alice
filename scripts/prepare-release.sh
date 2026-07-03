#!/bin/bash
# 在 CI 中打包 release 产物
# 用法: ./scripts/prepare-release.sh [输出目录] [版本号]

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
RELEASE_DIR="${1:-$ROOT/release}"
VERSION="${2:?请指定版本号}"

# shellcheck source=scripts/lib/log.sh
source "$ROOT/scripts/lib/log.sh"

log_info "Preparing release $VERSION -> $RELEASE_DIR"

rm -rf "$RELEASE_DIR"
mkdir -p "$RELEASE_DIR/packages/server" "$RELEASE_DIR/packages/shared" "$RELEASE_DIR/packages/client" "$RELEASE_DIR/scripts"

cp "$ROOT/package.json" "$RELEASE_DIR/"
cp "$ROOT/pnpm-workspace.yaml" "$RELEASE_DIR/"
cp "$ROOT/pnpm-lock.yaml" "$RELEASE_DIR/"
cp "$ROOT/scripts/ecosystem.config.cjs" "$RELEASE_DIR/"

cp "$ROOT/packages/shared/package.json" "$RELEASE_DIR/packages/shared/"
cp -r "$ROOT/packages/shared/dist" "$RELEASE_DIR/packages/shared/"

cp "$ROOT/packages/client/package.json" "$RELEASE_DIR/packages/client/"
cp -r "$ROOT/packages/client/dist" "$RELEASE_DIR/packages/client/"

cp "$ROOT/packages/server/package.json" "$RELEASE_DIR/packages/server/"
cp "$ROOT/packages/server/tsconfig.json" "$RELEASE_DIR/packages/server/"
cp "$ROOT/packages/server/tsconfig.build.json" "$RELEASE_DIR/packages/server/"
cp -r "$ROOT/packages/server/src" "$RELEASE_DIR/packages/server/"
cp -r "$ROOT/packages/server/dist" "$RELEASE_DIR/packages/server/"

mkdir -p "$RELEASE_DIR/scripts/lib"
for script in install-production.sh start.sh restart.sh stop.sh deploy-local-archive.sh bootstrap-ci.sh health-check.sh resync-nginx-slot.sh; do
  cp "$ROOT/scripts/$script" "$RELEASE_DIR/scripts/"
  chmod +x "$RELEASE_DIR/scripts/$script"
done
cp "$ROOT/scripts/lib/blue-green.sh" "$RELEASE_DIR/scripts/lib/"
cp "$ROOT/scripts/lib/log.sh" "$RELEASE_DIR/scripts/lib/"
chmod +x "$RELEASE_DIR/scripts/lib/blue-green.sh"
chmod +x "$RELEASE_DIR/scripts/lib/log.sh"

echo "$VERSION" > "$RELEASE_DIR/VERSION"

log_info "Release package ready at $RELEASE_DIR"

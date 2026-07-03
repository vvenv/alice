#!/bin/bash
# 非交互式升版本：检查 → 同步 package.json → commit → tag → push
# 供 GitHub Actions workflow_dispatch 调用；也可本地手动执行。
# CI 发布流程使用 --prepare-only，在 build/deploy 成功后再由 publish job 提交版本。
#
# 用法:
#   ./scripts/bump-version.sh patch
#   ./scripts/bump-version.sh 1.2.3 --skip-check
#   ./scripts/bump-version.sh minor --no-push
#   ./scripts/bump-version.sh patch --prepare-only   # 仅解析版本并检查，不写 git（供 CI 在部署成功后提交）

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

VERSION_ROOT="$ROOT"
# shellcheck source=scripts/lib/version.sh
source "$ROOT/scripts/lib/version.sh"
# shellcheck source=scripts/lib/log.sh
source "$ROOT/scripts/lib/log.sh"

VERSION_ARG=""
RUN_CHECK=1
DO_PUSH=1
PREPARE_ONLY=0

for arg in "$@"; do
  case "$arg" in
    --skip-check) RUN_CHECK=0 ;;
    --no-push) DO_PUSH=0 ;;
    --prepare-only) PREPARE_ONLY=1 ;;
    --help|-h)
      sed -n '3,10p' "$0"
      exit 0
      ;;
    -*)
      log_die "未知选项: ${arg}（可用 --skip-check、--no-push、--prepare-only）"
      ;;
    *)
      if [ -n "$VERSION_ARG" ]; then
        log_die "多余的参数: $arg"
      fi
      VERSION_ARG="$arg"
      ;;
  esac
done

if [ -z "$VERSION_ARG" ]; then
  log_die "请指定版本号或 bump 类型（patch / minor / major）"
fi

if [ -n "$(git status --porcelain)" ]; then
  log_die "工作区不干净，请先提交或暂存当前改动"
fi

NEW_VERSION="$(resolve_version "$VERSION_ARG")"
TAG="v${NEW_VERSION}"

# 进度信息输出到 stderr；stdout 仅保留版本号（供 CI 读取，如 --prepare-only）
log_info "当前分支: $(git branch --show-current)" >&2
log_info "新版本: $NEW_VERSION" >&2
log_info "标签: $TAG" >&2

if version_tag_exists "$NEW_VERSION"; then
  log_die "标签已存在: $TAG"
fi

if [ "$RUN_CHECK" -eq 1 ]; then
  log_info "运行 lint + test（并行）..." >&2
  pnpm check
else
  log_info "跳过 lint/test" >&2
fi

if [ "$PREPARE_ONLY" -eq 1 ]; then
  log_info "prepare-only：跳过 commit / tag / push" >&2
  echo "$NEW_VERSION"
  exit 0
fi

sync_package_versions "$NEW_VERSION"

git add "${VERSION_PACKAGE_JSONS[@]}"
git commit -m "chore: release ${TAG}"
git tag -a "$TAG" -m "Release ${TAG}"

log_info "已创建提交与标签: $TAG" >&2

if [ "$DO_PUSH" -eq 1 ]; then
  log_info "推送 commit..." >&2
  git push origin HEAD --no-verify
  log_info "推送 tag $TAG..." >&2
  git push origin "$TAG" --no-verify
  log_info "已推送 commit 与 tag（本地 push 会触发 Release workflow；Actions 内由同一 workflow 继续发布）" >&2
else
  log_info "下一步: git push origin HEAD --no-verify && git push origin $TAG --no-verify" >&2
fi

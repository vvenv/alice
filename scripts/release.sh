#!/bin/bash
# 发布流程：同步版本号 → 提交 → 打 tag →（可选）推送触发 Release workflow
#
# 用法:
#   ./scripts/release.sh                    # 交互式选择版本与选项
#   ./scripts/release.sh <version>          # 指定版本，如 1.0.0 或 v1.0.0
#   ./scripts/release.sh patch|minor|major  # 基于根 package.json 递增
#   ./scripts/release.sh 1.0.0 --push       # 提交并推送 commit + tag
#   ./scripts/release.sh patch --no-check   # 跳过 lint/test
#   ./scripts/release.sh patch --deploy-local              # 本地构建 + SSH 部署 + 推送 tag
#   ./scripts/release.sh patch --deploy-local --no-push    # 仅本地部署，不推送
#   ./scripts/release.sh patch --deploy-local --env test   # 部署到测试环境
#   ./scripts/release.sh patch --deploy-local --env edge   # 部署到 Edge
#   ./scripts/release.sh patch --deploy-local --env test,production  # 一次部署多个环境
#
# 推送 v* 标签后会自动触发 .github/workflows/release.yml（构建 + GitHub Release + 部署）
# GitHub Actions 分钟用尽时，使用 --deploy-local 在本地构建并直推服务器，同时推送 tag 记录版本

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

VERSION_ROOT="$ROOT"
# shellcheck source=scripts/lib/version.sh
source "$ROOT/scripts/lib/version.sh"
# shellcheck source=scripts/lib/log.sh
source "$ROOT/scripts/lib/log.sh"


VERSION_ARG=""
PUSH=0
NO_PUSH=0
RUN_CHECK=1
INTERACTIVE=0
PUSH_PRESET=0
NO_PUSH_PRESET=0
CHECK_PRESET=0
DEPLOY_LOCAL=0
DEPLOY_LOCAL_PRESET=0
DEPLOY_ENV="production"
VIA_DOCKER=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --push) PUSH=1; PUSH_PRESET=1; shift ;;
    --no-push) NO_PUSH=1; NO_PUSH_PRESET=1; shift ;;
    --no-check) RUN_CHECK=0; CHECK_PRESET=1; shift ;;
    --deploy-local) DEPLOY_LOCAL=1; DEPLOY_LOCAL_PRESET=1; shift ;;
    --via-docker) VIA_DOCKER=1; shift ;;
    --env)
      DEPLOY_ENV="$2"
      shift 2
      ;;
    --help|-h)
      sed -n '3,16p' "$0"
      exit 0
      ;;
    -*)
      log_die "未知选项: $1（可用 --push、--no-push、--no-check、--deploy-local、--env、--via-docker）"
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

if [ -z "$VERSION_ARG" ]; then
  if [ -t 0 ]; then
    INTERACTIVE=1
  else
    log_die "请指定版本号或 bump 类型（patch / minor / major），或在终端中交互运行"
  fi
fi

if [ -n "$(git status --porcelain)" ]; then
  log_die "工作区不干净，请先提交或暂存当前改动"
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
    [Yy]|[Yy][Ee][Ss])
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

run_interactive() {
  # shellcheck source=scripts/lib/prompt-menu.sh
  source "$ROOT/scripts/lib/prompt-menu.sh"

  local current branch patch_ver minor_ver major_ver choice custom_version

  current="$(get_current_version)"
  branch="$(git branch --show-current)"

  log_info "当前分支: $branch"
  log_info "当前版本: $current"
  echo ""

  previews=()
  while IFS= read -r line; do
    [ -n "$line" ] && previews+=("$line")
  done < <(compute_bump_previews)
  if [ "${#previews[@]}" -eq 3 ]; then
    patch_ver="${previews[0]}"
    minor_ver="${previews[1]}"
    major_ver="${previews[2]}"
    choice="$(prompt_menu "请选择新版本" --default=1 \
      "patch:${current} → ${patch_ver} (patch)" \
      "minor:${current} → ${minor_ver} (minor)" \
      "major:${current} → ${major_ver} (major)" \
      "custom:自定义版本号")"
  else
    log_info "当前为预发布版本，请手动输入目标版本号"
    choice="custom"
  fi

  if [ "$choice" = "custom" ]; then
    while true; do
      read -r -p "请输入版本号 (当前 ${current}): " custom_version </dev/tty
      custom_version="${custom_version// /}"
      if [ -z "$custom_version" ]; then
        echo "版本号不能为空" >&2
        continue
      fi
      if NEW_VERSION="$(resolve_version "$custom_version" 2>&1)"; then
        VERSION_ARG="$custom_version"
        break
      fi
      echo "$NEW_VERSION" >&2
    done
  else
    VERSION_ARG="$choice"
    NEW_VERSION="$(resolve_version "$choice")"
  fi

  if [ "$CHECK_PRESET" -eq 0 ]; then
    local check_choice
    check_choice="$(prompt_menu "是否运行 lint 和 test？" --default=1 \
      "yes:运行 lint + test" \
      "no:跳过检查")"
    if [ "$check_choice" = "no" ]; then
      RUN_CHECK=0
    fi
  fi

  if [ "$DEPLOY_LOCAL_PRESET" -eq 0 ]; then
    local deploy_choice
    deploy_choice="$(prompt_menu "发布方式" --default=1 \
      "ci:推送 tag 触发 GitHub Actions（推荐）" \
      "local:本地构建并 SSH 部署（不消耗 CI 分钟）")"
    if [ "$deploy_choice" = "local" ]; then
      DEPLOY_LOCAL=1
    fi
  fi

  if [ "$DEPLOY_LOCAL" -eq 1 ] && [ "$DEPLOY_LOCAL_PRESET" -eq 0 ]; then
    DEPLOY_ENV="$(prompt_multi_menu "部署环境（空格多选，回车确认）" --default=1 \
      "production:生产环境" \
      "test:测试环境" \
      "edge:Harvest Edge（圣保罗）")"
  fi

  TAG="v${NEW_VERSION}"
  echo ""
  log_info "发布预览"
  echo "  版本: ${current} → ${NEW_VERSION}"
  echo "  标签: ${TAG}"
  if [ "$RUN_CHECK" -eq 1 ]; then
    echo "  检查: lint + test"
  else
    echo "  检查: 跳过"
  fi
  if [ "$DEPLOY_LOCAL" -eq 1 ]; then
    if [ "$NO_PUSH_PRESET" -eq 1 ]; then
      echo "  部署: 本地构建 → ${DEPLOY_ENV}（不推送 tag）"
    else
      echo "  部署: 本地构建 → ${DEPLOY_ENV}，完成后推送 tag"
    fi
  elif [ "$PUSH_PRESET" -eq 1 ]; then
    echo "  推送: 完成后自动推送（触发 CI）"
  else
    echo "  推送: 稍后询问"
  fi
  echo ""

  if ! prompt_confirm "确认开始发布？" "y"; then
    log_info "已取消"
    exit 0
  fi
}

if [ "$INTERACTIVE" -eq 1 ]; then
  run_interactive
fi

if [ -z "${NEW_VERSION:-}" ]; then
  NEW_VERSION="$(resolve_version "$VERSION_ARG")"
fi
TAG="v${NEW_VERSION}"

if [ "$INTERACTIVE" -eq 0 ]; then
  log_info "当前分支: $(git branch --show-current)"
  log_info "新版本: $NEW_VERSION"
  log_info "标签: $TAG"
fi

if version_tag_exists "$NEW_VERSION"; then
  log_die "标签已存在: $TAG"
fi

if [ "$RUN_CHECK" -eq 1 ]; then
  log_info "运行 lint + test（并行）..."
  pnpm check
else
  log_info "跳过 lint/test"
fi

sync_package_versions "$NEW_VERSION"

git add "${VERSION_PACKAGE_JSONS[@]}"
git commit -m "chore: release ${TAG}"
git tag -a "$TAG" -m "Release ${TAG}"

log_info "已创建提交与标签: $TAG"

if [ "$DEPLOY_LOCAL" -eq 1 ]; then
  build_args=("$TAG")
  if [ "$VIA_DOCKER" -eq 1 ]; then
    build_args+=(--via-docker)
  fi
  log_info "本地构建 release 包..."
  chmod +x scripts/build-release-package.sh scripts/deploy-remote.sh
  TARBALL="$(./scripts/build-release-package.sh "${build_args[@]}" | tail -n 1)"

  log_info "部署到 ${DEPLOY_ENV}..."
  ./scripts/deploy-remote.sh "$TARBALL" --env "$DEPLOY_ENV" --version "$TAG"

  log_info "本地部署完成"
fi

should_push=0
if [ "$NO_PUSH" -eq 1 ]; then
  should_push=0
elif [ "$PUSH" -eq 1 ]; then
  should_push=1
elif [ "$DEPLOY_LOCAL" -eq 1 ] && [ "$INTERACTIVE" -eq 0 ]; then
  should_push=1
elif [ "$INTERACTIVE" -eq 1 ] && [ "$PUSH_PRESET" -eq 0 ] && [ "$NO_PUSH_PRESET" -eq 0 ]; then
  # shellcheck source=scripts/lib/prompt-menu.sh
  source "$ROOT/scripts/lib/prompt-menu.sh"
  if [ "$DEPLOY_LOCAL" -eq 1 ]; then
    push_choice="$(prompt_menu "是否推送到远程记录版本？（CI 已受限时不会消耗 Actions 分钟）" --default=1 \
      "now:立即推送 commit 和 tag" \
      "later:稍后手动推送")"
  else
    push_choice="$(prompt_menu "是否推送到远程并触发 Release workflow？" --default=1 \
      "later:稍后手动推送" \
      "now:立即推送 commit 和 tag")"
  fi
  if [ "$push_choice" = "now" ]; then
    should_push=1
  else
    should_push=0
  fi
else
  should_push=0
fi

if [ "$should_push" -eq 1 ]; then
  log_info "推送 commit..."
  git push --no-verify
  log_info "推送 tag $TAG..."
  git push origin "$TAG" --no-verify
  if [ "$DEPLOY_LOCAL" -eq 1 ]; then
    log_info "已推送 commit 与 tag（Release workflow 可能排队或失败；服务器已由本地部署更新）"
  else
    log_info "已推送，请在 GitHub Actions 查看 Release 进度"
  fi
else
  if [ "$DEPLOY_LOCAL" -eq 1 ]; then
    log_info "下一步: git push --no-verify && git push origin $TAG --no-verify"
  else
    log_info "下一步: git push --no-verify && git push origin $TAG --no-verify"
    log_info "推送标签后将触发 .github/workflows/release.yml（构建 + 部署）"
  fi
fi

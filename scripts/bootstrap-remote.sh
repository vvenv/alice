#!/bin/bash
# 本地远程执行主应用 bootstrap / 重新 bootstrap（与 CI bootstrap-server 相同）
#
# 用法:
#   ./scripts/bootstrap-remote.sh
#   ./scripts/bootstrap-remote.sh --env production
#   ./scripts/bootstrap-remote.sh v0.2.1 --domain app.example.com --ssl-email you@example.com
#   ./scripts/bootstrap-remote.sh --build
#   ./scripts/bootstrap-remote.sh --reuse
#   ./scripts/bootstrap-remote.sh --yes
#
# 默认用当前仓库代码构建 tarball（package.json 版本号仅作产物命名）。
# --reuse 才复用本地已有 alice-vX.tar.gz。
# 凭证与密钥：复制 scripts/env.production.example → .env.production（或 env.test.example → .env.test）
# 必填（主站）: DEPLOY_HOST/SSH_USER/SSH_PASSWORD、DB_PASSWORD、JWT_SECRET

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

VERSION_ROOT="$ROOT"
# shellcheck source=scripts/lib/version.sh
source "$ROOT/scripts/lib/version.sh"
# shellcheck source=scripts/lib/release-deploy-config.sh
source "$ROOT/scripts/lib/release-deploy-config.sh"
# shellcheck source=scripts/lib/bootstrap-remote.sh
source "$ROOT/scripts/lib/bootstrap-remote.sh"
# shellcheck source=scripts/lib/deploy-env.sh
source "$ROOT/scripts/lib/deploy-env.sh"
# shellcheck source=scripts/lib/log.sh
source "$ROOT/scripts/lib/log.sh"


VERSION_ARG=""
ENVIRONMENT="production"
DOMAIN=""
SSL_EMAIL=""
PORT=""
BUILD=0
REUSE=0
ENV_PRESET=0
DOMAIN_PRESET=0
SSL_EMAIL_PRESET=0
PORT_PRESET=0
VERSION_PRESET=0
BUILD_PRESET=0
REUSE_PRESET=0
INTERACTIVE=0
PROMPT_CODE_SOURCE=0
YES=0

default_port_for_env() {
  if [ "$1" = "test" ]; then
    echo "3602"
  else
    echo "3600"
  fi
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --)
      shift
      ;;
    --env)
      ENVIRONMENT="$2"
      ENV_PRESET=1
      shift 2
      ;;
    --domain)
      DOMAIN="$2"
      DOMAIN_PRESET=1
      shift 2
      ;;
    --ssl-email)
      SSL_EMAIL="$2"
      SSL_EMAIL_PRESET=1
      shift 2
      ;;
    --port)
      PORT="$2"
      PORT_PRESET=1
      shift 2
      ;;
    --build)
      BUILD=1
      BUILD_PRESET=1
      shift
      ;;
    --reuse)
      REUSE=1
      REUSE_PRESET=1
      shift
      ;;
    --yes|-y)
      YES=1
      shift
      ;;
    --help|-h)
      sed -n '3,13p' "$0"
      exit 0
      ;;
    -*)
      log_die "未知选项: $1"
      ;;
    *)
      if [ -n "$VERSION_ARG" ]; then
        log_die "多余的参数: $1"
      fi
      VERSION_ARG="$1"
      VERSION_PRESET=1
      shift
      ;;
  esac
done

# 按 --env 加载对应 .env.production / .env.test
load_deploy_env "$ROOT" "$ENVIRONMENT"

if [ "$ENV_PRESET" -eq 0 ] && deploy_env_has "${DEPLOY_ENV:-}"; then
  ENVIRONMENT="$DEPLOY_ENV"
  ENV_PRESET=1
fi

if [ "$DOMAIN_PRESET" -eq 0 ] && deploy_env_has "${REGORA_DOMAIN:-}"; then
  DOMAIN="$REGORA_DOMAIN"
  DOMAIN_PRESET=1
fi

if [ "$SSL_EMAIL_PRESET" -eq 0 ] && deploy_env_has "${SSL_EMAIL:-}"; then
  SSL_EMAIL_PRESET=1
fi

if [ "$PORT_PRESET" -eq 0 ] && deploy_env_has "${REGORA_PORT:-}"; then
  PORT="$REGORA_PORT"
  PORT_PRESET=1
fi

needs_interactive=0
if [ -t 0 ]; then
  [ "$ENV_PRESET" -eq 0 ] && needs_interactive=1
  [ "$DOMAIN_PRESET" -eq 0 ] && needs_interactive=1
  if deploy_env_has "${DOMAIN:-}"; then
    [ "$SSL_EMAIL_PRESET" -eq 0 ] && needs_interactive=1
  elif [ "$DOMAIN_PRESET" -eq 0 ]; then
    [ "$SSL_EMAIL_PRESET" -eq 0 ] && needs_interactive=1
  fi
  [ "$PORT_PRESET" -eq 0 ] && needs_interactive=1
  if ! deploy_env_has "${DB_PASSWORD:-}" || ! deploy_env_has "${JWT_SECRET:-}"; then
    needs_interactive=1
  fi
  if deploy_env_is_placeholder_db_password "${DB_PASSWORD:-}" \
    || deploy_env_is_placeholder_jwt_secret "${JWT_SECRET:-}"; then
    needs_interactive=1
  fi
fi

if [ "$needs_interactive" -eq 1 ]; then
  INTERACTIVE=1
fi

if [ "$YES" -eq 0 ] && [ -t 0 ] \
  && [ "$REUSE_PRESET" -eq 0 ] && [ "$BUILD_PRESET" -eq 0 ] && [ "$VERSION_PRESET" -eq 0 ]; then
  PROMPT_CODE_SOURCE=1
fi

_placeholder_secrets=()
while IFS= read -r _secret_name; do
  [ -n "$_secret_name" ] && _placeholder_secrets+=("$_secret_name")
done < <(deploy_env_collect_placeholder_secrets)
if [ "${#_placeholder_secrets[@]}" -gt 0 ] && [ "$INTERACTIVE" -eq 0 ]; then
  log_die ".env.${ENVIRONMENT} 中以下项仍为示例值，请填入真实密钥: ${_placeholder_secrets[*]}"
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

prompt_secret() {
  local var_name="$1"
  local prompt="$2"
  local value

  if [ -n "${!var_name:-}" ]; then
    return 0
  fi

  while true; do
    read -r -s -p "$prompt: " value </dev/tty
    echo "" >/dev/tty
    value="${value// /}"
    if [ -n "$value" ]; then
      printf -v "$var_name" '%s' "$value"
      return 0
    fi
    echo "不能为空" >&2
  done
}

prompt_code_source() {
  local current custom_version build_choice source_choice release_tarball candidate_tarball
  local -a source_menu=()

  current="$(get_current_version)"
  candidate_tarball="$ROOT/${PROJECT_SLUG}-v${current}.tar.gz"

  source_menu=(
    "local:用当前仓库代码构建并部署 (v${current})"
  )
  if [ -f "$candidate_tarball" ]; then
    source_menu+=("reuse:复用已有 ${PROJECT_SLUG}-v${current}.tar.gz（不含未打包的本地改动）")
  fi
  source_menu+=("release:指定其他 release 版本号（非当前仓库代码）")

  source_choice="$(prompt_menu "代码来源" --default=1 "${source_menu[@]}")"

  case "$source_choice" in
    local)
      VERSION="$current"
      BUILD=1
      REUSE=0
      ;;
    reuse)
      VERSION="$current"
      REUSE=1
      BUILD=0
      ;;
    release)
      while true; do
        read -r -p "请输入 release 版本号 (如 1.2.3 或 v1.2.3): " custom_version </dev/tty
        custom_version="${custom_version// /}"
        if [ -z "$custom_version" ]; then
          echo "版本号不能为空" >&2
          continue
        fi
        VERSION="${custom_version#v}"
        break
      done
      TAG="v${VERSION}"
      release_tarball="$ROOT/${PROJECT_SLUG}-${TAG}.tar.gz"
      if [ -f "$release_tarball" ]; then
        build_choice="$(prompt_menu "构建包" --default=1 \
          "reuse:复用已有 ${PROJECT_SLUG}-${TAG}.tar.gz" \
          "rebuild:重新构建该版本 tarball")"
        if [ "$build_choice" = "reuse" ]; then
          REUSE=1
          BUILD=0
        else
          BUILD=1
          REUSE=0
        fi
      else
        BUILD=1
        REUSE=0
      fi
      ;;
    *)
      log_die "未知选项: $source_choice"
      ;;
  esac
}

show_bootstrap_preview_and_confirm() {
  if [ -z "$PORT" ]; then
    PORT="$(default_port_for_env "$ENVIRONMENT")"
  fi
  TAG="v${VERSION}"

  echo ""
  log_info "Bootstrap 预览"
  log_info "  版本: ${TAG}"
  log_info "  环境: ${ENVIRONMENT}"
  if [ -n "$DOMAIN" ]; then
    log_info "  域名: ${DOMAIN}"
    if [ -n "$SSL_EMAIL" ]; then
      log_info "  SSL: ${SSL_EMAIL}"
    else
      log_info "  SSL: 跳过（仅 HTTP）"
    fi
  else
    log_info "  Nginx: 跳过"
  fi
  if [ "$REUSE" -eq 1 ]; then
    log_info "  构建: 复用已有 tarball"
  else
    log_info "  构建: 从当前仓库代码重新构建"
  fi
  echo ""

  if ! prompt_confirm "确认开始 bootstrap？" "y"; then
    log_info "已取消"
    exit 0
  fi
}

run_interactive() {
  local custom_version build_choice

  echo ""
  log_info "Alice 服务器 bootstrap / 重新 bootstrap"
  echo ""

  if [ "$ENV_PRESET" -eq 0 ]; then
    ENVIRONMENT="$(prompt_menu "部署环境" --default=1 \
      "production:生产环境 (端口 3600)" \
      "test:测试环境 (端口 3602)")"
  fi

  if [ "$VERSION_PRESET" -eq 0 ] && [ "$REUSE_PRESET" -eq 0 ] && [ "$BUILD_PRESET" -eq 0 ]; then
    prompt_code_source
  elif [ -n "$VERSION_ARG" ]; then
    VERSION="${VERSION_ARG#v}"
  else
    VERSION="$(get_current_version)"
  fi

  if [ -z "${VERSION:-}" ]; then
    VERSION="$(get_current_version)"
  fi

  if [ "$VERSION_PRESET" -eq 1 ] || [ "$REUSE_PRESET" -eq 1 ] || [ "$BUILD_PRESET" -eq 1 ]; then
    :
  elif [ "$BUILD" -eq 0 ] && [ "$REUSE" -eq 0 ]; then
    BUILD=1
  fi

  if [ "$DOMAIN_PRESET" -eq 0 ]; then
    local domain_input
    read -r -p "Nginx 域名 (留空跳过，如 app.alice.example): " domain_input </dev/tty
    domain_input="${domain_input// /}"
    DOMAIN="$domain_input"
  fi

  if [ -n "$DOMAIN" ] && [ "$SSL_EMAIL_PRESET" -eq 0 ]; then
    local email_input
    while true; do
      read -r -p "SSL 证书邮箱 (Let's Encrypt，留空跳过 HTTPS): " email_input </dev/tty
      email_input="${email_input// /}"
      if [ -z "$email_input" ]; then
        SSL_EMAIL=""
        break
      fi
      if [[ "$email_input" == *@*.* ]]; then
        SSL_EMAIL="$email_input"
        break
      fi
      echo "请输入有效邮箱地址，或留空跳过 SSL" >&2
    done
  fi

  if [ "$PORT_PRESET" -eq 0 ]; then
    local default_port port_input
    default_port="$(default_port_for_env "$ENVIRONMENT")"
    read -r -p "应用监听端口 [${default_port}]: " port_input </dev/tty
    port_input="${port_input// /}"
    if [ -n "$port_input" ]; then
      PORT="$port_input"
    else
      PORT="$default_port"
    fi
  fi

  prompt_secret DB_PASSWORD "PostgreSQL 密码 (DB_PASSWORD)"
  prompt_secret JWT_SECRET "JWT 签名密钥 (JWT_SECRET)"

  if [ -z "${TENANT_SECRET_ENCRYPTION_KEY:-}" ]; then
    read -r -s -p "租户加密密钥 TENANT_SECRET_ENCRYPTION_KEY (32 字节 hex，留空由服务器自动生成): " _tenant_key </dev/tty
    echo "" >/dev/tty
    _tenant_key="${_tenant_key// /}"
    if [ -n "$_tenant_key" ]; then
      TENANT_SECRET_ENCRYPTION_KEY="$_tenant_key"
    fi
  fi

  if ! deploy_env_has "${OPENAI_API_KEY:-}"; then
    local openai_choice
    openai_choice="$(prompt_menu "OpenAI API Key" --default=1 \
      "skip:跳过（稍后手动配置）" \
      "input:现在输入 OPENAI_API_KEY")"
    if [ "$openai_choice" = "input" ]; then
      read -r -s -p "OPENAI_API_KEY: " OPENAI_API_KEY </dev/tty
      echo "" >/dev/tty
    fi
  fi

  show_bootstrap_preview_and_confirm
}

if [ "$INTERACTIVE" -eq 1 ]; then
  deploy_env_clear_placeholder_secrets
  # shellcheck source=scripts/lib/prompt-menu.sh
  source "$ROOT/scripts/lib/prompt-menu.sh"
  run_interactive
elif [ -n "$VERSION_ARG" ]; then
  VERSION="${VERSION_ARG#v}"
else
  VERSION="$(get_current_version)"
fi

if [ "$PROMPT_CODE_SOURCE" -eq 1 ] && [ "$INTERACTIVE" -eq 0 ]; then
  # shellcheck source=scripts/lib/prompt-menu.sh
  source "$ROOT/scripts/lib/prompt-menu.sh"
  echo ""
  log_info "Alice 服务器 bootstrap / 重新 bootstrap（其余配置来自 .env.${ENVIRONMENT}）"
  echo ""
  prompt_code_source
  show_bootstrap_preview_and_confirm
fi

if [ -z "${DB_PASSWORD:-}" ] || [ -z "${JWT_SECRET:-}" ]; then
  log_die "缺少 DB_PASSWORD 或 JWT_SECRET。请在 .env.${ENVIRONMENT} 中配置，或使用交互式 bootstrap"
fi

TAG="v${VERSION}"
TARBALL="$ROOT/${PROJECT_SLUG}-${TAG}.tar.gz"

if [ -z "$PORT" ]; then
  PORT="$(default_port_for_env "$ENVIRONMENT")"
fi

if [ "$INTERACTIVE" -eq 0 ] && [ "$PROMPT_CODE_SOURCE" -eq 0 ] && [ "$REUSE" -eq 0 ] && [ "$BUILD" -eq 0 ]; then
  BUILD=1
fi

if [ "$INTERACTIVE" -eq 0 ] && [ "$PROMPT_CODE_SOURCE" -eq 0 ]; then
  log_info "版本: ${TAG}"
  log_info "环境: ${ENVIRONMENT}"
  if deploy_env_has "${REGORA_DOMAIN:-}" || deploy_env_has "${DOMAIN:-}"; then
    log_info "域名: ${DOMAIN}"
    deploy_env_has "${SSL_EMAIL:-}" && log_info "SSL: ${SSL_EMAIL}"
  fi
  log_info "端口: ${PORT}"
  if [ "$REUSE" -eq 1 ]; then
    log_info "构建: 复用已有 tarball"
  else
    log_info "构建: 从当前仓库代码重新构建"
  fi
fi

chmod +x scripts/build-release-package.sh

if [ "$REUSE" -eq 1 ] && [ -f "$TARBALL" ]; then
  log_info "复用已存在的 tarball: $TARBALL"
elif [ "$BUILD" -eq 1 ] || [ ! -f "$TARBALL" ]; then
  if [ "$REUSE" -eq 1 ]; then
    log_info "未找到已存在的 tarball，将重新构建"
  fi
  log_info "构建 release 包..."
  TARBALL="$(./scripts/build-release-package.sh "$TAG" | tail -n 1)"
else
  log_info "使用已有 tarball: $TARBALL"
fi

bootstrap_release_server "$TARBALL" "$TAG" "$ENVIRONMENT" "$PORT" "$DOMAIN" "$SSL_EMAIL"

log_info "完成: ${TAG} → ${ENVIRONMENT}"

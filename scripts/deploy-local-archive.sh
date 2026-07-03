#!/bin/bash
# 蓝绿部署：解压 tarball 到空闲槽位 → 初始化 → 健康检查 → 切换 Nginx → 停止旧槽位
# 用法: ./scripts/deploy-local-archive.sh <archive.tar.gz> [--env production|test] [--version v1.0.0]

set -euo pipefail

_SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=lib/blue-green.sh
source "${_SCRIPT_DIR}/lib/blue-green.sh"

if [ -f /etc/alice/deploy.env ]; then
  set -a
  # shellcheck source=/dev/null
  . /etc/alice/deploy.env
  set +a
fi

# shellcheck source=lib/log.sh
source "${_SCRIPT_DIR}/lib/log.sh"

ARCHIVE=""
ENVIRONMENT="production"
VERSION=""

while [[ $# -gt 0 ]]; do
  case $1 in
    --env)
      ENVIRONMENT="$2"
      shift 2
      ;;
    --version)
      VERSION="$2"
      shift 2
      ;;
    --help|-h)
      echo "用法: $0 <archive.tar.gz> [--env production|test] [--version v1.0.0]"
      exit 0
      ;;
    -*)
      log_error "未知选项: $1"
      exit 1
      ;;
    *)
      ARCHIVE="$1"
      shift
      ;;
  esac
done

if [ -z "$ARCHIVE" ] || [ ! -f "$ARCHIVE" ]; then
  log_error "请指定有效的 tarball 路径"
  exit 1
fi

if [ "$ENVIRONMENT" != "production" ] && [ "$ENVIRONMENT" != "test" ]; then
  log_error "无效的环境: ${ENVIRONMENT}（仅支持 production 或 test）"
  exit 1
fi

if [ -z "$VERSION" ]; then
  VERSION="$(basename "$ARCHIVE" .tar.gz)"
  VERSION="${VERSION#alice-}"
fi

bg_load_env "$ENVIRONMENT"

if [ "$ENVIRONMENT" = "test" ]; then
  RELEASE_BACKUP_DIR="/backups/test"
else
  RELEASE_BACKUP_DIR="/var/backups/alice"
fi

log_info "蓝绿部署: $ENVIRONMENT"
log_info "版本: $VERSION"
log_info "归档: $ARCHIVE"

bg_migrate_legacy_if_needed

DEPLOY_SLOT="$(bg_resolve_deploy_slot)"
ACTIVE_SLOT="$(bg_get_active_slot)"
DEPLOY_DIR="$(bg_slot_dir "$DEPLOY_SLOT")"
DEPLOY_PORT="$(bg_slot_port "$DEPLOY_SLOT")"
DEPLOY_APP="$(bg_slot_app "$DEPLOY_SLOT")"

log_info "当前活跃槽位: ${ACTIVE_SLOT}"
log_info "本次部署槽位: ${DEPLOY_SLOT} -> ${DEPLOY_DIR}（端口 ${DEPLOY_PORT}）"

TMP_DIR=$(mktemp -d)
trap 'rm -rf "$TMP_DIR"' EXIT

log_info "解压..."
EXTRACT_DIR="${TMP_DIR}/extracted"
mkdir -p "$EXTRACT_DIR"
tar -xzf "$ARCHIVE" -C "$EXTRACT_DIR"

if bg_slot_has_release "$DEPLOY_SLOT"; then
  BACKUP_NAME="$(bg_slot_app "$DEPLOY_SLOT")-$(date +%Y%m%d-%H%M%S)"
  mkdir -p "$RELEASE_BACKUP_DIR"
  log_info "备份槽位 ${DEPLOY_SLOT} -> ${RELEASE_BACKUP_DIR}/${BACKUP_NAME}.tar.gz"
  tar -czf "${RELEASE_BACKUP_DIR}/${BACKUP_NAME}.tar.gz" \
    --exclude='node_modules' \
    --exclude='packages/server/src/generated' \
    -C "$DEPLOY_DIR" . 2>/dev/null || true
fi

log_info "同步文件到 ${DEPLOY_DIR}..."
mkdir -p "$DEPLOY_DIR"

for keep in .env .env.production .env.test logs; do
  if [ -e "${DEPLOY_DIR}/${keep}" ]; then
    cp -a "${DEPLOY_DIR}/${keep}" "${TMP_DIR}/${keep}.bak" 2>/dev/null || true
  fi
done

rsync -a --delete \
  --exclude 'node_modules' \
  --exclude '.env' \
  --exclude '.env.production' \
  --exclude '.env.test' \
  --exclude 'logs' \
  "$EXTRACT_DIR/" "$DEPLOY_DIR/"

for keep in logs; do
  if [ -e "${TMP_DIR}/${keep}.bak" ]; then
    cp -a "${TMP_DIR}/${keep}.bak" "${DEPLOY_DIR}/${keep}"
  fi
done

if ! bg_link_shared_env "$DEPLOY_DIR"; then
  log_warn "未找到 ${DEPLOY_DIR}/.env，请确认共享 env 或 .env.production/.env.test 已配置"
  EXAMPLE_FILE="${DEPLOY_DIR}/.env.example"
  if [ ! -f "$EXAMPLE_FILE" ]; then
    if [ "$ENVIRONMENT" = "test" ]; then
      cat > "$EXAMPLE_FILE" <<EOF
PORT=3602
HOST=0.0.0.0
LOG_LEVEL=info
NODE_ENV=test
OPENAI_API_KEY=
OPENAI_BASE_URL=https://open.bigmodel.cn/api/paas/v4
OPENAI_TTS_MODEL=glm-tts
OPENAI_TTS_VOICE=female
OPENAI_VISION_MODEL=glm-4v-flash
EOF
    else
      cat > "$EXAMPLE_FILE" <<EOF
PORT=3600
HOST=0.0.0.0
LOG_LEVEL=info
NODE_ENV=production
OPENAI_API_KEY=
OPENAI_BASE_URL=https://open.bigmodel.cn/api/paas/v4
OPENAI_TTS_MODEL=glm-tts
OPENAI_TTS_VOICE=female
OPENAI_VISION_MODEL=glm-4v-flash
EOF
    fi
    log_warn "已创建 .env.example，请配置 ${BG_SHARED_ENV_FILE} 后重新部署"
    exit 1
  fi
fi

log_info "执行平台相关初始化（依赖安装）..."
ENVIRONMENT="$ENVIRONMENT" APP_DIR="$DEPLOY_DIR" bash "${DEPLOY_DIR}/scripts/install-production.sh"

if ! command -v pm2 &>/dev/null; then
  log_error "PM2 未安装，请先安装: pnpm add -g pm2"
  exit 1
fi

bg_start_slot_app "$DEPLOY_SLOT"

if ! bg_wait_health "$DEPLOY_PORT" 30 2; then
  log_error "新版本健康检查失败，回滚 PM2 进程 ${DEPLOY_APP}"
  bg_stop_slot_app "$DEPLOY_SLOT"
  exit 1
fi

PREVIOUS_SLOT="$ACTIVE_SLOT"

if ! bg_switch_nginx_slot "$DEPLOY_SLOT"; then
  log_error "Nginx 切换失败，回滚 PM2 进程 ${DEPLOY_APP}"
  bg_stop_slot_app "$DEPLOY_SLOT"
  exit 1
fi

# 检测是否有 Nginx alice-managed 配置（无 Nginx 时蓝绿无法切换流量）
_HAS_NGINX=0
if bg_find_nginx_conf &>/dev/null; then
  _HAS_NGINX=1
fi

bg_set_active_slot "$DEPLOY_SLOT"

if [ "$PREVIOUS_SLOT" != "$DEPLOY_SLOT" ] && bg_slot_has_release "$PREVIOUS_SLOT"; then
  if [ "$_HAS_NGINX" = "1" ]; then
    log_info "停止旧槽位 ${PREVIOUS_SLOT}"
    bg_stop_slot_app "$PREVIOUS_SLOT"
  else
    log_info "未配置 Nginx，跳过停止旧槽位 ${PREVIOUS_SLOT}（保留端口 $(bg_slot_port "$PREVIOUS_SLOT") 服务）"
  fi
fi

log_info "蓝绿部署完成: ${VERSION} (${ENVIRONMENT})"
log_info "活跃槽位: ${DEPLOY_SLOT}（端口 ${DEPLOY_PORT}，PM2 ${DEPLOY_APP}）"
log_info "前端静态文件: ${DEPLOY_DIR}/packages/client/dist"
log_info "健康检查: curl http://localhost:${DEPLOY_PORT}/health"

#!/bin/bash
# 从 0 到 1 的 CI 非交互式首次引导部署
# 用法:
#   ENVIRONMENT=production \
#   OPENAI_API_KEY=xxx \
#   PORT=3600 \
#   DOMAIN=example.com \
#   SSL_EMAIL=admin@example.com \
#   bash /tmp/alice-deploy/scripts/bootstrap-ci.sh /tmp/alice-deploy/alice-v1.0.0.tar.gz
#
# 必填环境变量:
#   ENVIRONMENT        production | test
# 可选环境变量:
#   PORT                         服务端口（production 默认 3600，test 默认 3602）
#   OPENAI_API_KEY               智谱 API Key
#   OPENAI_BASE_URL / OPENAI_TTS_* / OPENAI_VISION_*
#   DOMAIN             Nginx 域名（留空跳过 Nginx 配置）
#   SSL_EMAIL          SSL 证书邮箱（有 DOMAIN 时必填，留空跳过申请证书）

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=lib/log.sh
source "${SCRIPT_DIR}/lib/log.sh"


# ── 参数解析 ──────────────────────────────────────────────────────────────────

ARCHIVE=""
while [[ $# -gt 0 ]]; do
  case $1 in
    --env) ENVIRONMENT="$2"; shift 2 ;;
    --version) VERSION="$2"; shift 2 ;;
    --) shift; break ;;
    -*) log_die "未知选项: $1" ;;
    *) ARCHIVE="$1"; shift ;;
  esac
done

# ── 校验 ──────────────────────────────────────────────────────────────────────

[ "$(id -u)" -eq 0 ] || log_die "请以 root 身份运行"

ENVIRONMENT="${ENVIRONMENT:-production}"
[[ "$ENVIRONMENT" =~ ^(production|test)$ ]] || log_die "ENVIRONMENT 必须是 production 或 test"

if [ -z "$ARCHIVE" ] || [ ! -f "$ARCHIVE" ]; then
  log_die "请传入有效的 tarball 路径，例如: $0 /tmp/alice-deploy/alice-v1.0.0.tar.gz"
fi

# shellcheck source=lib/blue-green.sh
source "${SCRIPT_DIR}/lib/blue-green.sh"
bg_load_env "$ENVIRONMENT"

APP_DIR="$(bg_slot_dir a)"
APP_NAME="$(bg_slot_app a)"
DEFAULT_PORT="$(bg_slot_port a)"
PORT="${PORT:-$DEFAULT_PORT}"

if [ "$ENVIRONMENT" = "test" ]; then
  RELEASE_BACKUP_DIR="/backups/test"
else
  RELEASE_BACKUP_DIR="/var/backups/alice"
fi

if [ -z "${VERSION:-}" ]; then
  VERSION="$(basename "$ARCHIVE" .tar.gz)"
  VERSION="${VERSION#alice-}"
fi

log_info "===== Alice 0-1 Bootstrap ====="
log_info "版本:       $VERSION"
log_info "环境:       $ENVIRONMENT"
log_info "目标目录:   $APP_DIR"
log_info "端口:       $PORT"
[ -n "${DOMAIN:-}" ] && log_info "域名:       $DOMAIN"

# ── 系统依赖 ──────────────────────────────────────────────────────────────────

install_system_deps() {
  log_info "安装系统依赖..."
  apt-get update -qq

  for pkg in git curl rsync; do
    command -v "$pkg" &>/dev/null || apt-get install -y -qq "$pkg"
  done

  local pkgs=""
  dpkg -l nginx   &>/dev/null || pkgs="$pkgs nginx"
  dpkg -l ufw     &>/dev/null || pkgs="$pkgs ufw"
  dpkg -l certbot &>/dev/null || pkgs="$pkgs certbot python3-certbot-nginx"

  if [ -n "$pkgs" ]; then
    # shellcheck disable=SC2086
    apt-get install -y -qq $pkgs
  fi

  systemctl enable --now nginx
  log_info "系统依赖就绪"
}

install_nodejs() {
  if command -v node &>/dev/null; then
    local ver
    ver="$(node -v | sed 's/v//' | cut -d. -f1)"
    if [ "$ver" -ge 22 ]; then
      log_info "Node.js $(node -v) 已安装"
      return
    fi
    log_warn "Node.js $(node -v) 版本过低，升级到 22..."
    apt-get remove -y nodejs npm libnode-dev 2>/dev/null || true
    apt-get autoremove -y 2>/dev/null || true
  fi
  log_info "安装 Node.js 22 (NodeSource)..."
  curl -fsSL https://deb.nodesource.com/setup_22.x | bash -
  apt-get install -y nodejs
  log_info "Node.js $(node -v) 安装完成"
}

install_pnpm() {
  if command -v pnpm &>/dev/null; then
    log_info "pnpm 已安装"
    return
  fi
  log_info "安装 pnpm..."
  npm install -g pnpm
}

install_pm2() {
  if command -v pm2 &>/dev/null; then
    log_info "PM2 已安装"
    return
  fi
  log_info "安装 PM2..."
  npm install -g pm2
  local startup_cmd
  startup_cmd="$(pm2 startup systemd -u root --hp /root 2>/dev/null | grep -E '^sudo env PATH' || true)"
  if [ -n "$startup_cmd" ]; then
    bash -c "$startup_cmd" || true
  fi
}

# ── 部署目录 + env ────────────────────────────────────────────────────────────

deploy_archive() {
  log_info "解压 $ARCHIVE -> $APP_DIR ..."
  local tmp_extract
  tmp_extract="$(mktemp -d)"
  tar -xzf "$ARCHIVE" -C "$tmp_extract"

  if [ -d "$APP_DIR" ] && [ -f "${APP_DIR}/package.json" ]; then
    local bak="${APP_NAME}-$(date +%Y%m%d-%H%M%S)"
    mkdir -p "$RELEASE_BACKUP_DIR"
    log_info "备份当前版本 -> ${RELEASE_BACKUP_DIR}/${bak}.tar.gz"
    tar -czf "${RELEASE_BACKUP_DIR}/${bak}.tar.gz" \
      --exclude='node_modules' \
      -C "$APP_DIR" . 2>/dev/null || true
  fi

  mkdir -p "$APP_DIR"

  for keep in .env .env.production .env.test logs; do
    [ -e "${APP_DIR}/${keep}" ] && cp -a "${APP_DIR}/${keep}" "${tmp_extract}/${keep}.bak" 2>/dev/null || true
  done

  rsync -a --delete \
    --exclude 'node_modules' \
    --exclude '.env' \
    --exclude '.env.production' \
    --exclude '.env.test' \
    --exclude 'logs' \
    "$tmp_extract/" "$APP_DIR/"

  for keep in .env .env.production .env.test logs; do
    [ -e "${tmp_extract}/${keep}.bak" ] && cp -a "${tmp_extract}/${keep}.bak" "${APP_DIR}/${keep}" || true
  done

  rm -rf "$tmp_extract"
}

sync_env_file() {
  if [ ! -f "${SCRIPT_DIR}/sync-env-ci.sh" ]; then
    log_die "未找到 ${SCRIPT_DIR}/sync-env-ci.sh"
  fi
  BOOTSTRAP_UPSERT=true SYNC_FORCE=true bash "${SCRIPT_DIR}/sync-env-ci.sh"
}

link_env_file() {
  bg_set_active_slot "a"
}

# ── install-production（依赖安装）────────────────────────────────────────────

run_install_production() {
  if [ ! -f "${APP_DIR}/scripts/install-production.sh" ]; then
    log_die "未找到 ${APP_DIR}/scripts/install-production.sh，Release 包可能不完整"
  fi

  ENVIRONMENT="$ENVIRONMENT" APP_DIR="$APP_DIR" \
    bash "${APP_DIR}/scripts/install-production.sh"
}

# ── PM2 ──────────────────────────────────────────────────────────────────────

start_app() {
  bg_start_slot_app "a"
  log_info "PM2 服务已启动（槽位 a: ${APP_NAME}）"
}

# ── 防火墙 ────────────────────────────────────────────────────────────────────

setup_firewall() {
  log_info "配置防火墙..."
  ufw allow 22/tcp  2>/dev/null || true
  ufw allow 80/tcp  2>/dev/null || true
  ufw allow 443/tcp 2>/dev/null || true
  ufw allow "${PORT}"/tcp 2>/dev/null || true
  ufw --force enable 2>/dev/null || true
}

# ── Nginx ─────────────────────────────────────────────────────────────────────

setup_nginx() {
  [ -n "${DOMAIN:-}" ] || { log_warn "未设置 DOMAIN，跳过 Nginx 配置"; return; }

  local conf="/etc/nginx/sites-available/${DOMAIN}"

  if [ -f "$conf" ] && grep -q "alice-managed-v3" "$conf" 2>/dev/null; then
    log_info "Nginx 蓝绿配置已存在（${DOMAIN}），跳过重写"
  else
    log_info "写入 Nginx 蓝绿配置 for ${DOMAIN}..."
    bg_render_nginx_site "$DOMAIN" "$PORT" "${APP_DIR}/packages/client/dist" > "$conf"
  fi

  ln -sf "$conf" "/etc/nginx/sites-enabled/${DOMAIN}"
  rm -f /etc/nginx/sites-enabled/default
  nginx -t
  systemctl reload nginx

  if [ -n "${SSL_EMAIL:-}" ]; then
    if ! certbot certificates 2>/dev/null | grep -q "$DOMAIN"; then
      log_info "申请 SSL 证书 for ${DOMAIN}..."
      certbot --nginx -d "$DOMAIN" --non-interactive --agree-tos --redirect -m "$SSL_EMAIL"
    else
      log_info "SSL 证书已存在，跳过申请"
    fi
  else
    log_warn "未设置 SSL_EMAIL，跳过 SSL 证书申请"
  fi

  log_info "Nginx 配置完成"
}

# ── 主流程 ────────────────────────────────────────────────────────────────────

main() {
  install_system_deps
  install_nodejs
  install_pnpm
  install_pm2
  deploy_archive
  sync_env_file
  link_env_file
  run_install_production
  start_app
  setup_firewall
  setup_nginx

  bg_load_env "$ENVIRONMENT"
  if ! bg_wait_health "$(bg_slot_port a)" 30 2; then
    log_die "应用未通过健康检查，请查看上方 PM2 日志"
  fi

  log_info "===== Bootstrap 完成: ${VERSION} (${ENVIRONMENT}) -> ${APP_DIR} ====="
  log_info "健康检查: curl http://localhost:${PORT}/health"
  [ -n "${DOMAIN:-}" ] && log_info "访问地址: https://${DOMAIN}"
  log_info "查看日志: pm2 logs ${APP_NAME}"
}

main

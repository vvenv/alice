#!/bin/bash
# 从 0 到 1 的 CI 非交互式首次引导部署
# 用法:
#   ENVIRONMENT=production \
#   DB_PASSWORD=xxx \
#   JWT_SECRET=xxx \
#   OPENAI_API_KEY=xxx \
#   PORT=3400 \
#   DOMAIN=example.com \
#   SSL_EMAIL=admin@example.com \
#   bash /tmp/regora-deploy/scripts/bootstrap-ci.sh /tmp/regora-deploy/regora-v1.0.0.tar.gz
#
# 必填环境变量:
#   ENVIRONMENT        production | test
#   DB_PASSWORD        数据库密码
#   JWT_SECRET                   JWT 签名密钥（建议 64 字符随机串）
#   TENANT_SECRET_ENCRYPTION_KEY 租户 secret AES-GCM 密钥（32 字节 hex；留空则保留已有或自动生成）
# 可选环境变量:
#   PORT                         服务端口（production 默认 3400，test 默认 3402）
#   OPENAI_API_KEY               LLM API Key（合规分析 Agent 需要）
#   OPENAI_EMBEDDING_API_KEY     Embedding API Key（默认回退 OPENAI_API_KEY）
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

[ -n "${DB_PASSWORD:-}" ] || log_die "必须设置 DB_PASSWORD"
[ -n "${JWT_SECRET:-}" ]  || log_die "必须设置 JWT_SECRET"

if [ -z "$ARCHIVE" ] || [ ! -f "$ARCHIVE" ]; then
  log_die "请传入有效的 tarball 路径，例如: $0 /tmp/regora-deploy/regora-v1.0.0.tar.gz"
fi

# shellcheck source=lib/blue-green.sh
source "${SCRIPT_DIR}/lib/blue-green.sh"
# shellcheck source=lib/prisma-migrate.sh
source "${SCRIPT_DIR}/lib/prisma-migrate.sh"
bg_load_env "$ENVIRONMENT"

APP_DIR="$(bg_slot_dir a)"
APP_NAME="$(bg_slot_app a)"
DEFAULT_PORT="$(bg_slot_port a)"
PORT="${PORT:-$DEFAULT_PORT}"

DB_USER="regora"

if [ "$ENVIRONMENT" = "test" ]; then
  DB_NAME="regora_test"
  BACKUP_DIR="/backups/test"
  ENV_FILE=".env.test"
else
  DB_NAME="regora"
  BACKUP_DIR="/var/backups/regora"
  ENV_FILE=".env.production"
fi

if [ -z "${VERSION:-}" ]; then
  VERSION="$(basename "$ARCHIVE" .tar.gz)"
  VERSION="${VERSION#regora-}"
fi

log_info "===== Regora 0-1 Bootstrap ====="
log_info "版本:       $VERSION"
log_info "环境:       $ENVIRONMENT"
log_info "目标目录:   $APP_DIR"
log_info "数据库:     $DB_NAME"
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
  dpkg -l postgresql &>/dev/null || pkgs="$pkgs postgresql postgresql-contrib"
  dpkg -l postgresql-16 &>/dev/null || pkgs="$pkgs postgresql-16"  # pgvector 需要 PostgreSQL 16+
  dpkg -l postgresql-16-pgvector &>/dev/null || pkgs="$pkgs postgresql-16-pgvector"
  dpkg -l nginx      &>/dev/null || pkgs="$pkgs nginx"
  dpkg -l redis-server &>/dev/null || pkgs="$pkgs redis-server"
  dpkg -l ufw        &>/dev/null || pkgs="$pkgs ufw"
  dpkg -l certbot    &>/dev/null || pkgs="$pkgs certbot python3-certbot-nginx"

  if [ -n "$pkgs" ]; then
    # shellcheck disable=SC2086
    apt-get install -y -qq $pkgs
  fi

  systemctl enable --now redis-server postgresql nginx
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
  pm2 startup systemd -u root --hp /root | tail -n 1 | bash || true
}

# ── 数据库 ────────────────────────────────────────────────────────────────────

grant_database_privileges() {
  sudo -u postgres psql -c "ALTER DATABASE $DB_NAME OWNER TO $DB_USER;"
  sudo -u postgres psql -d "$DB_NAME" -c "ALTER SCHEMA public OWNER TO $DB_USER;"
  sudo -u postgres psql -c "GRANT ALL PRIVILEGES ON DATABASE $DB_NAME TO $DB_USER;"
  sudo -u postgres psql -d "$DB_NAME" -c "GRANT ALL ON SCHEMA public TO $DB_USER;"
  sudo -u postgres psql -d "$DB_NAME" -c "ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON TABLES TO $DB_USER;"
  sudo -u postgres psql -d "$DB_NAME" -c "ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON SEQUENCES TO $DB_USER;"
}

enable_pgvector_extension() {
  log_info "启用 pgvector 扩展..."
  if ! sudo -u postgres psql -d "$DB_NAME" -c "CREATE EXTENSION IF NOT EXISTS vector;"; then
    log_die "无法启用 pgvector 扩展，请确认已安装 postgresql-16-pgvector"
  fi
}

recreate_database() {
  log_warn "重建数据库 ${DB_NAME}（清除未完成的 migration 残留 schema）..."
  sudo -u postgres psql -tAc \
    "SELECT pg_terminate_backend(pid) FROM pg_stat_activity WHERE datname = '$DB_NAME' AND pid <> pg_backend_pid();" \
    >/dev/null 2>&1 || true
  sudo -u postgres psql -c "DROP DATABASE IF EXISTS \"$DB_NAME\";"
  sudo -u postgres psql -c "CREATE DATABASE \"$DB_NAME\";"
  grant_database_privileges
  enable_pgvector_extension
}

# Bootstrap 重试时：库中已有 app schema，但没有任何成功 migration → 清空后重来。
maybe_reset_stale_bootstrap_database() {
  local has_app_schema migration_applied
  has_app_schema="$(
    sudo -u postgres psql -d "$DB_NAME" -tAc \
      "SELECT 1 FROM pg_type WHERE typname = 'Role' LIMIT 1;" 2>/dev/null || true
  )"
  [ "$has_app_schema" = "1" ] || return 0

  migration_applied="$(
    sudo -u postgres psql -d "$DB_NAME" -tAc \
      "SELECT EXISTS (SELECT 1 FROM \"_prisma_migrations\" WHERE finished_at IS NOT NULL);" \
      2>/dev/null || echo 'f'
  )"
  [ "$migration_applied" = "t" ] && return 0

  recreate_database
}

setup_database() {
  log_info "配置 PostgreSQL 数据库..."
  systemctl start postgresql

  local user_exists db_exists
  user_exists="$(sudo -u postgres psql -tAc "SELECT 1 FROM pg_roles WHERE rolname='$DB_USER'" || echo '')"
  db_exists="$(sudo -u postgres psql -tAc "SELECT 1 FROM pg_database WHERE datname='$DB_NAME'" || echo '')"

  if [ "$user_exists" = "1" ]; then
    log_info "用户 $DB_USER 已存在，更新密码..."
    sudo -u postgres psql -c "ALTER USER $DB_USER WITH ENCRYPTED PASSWORD '${DB_PASSWORD}';"
  else
    log_info "创建用户 $DB_USER..."
    sudo -u postgres psql -c "CREATE USER $DB_USER WITH ENCRYPTED PASSWORD '${DB_PASSWORD}';"
    sudo -u postgres psql -c "ALTER USER $DB_USER CREATEDB;"
  fi

  if [ "$db_exists" = "1" ]; then
    log_info "数据库 $DB_NAME 已存在"
  else
    log_info "创建数据库 $DB_NAME..."
    sudo -u postgres psql -c "CREATE DATABASE $DB_NAME;"
  fi

  grant_database_privileges
  enable_pgvector_extension
  maybe_reset_stale_bootstrap_database

  log_info "数据库配置完成"
}

# ── 部署目录 + env ────────────────────────────────────────────────────────────

deploy_archive() {
  log_info "解压 $ARCHIVE -> $APP_DIR ..."
  local tmp_extract
  tmp_extract="$(mktemp -d)"
  tar -xzf "$ARCHIVE" -C "$tmp_extract"

  if [ -d "$APP_DIR" ] && [ -f "${APP_DIR}/package.json" ]; then
    local bak="${APP_NAME}-$(date +%Y%m%d-%H%M%S)"
    mkdir -p "$BACKUP_DIR"
    log_info "备份当前版本 -> ${BACKUP_DIR}/${bak}.tar.gz"
    tar -czf "${BACKUP_DIR}/${bak}.tar.gz" \
      --exclude='node_modules' \
      --exclude='packages/server/src/generated' \
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
  resolve_tenant_secret_encryption_key
  BOOTSTRAP_UPSERT=true SYNC_FORCE=true bash "${SCRIPT_DIR}/sync-env-ci.sh"
}

_read_env_var_from_file() {
  local file="$1" key="$2"
  if [ ! -f "$file" ]; then
    return 1
  fi
  local line
  line="$(grep -E "^${key}=" "$file" | tail -1 || true)"
  [ -n "$line" ] || return 1
  printf '%s' "${line#*=}"
}

resolve_tenant_secret_encryption_key() {
  local target="$BG_SHARED_ENV_FILE"

  if [ -n "${TENANT_SECRET_ENCRYPTION_KEY:-}" ]; then
    return 0
  fi

  local existing=""
  existing="$(_read_env_var_from_file "$target" "TENANT_SECRET_ENCRYPTION_KEY" || true)"
  if [ -n "$existing" ]; then
    TENANT_SECRET_ENCRYPTION_KEY="$existing"
    log_info "保留已有 TENANT_SECRET_ENCRYPTION_KEY"
    return 0
  fi

  if ! command -v openssl >/dev/null 2>&1; then
    log_die "未设置 TENANT_SECRET_ENCRYPTION_KEY 且无法自动生成（缺少 openssl）"
  fi

  TENANT_SECRET_ENCRYPTION_KEY="$(openssl rand -hex 32)"
  log_info "已自动生成 TENANT_SECRET_ENCRYPTION_KEY"
}

seed_default_tenant_if_missing() {
  log_info "检查默认租户..."
  local count
  count="$(sudo -u postgres psql -d "$DB_NAME" -tAc \
    "SELECT COUNT(*) FROM \"Tenant\" WHERE id = '00000000-0000-0000-0000-000000000001';" \
    | tr -d '[:space:]')"
  if [ "$count" != "0" ]; then
    log_info "默认租户已存在"
    return 0
  fi

  log_info "插入默认租户（自托管首次 bootstrap）..."
  sudo -u postgres psql -d "$DB_NAME" -v ON_ERROR_STOP=1 <<'EOSQL'
INSERT INTO "Tenant" (
  "id",
  "slug",
  "name",
  "status",
  "plan",
  "onboarding_completed",
  "created_at",
  "updated_at"
)
VALUES (
  '00000000-0000-0000-0000-000000000001',
  'default',
  '默认租户',
  'active',
  'free',
  false,
  CURRENT_TIMESTAMP,
  CURRENT_TIMESTAMP
)
ON CONFLICT ("id") DO NOTHING;
EOSQL
  log_info "默认租户已就绪"
}

link_env_file() {
  bg_set_active_slot "a"
}

# ── install-production（依赖 + migration）────────────────────────────────────

run_install_production() {
  if [ ! -f "${APP_DIR}/scripts/install-production.sh" ]; then
    log_die "未找到 ${APP_DIR}/scripts/install-production.sh，Release 包可能不完整"
  fi

  if [ -f "${APP_DIR}/.env" ]; then
    set -a
    # shellcheck source=/dev/null
    . "${APP_DIR}/.env"
    set +a
  fi
  prisma_recover_failed_migrations "$APP_DIR"

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
  ufw --force enable 2>/dev/null || true
}

# ── Nginx ─────────────────────────────────────────────────────────────────────

setup_nginx() {
  [ -n "${DOMAIN:-}" ] || { log_warn "未设置 DOMAIN，跳过 Nginx 配置"; return; }

  local conf="/etc/nginx/sites-available/${DOMAIN}"

  if [ -f "$conf" ] && grep -q "regora-managed-v3" "$conf" 2>/dev/null; then
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

# ── 备份定时任务 ──────────────────────────────────────────────────────────────

setup_backup() {
  if [ -f "${APP_DIR}/scripts/backup-cron.sh" ]; then
    log_info "安装备份定时任务..."
    bash "${APP_DIR}/scripts/backup-cron.sh" install --env "$ENVIRONMENT"
  fi
}

# ── 主流程 ────────────────────────────────────────────────────────────────────

main() {
  install_system_deps
  install_nodejs
  install_pnpm
  install_pm2
  setup_database
  deploy_archive
  sync_env_file
  link_env_file
  run_install_production
  seed_default_tenant_if_missing
  start_app
  setup_firewall
  setup_nginx
  setup_backup

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

#!/bin/bash
# 蓝绿部署共享库：双槽目录、端口轮换、Nginx 切换
# 由 deploy-local-archive.sh / bootstrap-ci.sh / health-check.sh source

set -euo pipefail

BG_STATE_DIR="/etc/alice"

# shellcheck source=log.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/log.sh"

bg_info()  { log_info "$@"; }
bg_warn()  { log_warn "$@"; }
bg_error() { log_error "$@"; }

# 加载环境对应的槽位配置（production | test）
bg_load_env() {
  local environment="${1:-production}"

  BG_ENVIRONMENT="$environment"

  case "$BG_ENVIRONMENT" in
    production)
      BG_SLOT_A_DIR="/var/www/alice_a"
      BG_SLOT_B_DIR="/var/www/alice_b"
      BG_SLOT_A_PORT="3600"
      BG_SLOT_B_PORT="3601"
      BG_SLOT_A_APP="alice-a"
      BG_SLOT_B_APP="alice-b"
      BG_SLOT_STATE_FILE="${BG_STATE_DIR}/production-slot"
      BG_LEGACY_DIR="/var/www/alice"
      BG_SHARED_ENV_FILE="${BG_STATE_DIR}/env.production"
      ;;
    test)
      BG_SLOT_A_DIR="/var/www/alice_test_a"
      BG_SLOT_B_DIR="/var/www/alice_test_b"
      BG_SLOT_A_PORT="3602"
      BG_SLOT_B_PORT="3603"
      BG_SLOT_A_APP="alice-test-a"
      BG_SLOT_B_APP="alice-test-b"
      BG_SLOT_STATE_FILE="${BG_STATE_DIR}/test-slot"
      BG_LEGACY_DIR="/var/www/alice_test"
      BG_SHARED_ENV_FILE="${BG_STATE_DIR}/env.test"
      ;;
    *)
      bg_error "无效的环境: ${BG_ENVIRONMENT}（仅支持 production 或 test）"
      return 1
      ;;
  esac
}

bg_ensure_state_dir() {
  mkdir -p "$BG_STATE_DIR"
  chmod 700 "$BG_STATE_DIR"
}

bg_slot_dir() {
  case "$1" in
    a) echo "$BG_SLOT_A_DIR" ;;
    b) echo "$BG_SLOT_B_DIR" ;;
    *) bg_error "无效槽位: $1（仅支持 a 或 b）"; return 1 ;;
  esac
}

bg_slot_port() {
  case "$1" in
    a) echo "$BG_SLOT_A_PORT" ;;
    b) echo "$BG_SLOT_B_PORT" ;;
    *) bg_error "无效槽位: $1"; return 1 ;;
  esac
}

bg_slot_app() {
  case "$1" in
    a) echo "$BG_SLOT_A_APP" ;;
    b) echo "$BG_SLOT_B_APP" ;;
    *) bg_error "无效槽位: $1"; return 1 ;;
  esac
}

bg_get_active_slot() {
  if [ -f "$BG_SLOT_STATE_FILE" ]; then
    local slot
    slot="$(tr -d '[:space:]' < "$BG_SLOT_STATE_FILE")"
    if [ "$slot" = "a" ] || [ "$slot" = "b" ]; then
      echo "$slot"
      return 0
    fi
  fi
  echo "a"
}

bg_get_inactive_slot() {
  local active
  active="$(bg_get_active_slot)"
  if [ "$active" = "a" ]; then
    echo "b"
  else
    echo "a"
  fi
}

bg_set_active_slot() {
  local slot="$1"
  bg_ensure_state_dir
  echo "$slot" > "$BG_SLOT_STATE_FILE"
}

# 将旧版单目录部署迁移到槽位 a
bg_migrate_legacy_if_needed() {
  local slot_a_dir
  slot_a_dir="$(bg_slot_dir a)"

  if [ -d "$BG_LEGACY_DIR" ] && [ -f "${BG_LEGACY_DIR}/package.json" ] && [ ! -f "${slot_a_dir}/package.json" ]; then
    bg_info "迁移旧版目录 ${BG_LEGACY_DIR} -> ${slot_a_dir}"
    mkdir -p "$slot_a_dir"
    rsync -a \
      --exclude 'node_modules' \
      "${BG_LEGACY_DIR}/" "${slot_a_dir}/"

    if [ -f "${BG_LEGACY_DIR}/.env" ] && [ ! -f "$BG_SHARED_ENV_FILE" ]; then
      cp -a "${BG_LEGACY_DIR}/.env" "$BG_SHARED_ENV_FILE"
      chmod 600 "$BG_SHARED_ENV_FILE"
      bg_info "已迁移共享 env -> ${BG_SHARED_ENV_FILE}"
    fi

    bg_set_active_slot "a"

    if command -v pm2 &>/dev/null; then
      pm2 delete alice 2>/dev/null || true
      pm2 delete alice-test 2>/dev/null || true
      pm2 save 2>/dev/null || true
    fi
  fi

  if [ ! -f "$BG_SLOT_STATE_FILE" ]; then
    bg_set_active_slot "a"
  fi
}

bg_slot_has_release() {
  local slot="$1"
  local dir
  dir="$(bg_slot_dir "$slot")"
  [ -f "${dir}/package.json" ] && [ -d "${dir}/packages/server/dist" ]
}

# 选择本次部署目标槽位：优先空闲槽；首次部署用 a
bg_resolve_deploy_slot() {
  local active inactive
  active="$(bg_get_active_slot)"
  inactive="$(bg_get_inactive_slot)"

  if ! bg_slot_has_release "a" && ! bg_slot_has_release "b"; then
    echo "a"
    return 0
  fi

  if ! bg_slot_has_release "$active"; then
    echo "$active"
    return 0
  fi

  echo "$inactive"
}

bg_link_shared_env() {
  local slot_dir="$1"

  if [ -f "$BG_SHARED_ENV_FILE" ]; then
    ln -sf "$BG_SHARED_ENV_FILE" "${slot_dir}/.env"
    return 0
  fi

  local active_slot active_dir
  active_slot="$(bg_get_active_slot)"
  active_dir="$(bg_slot_dir "$active_slot")"

  if [ -f "${active_dir}/.env" ]; then
    cp -a "${active_dir}/.env" "$BG_SHARED_ENV_FILE"
    chmod 600 "$BG_SHARED_ENV_FILE"
    ln -sf "$BG_SHARED_ENV_FILE" "${slot_dir}/.env"
    bg_info "已创建共享 env: ${BG_SHARED_ENV_FILE}"
    return 0
  fi

  if [ -f "${slot_dir}/.env.production" ]; then
    ln -sf ".env.production" "${slot_dir}/.env"
    return 0
  fi

  if [ -f "${slot_dir}/.env.test" ]; then
    ln -sf ".env.test" "${slot_dir}/.env"
    return 0
  fi

  return 1
}

bg_start_slot_app() {
  local slot="$1"
  local dir port app_name node_env max_mem

  dir="$(bg_slot_dir "$slot")"
  port="$(bg_slot_port "$slot")"
  app_name="$(bg_slot_app "$slot")"

  if [ "$BG_ENVIRONMENT" = "test" ]; then
    node_env="test"
    max_mem="500M"
    node_options=""
  else
    node_env="production"
    max_mem="2G"
    node_options="--max-old-space-size=1536"
  fi

  mkdir -p "${dir}/logs"

  if pm2 describe "$app_name" &>/dev/null; then
    bg_info "删除旧 PM2 进程: ${app_name}"
    pm2 delete "$app_name" || true
  fi

  bg_info "启动 ${app_name}（端口 ${port}）..."
  PORT="$port" NODE_ENV="$node_env" NODE_OPTIONS="$node_options" pm2 start "${dir}/packages/server/dist/index.js" \
    --name "$app_name" \
    --cwd "$dir" \
    --max-memory-restart "$max_mem" \
    --merge-logs \
    --log-date-format "YYYY-MM-DD HH:mm:ss Z" \
    --error "${dir}/logs/pm2-error.log" \
    --output "${dir}/logs/pm2-out.log"

  pm2 save
}

bg_stop_slot_app() {
  local slot="$1"
  local app_name
  app_name="$(bg_slot_app "$slot")"

  if pm2 describe "$app_name" &>/dev/null; then
    bg_info "停止 PM2 进程: ${app_name}"
    pm2 delete "$app_name" || true
    pm2 save
  fi
}

bg_wait_health() {
  local port="$1"
  local max_attempts="${2:-30}"
  local interval="${3:-2}"
  local attempt=1

  while [ "$attempt" -le "$max_attempts" ]; do
    if curl -fsS "http://127.0.0.1:${port}/health" >/dev/null 2>&1; then
      bg_info "健康检查通过: 127.0.0.1:${port}/health"
      return 0
    fi
    sleep "$interval"
    attempt=$((attempt + 1))
  done

  bg_error "健康检查失败: 127.0.0.1:${port}/health（${max_attempts} 次）"
  bg_show_pm2_diagnostics "$port"
  return 1
}

bg_show_pm2_diagnostics() {
  local port="${1:-}"
  local app_name

  if ! command -v pm2 >/dev/null 2>&1; then
    return 0
  fi

  bg_warn "PM2 状态:"
  pm2 list 2>/dev/null || true

  if [ -n "${BG_ENVIRONMENT:-}" ]; then
    app_name="$(bg_slot_app "$(bg_get_active_slot)")"
    if pm2 describe "$app_name" &>/dev/null; then
      bg_warn "最近日志 (${app_name}):"
      pm2 logs "$app_name" --nostream --lines 30 2>/dev/null || true
    fi
  fi

  if [ -n "$port" ]; then
    bg_warn "端口监听:"
    ss -ltnp 2>/dev/null | grep ":${port} " || true
  fi
}

bg_resolve_nginx_conf_path() {
  local conf="$1"
  if [ -L "$conf" ]; then
    readlink -f "$conf"
  else
    echo "$conf"
  fi
}

bg_find_nginx_conf() {
  local conf
  for conf in /etc/nginx/sites-enabled/* /etc/nginx/sites-available/*; do
    [ -f "$conf" ] || continue
    if grep -q "alice-managed" "$conf" 2>/dev/null; then
      bg_resolve_nginx_conf_path "$conf"
      return 0
    fi
  done
  return 1
}

# 收集需同步的 Nginx 配置（含 Certbot 拆出的 SSL 片段，避免 HTTPS 仍指向旧端口导致 502）
bg_collect_nginx_confs() {
  local domain="$1"
  local conf resolved seen="|"

  for conf in /etc/nginx/sites-enabled/* /etc/nginx/sites-available/*; do
    [ -f "$conf" ] || continue
    resolved="$(bg_resolve_nginx_conf_path "$conf")"
    case "$seen" in *"|${resolved}|"*) continue ;; esac

    if grep -q "alice-managed" "$resolved" 2>/dev/null; then
      echo "$resolved"
      seen="${seen}${resolved}|"
      continue
    fi

    if [ -n "$domain" ] && grep -qE "server_name[[:space:]]+.*(^|[[:space:]])${domain}([[:space:]]|;)" "$resolved" 2>/dev/null; then
      if grep -qE "proxy_pass|alice_backend|127\\.0\\.0\\.1:(3600|3602|3601|3603)" "$resolved" 2>/dev/null; then
        echo "$resolved"
        seen="${seen}${resolved}|"
      fi
    fi
  done
}

# 更新 upstream 端口、静态 root，以及 Certbot 在 443 块中内联的 proxy_pass
bg_patch_nginx_backend_routes() {
  local conf="$1"
  local port="$2"
  local root="$3"

  sed -i -E \
    -e "s|server 127\\.0\\.0\\.1:[0-9]+;|server 127.0.0.1:${port};|g" \
    -e "s|root /var/www/[^;]+;|root ${root};|g" \
    -e "s|proxy_pass http://127\\.0\\.0\\.1:[0-9]+;|proxy_pass http://127.0.0.1:${port};|g" \
    -e "s|proxy_pass http://localhost:[0-9]+;|proxy_pass http://127.0.0.1:${port};|g" \
    "$conf"
}

bg_get_active_port() {
  local slot
  slot="$(bg_get_active_slot)"
  bg_slot_port "$slot"
}

# 生成 Nginx 站点配置（alice-managed-v3，蓝绿 upstream）
bg_render_nginx_site() {
  local domain="$1"
  local active_port="$2"
  local active_root="$3"

  cat <<NGINX
# alice-managed-v3
upstream alice_backend {
    server 127.0.0.1:${active_port};
    keepalive 8;
}

server {
    listen 80;
    server_name ${domain};

    root ${active_root};
    index index.html;

    client_max_body_size 100m;

    gzip on;
    gzip_vary on;
    gzip_proxied any;
    gzip_comp_level 6;
    gzip_min_length 1024;
    gzip_types text/plain text/css text/xml application/json application/javascript application/xml+rss application/atom+xml image/svg+xml;

    location ~ ^/api/(documents|search) {
        proxy_pass http://alice_backend;
        proxy_http_version 1.1;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_read_timeout 120s;
        proxy_send_timeout 120s;
        proxy_buffering off;
        gzip off;
    }

    location /api/ {
        proxy_pass http://alice_backend;
        proxy_http_version 1.1;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }

    location = /health {
        proxy_pass http://alice_backend;
        proxy_set_header Host \$host;
    }

    location ^~ /assets/ {
        expires 1y;
        add_header Cache-Control "public, max-age=31536000, immutable" always;
        try_files \$uri =404;
    }

    location / {
        try_files \$uri /index.html;
        add_header Cache-Control "no-cache" always;
    }
}
NGINX
}

# 将 Nginx 切换到指定槽位（sed 更新端口与静态 root，保留 Certbot SSL 配置）
bg_switch_nginx_slot() {
  local slot="$1"
  local port root conf domain available extra_conf patched="|"

  port="$(bg_slot_port "$slot")"
  root="$(bg_slot_dir "$slot")/packages/client/dist"

  if ! conf="$(bg_find_nginx_conf)"; then
    bg_warn "未找到 alice-managed Nginx 配置，跳过流量切换"
    return 0
  fi

  domain="$(grep -m1 'server_name' "$conf" | sed -E 's/.*server_name[[:space:]]+([^;]+);.*/\1/' | awk '{print $1}')"

  bg_info "切换 Nginx 流量 -> 槽位 ${slot}（端口 ${port}，root ${root}）"

  if grep -q "alice-managed-v3" "$conf" 2>/dev/null; then
    :
  elif grep -q "alice-managed" "$conf" 2>/dev/null; then
    # 从 v2 就地升级为 v3：插入 upstream，proxy_pass 改走 upstream（保留 SSL 等 Certbot 改动）
    if ! grep -q "upstream alice_backend" "$conf" 2>/dev/null; then
      sed -i "/# alice-managed/a\\
upstream alice_backend {\\
    server 127.0.0.1:${port};\\
    keepalive 8;\\
}\\
" "$conf"
    else
      sed -i -E "s|server 127\\.0\\.0\\.1:[0-9]+;|server 127.0.0.1:${port};|g" "$conf"
    fi
    sed -i -E \
      -e "s|proxy_pass http://localhost:[0-9]+;|proxy_pass http://alice_backend;|g" \
      -e "s|proxy_pass http://127\\.0\\.0\\.1:[0-9]+;|proxy_pass http://alice_backend;|g" \
      -e "s|root /var/www/[^;]+;|root ${root};|g" \
      "$conf"
    sed -i 's/# alice-managed-v2/# alice-managed-v3/' "$conf" 2>/dev/null || \
      sed -i 's/# alice-managed/# alice-managed-v3/' "$conf" 2>/dev/null || true
  elif [ -n "$domain" ]; then
    available="/etc/nginx/sites-available/${domain}"
    bg_render_nginx_site "$domain" "$port" "$root" > "$available"
    ln -sf "$available" "/etc/nginx/sites-enabled/${domain}"
    rm -f /etc/nginx/sites-enabled/default 2>/dev/null || true
    conf="$(bg_resolve_nginx_conf_path "$available")"
  else
    bg_warn "无法识别 Nginx 配置格式，跳过流量切换"
    return 0
  fi

  bg_patch_nginx_backend_routes "$conf" "$port" "$root"
  patched="|${conf}|"

  while IFS= read -r extra_conf; do
    [ -z "$extra_conf" ] && continue
    extra_conf="$(bg_resolve_nginx_conf_path "$extra_conf")"
    case "$patched" in *"|${extra_conf}|"*) continue ;; esac
    bg_info "同步 Certbot/SSL Nginx 配置: ${extra_conf}"
    bg_patch_nginx_backend_routes "$extra_conf" "$port" "$root"
    patched="${patched}${extra_conf}|"
  done < <(bg_collect_nginx_confs "$domain")

  nginx -t
  systemctl reload nginx
  bg_info "Nginx 已切换至槽位 ${slot}"
}

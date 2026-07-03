#!/bin/bash
# 数据库还原脚本（在服务器上以 root 运行）
# 从 backup.sh 产物还原 PostgreSQL + Redis，与备份对称。
#
# 用法:
#   ./scripts/restore.sh --env production --list                 # 列出可用备份
#   ./scripts/restore.sh --env production --latest               # 还原最新 PG 备份
#   ./scripts/restore.sh --env production --file <path>          # 还原指定 PG 备份
#   ./scripts/restore.sh --env production --file <pg.dump> --redis-file <rdb.gz>
#   ./scripts/restore.sh --env production --latest --only-pg     # 仅还原 PG
#   ./scripts/restore.sh --env production --redis-file <rdb.gz> --only-redis
#   ./scripts/restore.sh --env production --latest --yes         # 跳过确认（自动化/远程编排）
#   ./scripts/restore.sh --env production --latest --no-safety-backup
#
# 行为:
#   - 默认在还原前自动做一次「安全备份」(regora_backup_safety_<ts>.dump)，作为回滚兜底。
#   - PG 还原：终止连接 → DROP/CREATE DATABASE（WITH FORCE）→ pg_restore → 把对象 re-own 给 regora。
#     （不用 --clean，避免 pgvector 扩展的 DROP EXTENSION 依赖冲突；清库重建最干净。）
#   - Redis 还原：停服 → 用备份 RDB 替换 dump.rdb → 启服。
#   - 破坏性操作前要求交互确认（输入大写 YES），非交互终端需 --yes。

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=lib/log.sh
source "${SCRIPT_DIR}/lib/log.sh"

ENVIRONMENT="production"
PG_FILE=""
REDIS_FILE=""
USE_LATEST=0
ONLY_PG=0
ONLY_REDIS=0
ASSUME_YES=0
NO_SAFETY_BACKUP=0
LIST_ONLY=0

# 应用 DB 用户恒为 regora（与 bootstrap-ci.sh 一致），库按环境区分
DB_USER="regora"

usage() {
  sed -n '3,21p' "$0"
  exit 0
}

parse_args() {
  while [[ $# -gt 0 ]]; do
    case $1 in
      --env)            ENVIRONMENT="$2"; shift 2 ;;
      --file)           PG_FILE="$2"; shift 2 ;;
      --redis-file)     REDIS_FILE="$2"; shift 2 ;;
      --latest)         USE_LATEST=1; shift ;;
      --only-pg)        ONLY_PG=1; shift ;;
      --only-redis)     ONLY_REDIS=1; shift ;;
      --yes)            ASSUME_YES=1; shift ;;
      --no-safety-backup) NO_SAFETY_BACKUP=1; shift ;;
      --list)           LIST_ONLY=1; shift ;;
      --help|-h)        usage ;;
      *)                log_die "未知参数: $1" ;;
    esac
  done

  if [ "$ENVIRONMENT" != "production" ] && [ "$ENVIRONMENT" != "test" ]; then
    log_die "无效的环境参数: $ENVIRONMENT (仅支持 production 或 test)"
  fi

  if [ "$ENVIRONMENT" = "test" ]; then
    DB_NAME="regora_test"
    BACKUP_DIR="/backups/test"
  else
    DB_NAME="regora"
    BACKUP_DIR="/var/backups/regora"
  fi

  if [ "$ONLY_PG" = "1" ] && [ "$ONLY_REDIS" = "1" ]; then
    log_die "--only-pg 与 --only-redis 互斥"
  fi
}

check_root() {
  if [ "${EUID:-$(id -u)}" -ne 0 ]; then
    log_die "请使用 root 用户运行此脚本"
  fi
}

# 解析 PG 备份文件路径：--file 优先；否则 --latest 取最新（优先非 safety）
# 文件名含时间戳 YYYYMMDD_HHMMSS，bash glob 按名字升序展开即按时间升序，
# 迭代到最后一个即为最新。
resolve_pg_file() {
  if [ -n "$PG_FILE" ]; then
    [ -f "$PG_FILE" ] || log_die "备份文件不存在: $PG_FILE"
    return
  fi

  if [ "$USE_LATEST" != "1" ]; then
    return  # 仅 Redis 还原时不需要 PG 文件
  fi

  local f latest=""
  for f in "$BACKUP_DIR"/regora_backup_*.dump; do
    [ -e "$f" ] || continue
    case "$(basename "$f")" in *safety*) continue ;; esac
    latest="$f"  # 不断覆盖，最终保留字典序最后（最新）的一个
  done
  if [ -z "$latest" ]; then
    for f in "$BACKUP_DIR"/regora_backup_*.dump; do
      [ -e "$f" ] || continue
      latest="$f"
    done
  fi
  [ -n "$latest" ] || log_die "未找到 PG 备份文件 ($BACKUP_DIR/regora_backup_*.dump)"
  PG_FILE="$latest"
}

# 倒序打印一组文件（最新在前）
_print_files_desc() {
  local label="$1"; shift
  local -a arr=("$@")
  log_info "${label} ($BACKUP_DIR):"
  if [ "${#arr[@]}" -gt 0 ]; then
    local i
    for ((i = ${#arr[@]} - 1; i >= 0; i--)); do
      printf '  %s  %s\n' \
        "$(date -r "${arr[$i]}" '+%Y-%m-%d %H:%M' 2>/dev/null || echo '?')" \
        "$(basename "${arr[$i]}")"
    done
  else
    echo "  （无）"
  fi
}

list_backups() {
  local f
  local -a pgs=() redises=()
  for f in "$BACKUP_DIR"/regora_backup_*.dump; do
    [ -e "$f" ] || continue
    pgs+=("$f")
  done
  for f in "$BACKUP_DIR"/regora_redis_*.rdb.gz; do
    [ -e "$f" ] || continue
    redises+=("$f")
  done

  _print_files_desc "PostgreSQL 备份" "${pgs[@]}"
  echo
  _print_files_desc "Redis 备份" "${redises[@]}"
}

confirm_restore() {
  if [ "$ASSUME_YES" = "1" ]; then
    return 0
  fi
  if [ ! -t 0 ]; then
    log_die "非交互终端，需加 --yes 确认还原"
  fi
  echo
  log_warn "即将清空并还原数据库 [$DB_NAME] / Redis，当前数据将被覆盖！"
  read -r -p "确认还原？输入大写 YES 继续: " reply
  if [ "$reply" != "YES" ]; then
    log_die "已取消"
  fi
}

# 还原前安全备份（仅当要还原 PG 时）
pre_restore_safety_backup() {
  if [ "$NO_SAFETY_BACKUP" = "1" ]; then
    log_warn "已跳过还原前安全备份（--no-safety-backup）"
    return
  fi
  mkdir -p "$BACKUP_DIR"

  local timestamp safety_file tmp_file
  timestamp="$(date +%Y%m%d_%H%M%S)"
  safety_file="$BACKUP_DIR/regora_backup_safety_${timestamp}.dump"
  tmp_file="$(sudo -u postgres mktemp /tmp/regora_safety_XXXXXX.dump)"
  trap 'rm -f "$tmp_file"' EXIT

  log_info "生成还原前安全备份..."
  if ! sudo -u postgres pg_dump --format=custom --no-owner --no-acl -f "$tmp_file" "$DB_NAME" 2>/dev/null; then
    rm -f "$tmp_file"
    trap - EXIT
    log_warn "安全备份失败（数据库可能为空或不可达），继续还原"
    return
  fi
  mv "$tmp_file" "$safety_file"
  trap - EXIT
  chmod 600 "$safety_file"
  log_success "安全备份完成: $safety_file"
}

restore_pg() {
  if [ -z "$PG_FILE" ]; then
    return
  fi
  log_info "还原 PostgreSQL: $PG_FILE → $DB_NAME"

  # 完整性校验
  if ! sudo -u postgres pg_restore -l "$PG_FILE" >/dev/null 2>&1; then
    log_die "备份文件不可读或损坏: $PG_FILE"
  fi

  log_warn "建议在还原前停止应用（pm2 stop），否则连接被强制断开会产生 5xx 直到还原完成"
  log_info "终止到 $DB_NAME 的现有连接..."
  sudo -u postgres psql -d postgres -tAc \
    "SELECT pg_terminate_backend(pid) FROM pg_stat_activity WHERE datname = '$DB_NAME' AND pid <> pg_backend_pid();" \
    >/dev/null 2>&1 || true

  # DROP DATABASE WITH (FORCE)（PG13+）一并终止残留连接；CREATE 后为空库，避免扩展依赖冲突
  log_info "重建数据库 $DB_NAME..."
  sudo -u postgres psql -d postgres -c "DROP DATABASE IF EXISTS \"$DB_NAME\" WITH (FORCE);"
  sudo -u postgres psql -d postgres -c "CREATE DATABASE \"$DB_NAME\";"

  log_info "pg_restore 载入..."
  if ! sudo -u postgres pg_restore \
      --no-owner \
      --no-acl \
      --exit-on-error \
      --dbname="$DB_NAME" \
      "$PG_FILE"; then
    log_die "pg_restore 失败（安全备份见 $BACKUP_DIR/regora_backup_safety_*.dump）"
  fi

  log_info "把对象所有权归还给 $DB_USER（Prisma migration 需要）..."
  # 库级归属（连到维护库 postgres 执行）
  sudo -u postgres psql -d postgres \
    -c "ALTER DATABASE \"$DB_NAME\" OWNER TO \"$DB_USER\";" \
    -c "GRANT ALL PRIVILEGES ON DATABASE \"$DB_NAME\" TO \"$DB_USER\";"
  # schema 归属 + 默认权限（连到目标库执行）
  sudo -u postgres psql -d "$DB_NAME" \
    -c "ALTER SCHEMA public OWNER TO \"$DB_USER\";" \
    -c "GRANT ALL ON SCHEMA public TO \"$DB_USER\";" \
    -c "ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON TABLES TO \"$DB_USER\";" \
    -c "ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON SEQUENCES TO \"$DB_USER\";"
  # 把 public 下已还原的表/视图/序列 re-own 给应用用户
  # （生成 ALTER 语句再执行；不在 DO block 内用 psql 变量——psql 不在 dollar-quote 内做变量替换）
  sudo -u postgres psql -d "$DB_NAME" -tAc \
    "SELECT 'ALTER ' || CASE WHEN relkind='S' THEN 'SEQUENCE' ELSE 'TABLE' END \
       || ' public.' || quote_ident(relname) \
       || ' OWNER TO ' || quote_ident('$DB_USER') || ';' \
     FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace \
     WHERE n.nspname='public' AND relkind IN ('r','p','v','m','f','S');" \
    | sudo -u postgres psql -d "$DB_NAME"

  log_success "PostgreSQL 还原完成"
}

# 探测 redis 服务名（redis / redis-server）
redis_service_name() {
  if systemctl list-unit-files 2>/dev/null | grep -qE '^redis\.service'; then
    echo "redis"
  elif systemctl list-unit-files 2>/dev/null | grep -qE '^redis-server\.service'; then
    echo "redis-server"
  else
    echo ""
  fi
}

restore_redis() {
  if [ -z "$REDIS_FILE" ]; then
    return
  fi
  [ -f "$REDIS_FILE" ] || log_die "Redis 备份文件不存在: $REDIS_FILE"
  log_info "还原 Redis: $REDIS_FILE"

  if ! command -v redis-cli >/dev/null 2>&1; then
    log_die "未安装 redis-cli"
  fi

  # 停服前先取 dir / dbfilename / 属主
  local redis_dir redis_dbfile redis_rdb redis_user svc
  redis_dir="$(redis-cli CONFIG GET dir 2>/dev/null | tail -1 | tr -d '[:space:]')"
  redis_dbfile="$(redis-cli CONFIG GET dbfilename 2>/dev/null | tail -1 | tr -d '[:space:]')"
  redis_rdb="${redis_dir}/${redis_dbfile}"
  if [ -z "$redis_dir" ] || [ -z "$redis_dbfile" ]; then
    log_die "无法获取 Redis dir/dbfilename 配置"
  fi
  redis_user="$(stat -c '%U' "$redis_rdb" 2>/dev/null || echo redis)"

  svc="$(redis_service_name)"
  if [ -z "$svc" ]; then
    log_warn "未找到 redis systemd 服务，尝试直接替换 RDB（不停服，存在数据竞争风险）"
  else
    log_info "停止 Redis ($svc)..."
    systemctl stop "$svc"
  fi

  gunzip -c "$REDIS_FILE" > "$redis_rdb"
  chown "${redis_user}:${redis_user}" "$redis_rdb" 2>/dev/null || true
  chmod 640 "$redis_rdb" 2>/dev/null || true

  if [ -n "$svc" ]; then
    log_info "启动 Redis ($svc)..."
    systemctl start "$svc"
    sleep 1
    if ! redis-cli PING >/dev/null 2>&1; then
      log_die "Redis 启动后 PING 失败，请检查 systemctl status $svc"
    fi
  fi
  log_success "Redis 还原完成"
}

main() {
  parse_args "$@"
  check_root

  if [ "$LIST_ONLY" = "1" ]; then
    list_backups
    exit 0
  fi

  # 决定还原范围
  if [ "$ONLY_REDIS" != "1" ]; then
    resolve_pg_file
  fi
  if [ "$ONLY_PG" = "1" ]; then
    REDIS_FILE=""
  fi

  if [ -z "$PG_FILE" ] && [ -z "$REDIS_FILE" ]; then
    log_die "未指定要还原的内容：使用 --file/--latest 还原 PG，或 --redis-file/--only-redis 还原 Redis"
  fi

  log_info "还原环境: $ENVIRONMENT | 数据库: $DB_NAME"
  [ -n "$PG_FILE" ] && log_info "PG 备份: $PG_FILE"
  [ -n "$REDIS_FILE" ] && log_info "Redis 备份: $REDIS_FILE"

  confirm_restore

  # 仅在还原 PG 时做安全备份（Redis 还原不触发）
  if [ -n "$PG_FILE" ]; then
    pre_restore_safety_backup
    restore_pg
  fi
  if [ -n "$REDIS_FILE" ]; then
    restore_redis
  fi

  log_success "还原完成！"
}

main "$@"

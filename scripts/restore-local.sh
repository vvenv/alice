#!/bin/bash
# 本地数据库还原脚本（macOS 开发机）
# 把 ./backups/<env>/ 下的备份（db:pull 拉取的远程产物）还原到本地 postgres + 可选 Redis。
#
# 用法:
#   ./scripts/restore-local.sh --list                          # 列出可用备份
#   ./scripts/restore-local.sh --latest                        # 还原最新 PG 备份
#   ./scripts/restore-local.sh --file <path>                   # 还原指定 PG 备份
#   ./scripts/restore-local.sh --latest --redis-file <rdb.gz>  # 同时还原 Redis
#   ./scripts/restore-local.sh --latest --only-pg              # 仅 PG
#   ./scripts/restore-local.sh --redis-file <rdb.gz> --only-redis
#   ./scripts/restore-local.sh --latest --yes                  # 跳过确认（自动化）
#   ./scripts/restore-local.sh --latest --no-safety-backup
#   ./scripts/restore-local.sh --latest --db-name regora_test  # 还原到其他本地库
#
# 与 restore.sh（服务器版）的区别:
#   - 不要求 root，以当前 macOS 用户运行（需为 postgres superuser，Homebrew 默认满足）
#   - 无 sudo -u postgres；systemctl → brew services
#   - 备份来源: ./backups/<env>/（db:pull 产物）
#   - 安全备份目录: ./backups/local-safety/
#   - 目标库默认 regora（--db-name 覆盖），应用用户恒为 regora
#
# 行为:
#   - 默认还原前对本地目标库做安全备份（regora_backup_safety_<ts>.dump）
#   - PG: 终止连接 → DROP/CREATE DATABASE → pg_restore → re-own 给 regora
#   - Redis: brew services stop → 替换 dump.rdb → brew services start
#   - 破坏性操作前要求交互确认（大写 YES），非交互需 --yes

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
# shellcheck source=lib/log.sh
source "${SCRIPT_DIR}/lib/log.sh"

BACKUP_ENV="production"
DB_NAME="regora"
DB_USER="regora"
PG_FILE=""
REDIS_FILE=""
USE_LATEST=0
ONLY_PG=0
ONLY_REDIS=0
ASSUME_YES=0
NO_SAFETY_BACKUP=0
LIST_ONLY=0

BACKUP_DIR=""
SAFETY_DIR=""

usage() {
  sed -n '3,27p' "$0"
  exit 0
}

parse_args() {
  while [ $# -gt 0 ]; do
    case $1 in
      --env)              BACKUP_ENV="$2"; shift 2 ;;
      --db-name)          DB_NAME="$2"; shift 2 ;;
      --file)             PG_FILE="$2"; shift 2 ;;
      --redis-file)       REDIS_FILE="$2"; shift 2 ;;
      --latest)           USE_LATEST=1; shift ;;
      --only-pg)          ONLY_PG=1; shift ;;
      --only-redis)       ONLY_REDIS=1; shift ;;
      --yes)              ASSUME_YES=1; shift ;;
      --no-safety-backup) NO_SAFETY_BACKUP=1; shift ;;
      --list)             LIST_ONLY=1; shift ;;
      --help|-h)          usage ;;
      *)                  log_die "未知参数: $1" ;;
    esac
  done

  if [ "$BACKUP_ENV" != "production" ] && [ "$BACKUP_ENV" != "test" ]; then
    log_die "无效的 --env: $BACKUP_ENV (仅支持 production 或 test)"
  fi

  if [ "$ONLY_PG" = "1" ] && [ "$ONLY_REDIS" = "1" ]; then
    log_die "--only-pg 与 --only-redis 互斥"
  fi

  BACKUP_DIR="$ROOT/backups/$BACKUP_ENV"
  SAFETY_DIR="$ROOT/backups/local-safety"
}

# 校验本地前置：psql/pg_restore/pg_dump 可用，当前用户是 superuser，regora 角色存在
check_prereqs() {
  command -v psql >/dev/null 2>&1 || log_die "未安装 psql (Homebrew: brew install postgresql@18)"
  command -v pg_restore >/dev/null 2>&1 || log_die "未安装 pg_restore"
  command -v pg_dump >/dev/null 2>&1 || log_die "未安装 pg_dump"

  local is_super
  is_super="$(psql -d postgres -tAc "SELECT rolsuper FROM pg_roles WHERE rolname=current_user" 2>/dev/null | tr -d '[:space:]')"
  if [ "$is_super" != "t" ]; then
    log_die "当前 postgres 用户无 superuser 权限，无法 DROP/CREATE DATABASE（Homebrew 默认 superuser 为当前 macOS 用户）"
  fi

  local has_role
  has_role="$(psql -d postgres -tAc "SELECT 1 FROM pg_roles WHERE rolname='$DB_USER'" 2>/dev/null | tr -d '[:space:]')"
  if [ "$has_role" != "1" ]; then
    log_die "postgres 角色 '$DB_USER' 不存在，请先创建（参考 bootstrap-ci.sh 或 psql -c 'CREATE USER $DB_USER'）"
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

# 倒序打印一组文件（最新在前）。macOS date 支持 -r <file>
# 自己 glob 备份目录，避免 bash 3.2 空数组 + set -u 的 unbound variable 问题
_print_files_desc() {
  local label="$1" pattern="$2"
  local -a arr=()
  local f
  for f in "$BACKUP_DIR"/$pattern; do
    [ -e "$f" ] || continue
    arr+=("$f")
  done

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
  _print_files_desc "PostgreSQL 备份" 'regora_backup_*.dump'
  echo
  _print_files_desc "Redis 备份" 'regora_redis_*.rdb.gz'
}

confirm_restore() {
  if [ "$ASSUME_YES" = "1" ]; then
    return 0
  fi
  if [ ! -t 0 ]; then
    log_die "非交互终端，需加 --yes 确认还原"
  fi
  echo
  log_warn "即将清空并还原本地数据库 [$DB_NAME] / Redis，当前数据将被覆盖！"
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
  mkdir -p "$SAFETY_DIR"

  local timestamp safety_file tmp_file
  timestamp="$(date +%Y%m%d_%H%M%S)"
  safety_file="$SAFETY_DIR/regora_backup_safety_${timestamp}.dump"
  tmp_file="$(mktemp "${SAFETY_DIR}/.safety_XXXXXX.dump")"
  trap 'rm -f "$tmp_file"' EXIT

  log_info "生成还原前安全备份（本地 $DB_NAME）..."
  # 目标库可能不存在或为空，pg_dump 失败时跳过
  if ! pg_dump --format=custom --no-owner --no-acl -f "$tmp_file" "$DB_NAME" 2>/dev/null; then
    rm -f "$tmp_file"
    trap - EXIT
    log_warn "安全备份失败（库可能不存在或为空），继续还原"
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
  log_info "还原 PostgreSQL: $PG_FILE → 本地 $DB_NAME"

  # 完整性校验
  if ! pg_restore -l "$PG_FILE" >/dev/null 2>&1; then
    log_die "备份文件不可读或损坏: $PG_FILE"
  fi

  log_info "终止到 $DB_NAME 的现有连接..."
  psql -d postgres -tAc \
    "SELECT pg_terminate_backend(pid) FROM pg_stat_activity WHERE datname = '$DB_NAME' AND pid <> pg_backend_pid();" \
    >/dev/null 2>&1 || true

  # DROP DATABASE WITH (FORCE)（PG13+）；CREATE 后为空库，避免扩展依赖冲突
  # CREATE 时直接 OWNER 给 DB_USER，省去后续 ALTER DATABASE
  log_info "重建本地数据库 $DB_NAME..."
  psql -d postgres -v ON_ERROR_STOP=1 -c "DROP DATABASE IF EXISTS \"$DB_NAME\" WITH (FORCE);"
  psql -d postgres -v ON_ERROR_STOP=1 -c "CREATE DATABASE \"$DB_NAME\" OWNER \"$DB_USER\";"

  log_info "pg_restore 载入..."
  # pg_dump custom 产物含 CREATE EXTENSION IF NOT EXISTS vector（pre-data），pg_restore 会自动建扩展
  if ! pg_restore \
      --no-owner \
      --no-acl \
      --exit-on-error \
      --dbname="$DB_NAME" \
      "$PG_FILE"; then
    log_die "pg_restore 失败（安全备份见 $SAFETY_DIR/regora_backup_safety_*.dump）"
  fi

  log_info "把对象所有权归还给 $DB_USER（Prisma migration 需要）..."
  # schema 归属 + 默认权限（连到目标库执行）
  psql -d "$DB_NAME" -v ON_ERROR_STOP=1 \
    -c "ALTER SCHEMA public OWNER TO \"$DB_USER\";" \
    -c "GRANT ALL ON SCHEMA public TO \"$DB_USER\";" \
    -c "ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON TABLES TO \"$DB_USER\";" \
    -c "ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON SEQUENCES TO \"$DB_USER\";"
  # 把 public 下已还原的表/视图/序列 re-own 给应用用户
  # （生成 ALTER 语句再执行；不在 DO block 内用 psql 变量——psql 不在 dollar-quote 内做变量替换）
  psql -d "$DB_NAME" -tAc \
    "SELECT 'ALTER ' || CASE WHEN relkind='S' THEN 'SEQUENCE' ELSE 'TABLE' END \
       || ' public.' || quote_ident(relname) \
       || ' OWNER TO ' || quote_ident('$DB_USER') || ';' \
     FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace \
     WHERE n.nspname='public' AND relkind IN ('r','p','v','m','f','S');" \
    | psql -d "$DB_NAME"

  log_success "PostgreSQL 还原完成"
}

restore_redis() {
  if [ -z "$REDIS_FILE" ]; then
    return
  fi
  [ -f "$REDIS_FILE" ] || log_die "Redis 备份文件不存在: $REDIS_FILE"
  log_info "还原 Redis: $REDIS_FILE"

  command -v redis-cli >/dev/null 2>&1 || log_die "未安装 redis-cli"
  command -v brew >/dev/null 2>&1 || log_die "未安装 Homebrew（本脚本用 brew services 管理 Redis）"

  # 停服前先取 dir / dbfilename
  local redis_dir redis_dbfile redis_rdb
  redis_dir="$(redis-cli CONFIG GET dir 2>/dev/null | tail -1 | tr -d '[:space:]')"
  redis_dbfile="$(redis-cli CONFIG GET dbfilename 2>/dev/null | tail -1 | tr -d '[:space:]')"
  redis_rdb="${redis_dir}/${redis_dbfile}"
  if [ -z "$redis_dir" ] || [ -z "$redis_dbfile" ]; then
    log_die "无法获取 Redis dir/dbfilename 配置"
  fi

  log_info "停止 Redis (brew services stop redis)..."
  brew services stop redis >/dev/null 2>&1 || true

  gunzip -c "$REDIS_FILE" > "$redis_rdb"
  # macOS 当前用户即 redis 进程用户，无需 chown
  chmod 640 "$redis_rdb" 2>/dev/null || true

  log_info "启动 Redis (brew services start redis)..."
  if ! brew services start redis >/dev/null 2>&1; then
    log_die "brew services start redis 失败"
  fi
  sleep 1
  if ! redis-cli PING >/dev/null 2>&1; then
    log_die "Redis 启动后 PING 失败，请检查 brew services info redis"
  fi
  log_success "Redis 还原完成"
}

main() {
  parse_args "$@"
  check_prereqs

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

  log_info "本地还原 | 备份目录: $BACKUP_DIR | 目标库: $DB_NAME | 应用用户: $DB_USER"
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

  log_success "本地还原完成！"
}

main "$@"

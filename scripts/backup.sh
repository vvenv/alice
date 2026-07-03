#!/bin/bash
# 数据库备份脚本（在服务器上以 root 运行；由 backup-cron.sh 定时或手动调用）
# 备份 PostgreSQL（pg_dump custom 格式，pg_restore 还原）+ Redis（RDB 快照）
#
# 用法:
#   ./scripts/backup.sh --env production      # 默认
#   ./scripts/backup.sh --env test
#   ./scripts/backup.sh --help
#
# 备份产物:
#   PostgreSQL: <BACKUP_DIR>/regora_backup_<时间戳>.dump   (pg_restore / restore.sh 还原)
#   Redis:      <BACKUP_DIR>/regora_redis_backup_<时间戳>.rdb.gz
#
# 备份目录:
#   production → /var/backups/regora
#   test       → /backups/test
#
# 文件名模式 regora_backup_*.dump / regora_redis_*.rdb.gz 被 backup-cron.sh 的保留策略引用，
# 改动需同步。安全备份（restore.sh 生成）命名为 regora_backup_safety_*.dump，同样命中保留策略。

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=lib/log.sh
source "${SCRIPT_DIR}/lib/log.sh"

ENVIRONMENT="production"
DATABASE_BACKUP_COMPRESS="${DATABASE_BACKUP_COMPRESS:-6}"

usage() {
  sed -n '3,20p' "$0"
  exit 0
}

parse_args() {
  while [[ $# -gt 0 ]]; do
    case $1 in
      --env)
        ENVIRONMENT="$2"
        shift 2
        ;;
      --help|-h)
        usage
        ;;
      *)
        log_error "未知参数: $1"
        exit 1
        ;;
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

  log_info "备份环境: $ENVIRONMENT"
  log_info "数据库名称: $DB_NAME"
  log_info "备份目录: $BACKUP_DIR"
}

check_root() {
  if [ "${EUID:-$(id -u)}" -ne 0 ]; then
    log_die "请使用 root 用户运行此脚本"
  fi
}

# 等待 Redis BGSAVE 完成：轮询 LASTSAVE 时间戳直到推进，替代固定 sleep
wait_redis_bgsave() {
  local before after attempts
  before="$(redis-cli LASTSAVE 2>/dev/null | tr -d '[:space:]')"
  if [ -z "$before" ]; then
    log_warn "无法获取 Redis LASTSAVE，回退到固定等待 5s"
    sleep 5
    return
  fi

  # 若正在 BGSAVE，redis-cli 会返回提示但不报错；触发一次以确保有新快照
  redis-cli BGSAVE >/dev/null 2>&1 || true

  attempts=0
  while [ "$attempts" -lt 60 ]; do
    after="$(redis-cli LASTSAVE 2>/dev/null | tr -d '[:space:]')"
    if [ -n "$after" ] && [ "$after" -gt "$before" ]; then
      return
    fi
    sleep 1
    attempts=$((attempts + 1))
  done
  log_warn "Redis BGSAVE 在 60s 内未完成，继续使用当前 RDB"
}

backup_database() {
  log_info "备份数据库..."
  mkdir -p "$BACKUP_DIR"

  local timestamp backup_file tmp_file size
  timestamp="$(date +%Y%m%d_%H%M%S)"
  backup_file="$BACKUP_DIR/regora_backup_${timestamp}.dump"
  tmp_file="$(sudo -u postgres mktemp /tmp/regora_backup_XXXXXX.dump)"

  # 任一退出路径都清理临时文件（EXIT trap 在成功 mv 后清除）
  trap 'rm -f "$tmp_file"' EXIT

  if ! sudo -u postgres pg_dump \
      --format=custom \
      --no-owner \
      --no-acl \
      --compress="$DATABASE_BACKUP_COMPRESS" \
      -f "$tmp_file" \
      "$DB_NAME"; then
    log_die "pg_dump 失败"
  fi

  # 完整性校验：能列出 TOC 说明 dump 可被 pg_restore 读取
  if ! sudo -u postgres pg_restore -l "$tmp_file" >/dev/null 2>&1; then
    rm -f "$tmp_file"
    trap - EXIT
    log_die "备份文件完整性校验失败: $tmp_file"
  fi

  mv "$tmp_file" "$backup_file"
  trap - EXIT
  chmod 600 "$backup_file"

  size="$(du -h "$backup_file" | cut -f1)"
  log_success "数据库备份完成: $backup_file ($size)"
}

backup_redis() {
  log_info "备份 Redis 数据..."
  mkdir -p "$BACKUP_DIR"

  if ! command -v redis-cli >/dev/null 2>&1; then
    log_warn "未安装 redis-cli，跳过 Redis 备份"
    return
  fi
  if ! redis-cli PING >/dev/null 2>&1; then
    log_warn "Redis 不可达，跳过 Redis 备份"
    return
  fi

  local timestamp backup_file redis_dir redis_dbfile redis_rdb
  timestamp="$(date +%Y%m%d_%H%M%S)"
  backup_file="$BACKUP_DIR/regora_redis_backup_${timestamp}.rdb.gz"

  wait_redis_bgsave

  redis_dir="$(redis-cli CONFIG GET dir | tail -1 | tr -d '[:space:]')"
  redis_dbfile="$(redis-cli CONFIG GET dbfilename | tail -1 | tr -d '[:space:]')"
  redis_rdb="${redis_dir}/${redis_dbfile}"

  if [ -f "$redis_rdb" ]; then
    cp "$redis_rdb" "${backup_file%.gz}"
    gzip "${backup_file%.gz}"
    chmod 600 "$backup_file"
    log_success "Redis 备份完成: $backup_file"
  else
    log_warn "Redis RDB 文件不存在 ($redis_rdb)，跳过 Redis 备份"
  fi
}

main() {
  parse_args "$@"
  check_root

  log_info "开始备份 (目录: $BACKUP_DIR)..."
  backup_database
  backup_redis

  log_success "备份完成！"
}

main "$@"
